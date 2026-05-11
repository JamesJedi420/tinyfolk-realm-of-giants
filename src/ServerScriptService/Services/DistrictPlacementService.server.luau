--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STARTUP_WAIT_TIMEOUT_SECONDS = 10

local DistrictPlacementConfig: any
local RealmChunkAssemblySchema: any
local RealmAssemblyPrototypeFixture: any
local RealmDistrictPlacementValidator: any

local REMOTES_FOLDER_NAME = "Remotes"

-- DistrictPlacementRequest is not ConstructionBuildRequest.
-- Do not route district placement through ConstructionBuildRequest or ConstructionService.
-- These are separate systems with separate remotes, separate request shapes, and separate mutation targets.
-- ConstructionBuildRequest: mutates existing BasePart site state (IsBuilt, visual state).
-- DistrictPlacementRequest: validates a proposed district placement and records it in the
-- server-owned placement registry. World content creation is a later TIN-175 gate integration slice.

type PlacedDistrictState = {
	districtId: string,
	placedByUserId: number,
	placedAt: number,
	proposedOccupiedSpace: { any },
}

local placedDistrictById: { [string]: PlacedDistrictState } = {}
local lastRequestAtByUserId: { [number]: number? } = {}

local prototypeAssemblyOutput: any = nil

local function debugLog(message: string)
	print(string.format("[DistrictPlacementService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[DistrictPlacementService] %s", message))
end

debugLog("Booting service")

local function requireChildModule(parent: Instance, childName: string): any
	debugLog(string.format(
		"Resolving dependency child=%s parent=%s timeout=%ds",
		childName,
		parent:GetFullName(),
		STARTUP_WAIT_TIMEOUT_SECONDS
	))
	local child = parent:WaitForChild(childName, STARTUP_WAIT_TIMEOUT_SECONDS)
	if not child then
		error(string.format("startup_dependency_missing child=%s parent=%s", childName, parent:GetFullName()))
	end

	local ok, moduleOrError = pcall(function()
		return require(child)
	end)
	if not ok then
		error(string.format(
			"startup_dependency_require_failed child=%s error=%s",
			childName,
			tostring(moduleOrError)
		))
	end

	debugLog(string.format("Resolved dependency child=%s", childName))
	return moduleOrError
end

local function resolveDependencies()
	local shared = ReplicatedStorage:WaitForChild("Shared", STARTUP_WAIT_TIMEOUT_SECONDS)
	if not shared then
		error("startup_dependency_missing child=Shared parent=ReplicatedStorage")
	end

	local config = shared:WaitForChild("Config", STARTUP_WAIT_TIMEOUT_SECONDS)
	if not config then
		error("startup_dependency_missing child=Config parent=ReplicatedStorage.Shared")
	end

	local realmAssembly = shared:WaitForChild("RealmAssembly", STARTUP_WAIT_TIMEOUT_SECONDS)
	if not realmAssembly then
		error("startup_dependency_missing child=RealmAssembly parent=ReplicatedStorage.Shared")
	end

	DistrictPlacementConfig = requireChildModule(config, "DistrictPlacementConfig")
	RealmChunkAssemblySchema = requireChildModule(realmAssembly, "RealmChunkAssemblySchema")
	RealmAssemblyPrototypeFixture = requireChildModule(realmAssembly, "RealmAssemblyPrototypeFixture")
	RealmDistrictPlacementValidator = requireChildModule(realmAssembly, "RealmDistrictPlacementValidator")
end

local dependenciesReady, dependencyError = pcall(resolveDependencies)
if not dependenciesReady then
	debugWarn(string.format(
		"Startup failed during dependency resolution error=%s",
		tostring(dependencyError)
	))
	return
end

debugLog("Dependency resolution complete")

-- Build prototype assembly output for placement validation.
-- This is a placeholder: the real assembled realm descriptor will be supplied by the
-- realm assembly pipeline once that runtime path is defined (out of TIN-188 scope).
local prototypeOutputBuilt, prototypeOutputOrError = pcall(function()
	return RealmChunkAssemblySchema.BuildAssemblyOutput(
		RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
	)
end)
if not prototypeOutputBuilt then
	debugWarn(string.format(
		"Failed to build prototype assembly output error=%s",
		tostring(prototypeOutputOrError)
	))
	return
end

prototypeAssemblyOutput = prototypeOutputOrError
debugLog("Prototype assembly output ready")

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	debugLog("Created ReplicatedStorage.Remotes folder")
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		debugLog(string.format("Using existing ReplicatedStorage.Remotes.%s", remoteName))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	debugLog(string.format("Created ReplicatedStorage.Remotes.%s", remoteName))
	return remote
end

local function isCoolingDown(userId: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end
	return (os.clock() - last) < DistrictPlacementConfig.RequestCooldownSeconds
end

local function markRequest(userId: number)
	lastRequestAtByUserId[userId] = os.clock()
end

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function rejectPlacement(player: Player, reason: string)
	debugWarn(string.format(
		"Rejected DistrictPlacementRequest userId=%d reason=%s",
		player.UserId,
		reason
	))
end

local function logPlacementOutcome(status: string, player: Player, districtId: string, reason: string?)
	debugLog(string.format(
		"PlacementOutcome status=%s userId=%d districtId=%s reason=%s",
		status,
		player.UserId,
		districtId,
		tostring(reason)
	))
end

local function isVector3Data(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	return type(value.x) == "number" and type(value.y) == "number" and type(value.z) == "number"
end

-- Validates incoming payload shape and extracts a typed DistrictPlacementRequest.
-- Returns: valid (boolean), rejectionReason (string?), request (any)
local function validatePayload(payload: unknown): (boolean, string?, any)
	if type(payload) ~= "table" then
		return false, "malformed_payload", nil
	end

	local tbl = payload :: any

	if type(tbl.districtId) ~= "string" or tbl.districtId == "" then
		return false, "malformed_payload_district_id", nil
	end

	if type(tbl.proposedOccupiedSpace) ~= "table" then
		return false, "malformed_payload_occupied_space", nil
	end

	for i, box in ipairs(tbl.proposedOccupiedSpace) do
		if type(box) ~= "table" then
			return false, string.format("malformed_payload_box_entry index=%d", i), nil
		end
		if not isVector3Data(box.worldCenter) then
			return false, string.format("malformed_payload_box_fields index=%d field=worldCenter", i), nil
		end
		if not isVector3Data(box.halfExtents) then
			return false, string.format("malformed_payload_box_fields index=%d field=halfExtents", i), nil
		end
	end

	-- Typed DistrictPlacementRequest extracted from validated payload.
	local request: any = {
		districtId = tbl.districtId,
		proposedOccupiedSpace = tbl.proposedOccupiedSpace,
	}

	return true, nil, request
end

local remotesFolder = ensureRemotesFolder()
debugLog("Ensuring district placement remote")
local placementRemote = ensureRemoteEvent(remotesFolder, DistrictPlacementConfig.PlacementRemoteName)
debugLog(string.format("District placement remote ready name=%s", DistrictPlacementConfig.PlacementRemoteName))

placementRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	debugLog(string.format(
		"Received DistrictPlacementRequest userId=%d payloadType=%s",
		player.UserId,
		typeof(payload)
	))

	if isCoolingDown(player.UserId) then
		rejectPlacement(player, "request_cooldown")
		logPlacementOutcome("rejected", player, "<unknown>", "request_cooldown")
		return
	end

	markRequest(player.UserId)

	local payloadValid, payloadError, request = validatePayload(payload)
	if not payloadValid then
		local reason = payloadError or "malformed_payload"
		rejectPlacement(player, reason)
		logPlacementOutcome("rejected", player, "<unknown>", reason)
		return
	end

	if not isPlayerAlive(player) then
		rejectPlacement(player, "player_not_alive")
		logPlacementOutcome("rejected", player, request.districtId, "player_not_alive")
		return
	end

	local result = RealmDistrictPlacementValidator.ValidatePlacement(request, prototypeAssemblyOutput)

	if not result.accepted then
		local reasonCodes: { string } = {}
		for _, r in ipairs(result.rejectReasons) do
			table.insert(reasonCodes, r.code)
		end
		local reasonSummary = table.concat(reasonCodes, ";")
		rejectPlacement(player, string.format("placement_rejected_by_validator reasons=%s", reasonSummary))
		logPlacementOutcome("rejected", player, request.districtId, "placement_rejected_by_validator")
		return
	end

	-- Record accepted placement in server-owned in-memory registry.
	-- Workspace content creation is out of TIN-188 scope; that is TIN-175 gate integration work.
	placedDistrictById[request.districtId] = {
		districtId = request.districtId,
		placedByUserId = player.UserId,
		placedAt = os.clock(),
		proposedOccupiedSpace = request.proposedOccupiedSpace,
	}

	debugLog(string.format(
		"Accepted DistrictPlacementRequest userId=%d districtId=%s boxCount=%d",
		player.UserId,
		request.districtId,
		#request.proposedOccupiedSpace
	))
	logPlacementOutcome("accepted", player, request.districtId, nil)
end)

debugLog("District placement service ready")
