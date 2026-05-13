--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local STARTUP_WAIT_TIMEOUT_SECONDS = 10

local GiantBuildModeConfig: any
local GiantStructureCatalog: any
local GiantRealmSaveSchema: any
local ResourceFlowState: any

local REMOTES_FOLDER_NAME = "Remotes"

type StructureBoxInput = {
	tag: string?,
	worldCenter: { x: number, y: number, z: number },
	halfExtents: { x: number, y: number, z: number },
}

type StructurePlacementRequest = {
	structureId: string,
	proposedOccupiedSpace: { StructureBoxInput },
}

type AcceptedStructurePlacementState = {
	structureId: string,
	placedByUserId: number,
	placedAt: number,
	proposedOccupiedSpace: { StructureBoxInput },
}

local placedStructureById: { [string]: AcceptedStructurePlacementState } = {}
local lastRequestAtByUserId: { [number]: number? } = {}
local realmOwnerUserId: number? = nil

local function debugLog(message: string)
	print(string.format("[GiantBuildModeService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GiantBuildModeService] %s", message))
end

debugLog("Booting service")

local function requireChildModule(parent: Instance, childName: string): any
	debugLog(
		string.format(
			"Resolving dependency child=%s parent=%s timeout=%ds",
			childName,
			parent:GetFullName(),
			STARTUP_WAIT_TIMEOUT_SECONDS
		)
	)
	local child = parent:WaitForChild(childName, STARTUP_WAIT_TIMEOUT_SECONDS)
	if not child then
		error(string.format("startup_dependency_missing child=%s parent=%s", childName, parent:GetFullName()))
	end

	local ok, moduleOrError = pcall(function()
		return require(child)
	end)
	if not ok then
		error(string.format("startup_dependency_require_failed child=%s error=%s", childName, tostring(moduleOrError)))
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
	local giantRealm = shared:WaitForChild("GiantRealm", STARTUP_WAIT_TIMEOUT_SECONDS)
	if not giantRealm then
		error("startup_dependency_missing child=GiantRealm parent=ReplicatedStorage.Shared")
	end

	GiantBuildModeConfig = requireChildModule(config, "GiantBuildModeConfig")
	local structureCatalogModuleName = GiantBuildModeConfig.StructureCatalogModuleName
	if type(structureCatalogModuleName) ~= "string" or structureCatalogModuleName == "" then
		error("startup_dependency_invalid giant_structure_catalog_module_name")
	end
	GiantStructureCatalog = requireChildModule(config, structureCatalogModuleName)
	GiantRealmSaveSchema = requireChildModule(giantRealm, "GiantRealmSaveSchema")
	ResourceFlowState = requireChildModule(script.Parent, "ResourceFlowState")
end

local dependenciesReady, dependencyError = pcall(resolveDependencies)
if not dependenciesReady then
	debugWarn(string.format("Startup failed during dependency resolution error=%s", tostring(dependencyError)))
	return
end

debugLog("Dependency resolution complete")

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

local function createMockFolder(name: string, parent: any): any
	local folder: any = {
		Name = name,
		ClassName = "Folder",
		_Children = {},
		_Attributes = {},
	}

	function folder.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function folder.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function folder.GetChildren(self: any): { any }
		local children: { any } = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function folder.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function folder.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	folder.Parent = parent
	if type(parent._Children) == "table" then
		parent._Children[name] = folder
	end

	return folder
end

local function createFolder(name: string, parent: any): any
	if type(parent) == "table" and type(parent._Children) == "table" then
		return createMockFolder(name, parent)
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureChildFolder(parent: any, folderName: string): any
	local existing = parent:FindFirstChild(folderName)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end

	return createFolder(folderName, parent)
end

local function removeChildFolderByName(parent: any, childName: string)
	local existing = parent:FindFirstChild(childName)
	if existing == nil then
		return
	end

	if type(existing.Destroy) == "function" then
		existing:Destroy()
		return
	end

	if type(parent) == "table" then
		local children = rawget(parent, "_Children")
		if type(children) == "table" then
			rawset(children, childName, nil)
		end
	end
end

local function setArtifactAttribute(instance: any, attributeName: string, value: any)
	if type(instance.SetAttribute) == "function" then
		instance:SetAttribute(attributeName, value)
		return
	end

	if type(instance) == "table" then
		local attributes = rawget(instance, "_Attributes")
		if type(attributes) ~= "table" then
			attributes = {}
			rawset(instance, "_Attributes", attributes)
		end
		rawset(attributes, attributeName, value)
	end
end

local function materializeAcceptedWorkspaceArtifact(state: AcceptedStructurePlacementState)
	local mapFolder = ensureChildFolder(Workspace, "Map")
	local giantStructuresFolder = ensureChildFolder(mapFolder, "GiantStructures")

	removeChildFolderByName(giantStructuresFolder, state.structureId)

	local artifact = createFolder(state.structureId, giantStructuresFolder)
	setArtifactAttribute(artifact, "StructureId", state.structureId)
	setArtifactAttribute(artifact, "PlacedByUserId", state.placedByUserId)
	setArtifactAttribute(artifact, "PlacedAt", state.placedAt)
	setArtifactAttribute(artifact, "OccupiedBoxCount", #state.proposedOccupiedSpace)

	debugLog(string.format("Materialized giant structure artifact structureId=%s", state.structureId))
end

local function clearGiantStructureArtifacts()
	local mapFolder = ensureChildFolder(Workspace, "Map")
	local giantStructuresFolder = ensureChildFolder(mapFolder, "GiantStructures")
	local children = giantStructuresFolder:GetChildren()
	for _, child in ipairs(children) do
		removeChildFolderByName(giantStructuresFolder, child.Name)
	end
end

local function isCoolingDown(userId: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end

	return (os.clock() - last) < GiantBuildModeConfig.RequestCooldownSeconds
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
	if humanoid == nil then
		return false
	end

	return humanoid.Health > 0
end

local function isVector3Data(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if type(value.x) ~= "number" or type(value.y) ~= "number" or type(value.z) ~= "number" then
		return false
	end
	if value.x ~= value.x or value.y ~= value.y or value.z ~= value.z then
		return false
	end
	return true
end

local function isWithinWorldCoordinateLimit(vector: { x: number, y: number, z: number }): boolean
	local maxAny = GiantBuildModeConfig.MaxWorldCoordinateStuds
	if type(maxAny) ~= "number" then
		return false
	end
	local max: number = maxAny
	if math.abs(vector.x) > max then
		return false
	end
	if math.abs(vector.y) > max then
		return false
	end
	if math.abs(vector.z) > max then
		return false
	end
	return true
end

local function areHalfExtentsValid(halfExtents: { x: number, y: number, z: number }): boolean
	if halfExtents.x <= 0 or halfExtents.y <= 0 or halfExtents.z <= 0 then
		return false
	end

	local maxAny = GiantBuildModeConfig.MaxHalfExtentStuds
	if type(maxAny) ~= "number" then
		return false
	end
	local max: number = maxAny
	if halfExtents.x > max then
		return false
	end
	if halfExtents.y > max then
		return false
	end
	if halfExtents.z > max then
		return false
	end
	return true
end

-- Validates incoming payload shape and extracts a typed StructurePlacementRequest.
-- Returns: valid (boolean), rejectionReason (string?), request (StructurePlacementRequest?)
local function validatePayload(payload: unknown): (boolean, string?, StructurePlacementRequest?)
	if type(payload) ~= "table" then
		return false, "malformed_payload", nil
	end

	local tbl = payload :: any

	if type(tbl.structureId) ~= "string" or tbl.structureId == "" then
		return false, "malformed_payload_structure_id", nil
	end

	if type(tbl.proposedOccupiedSpace) ~= "table" then
		return false, "malformed_payload_occupied_space", nil
	end

	if #tbl.proposedOccupiedSpace < 1 then
		return false, "malformed_payload_occupied_space_empty", nil
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
		if not isWithinWorldCoordinateLimit(box.worldCenter) then
			return false, string.format("payload_box_world_center_out_of_bounds index=%d", i), nil
		end
		if not areHalfExtentsValid(box.halfExtents) then
			return false, string.format("payload_box_half_extents_invalid index=%d", i), nil
		end
		if box.tag ~= nil and type(box.tag) ~= "string" then
			return false, string.format("malformed_payload_box_fields index=%d field=tag", i), nil
		end
	end

	local request: StructurePlacementRequest = {
		structureId = tbl.structureId,
		proposedOccupiedSpace = tbl.proposedOccupiedSpace,
	}

	return true, nil, request
end

local function rejectPlacement(player: Player, reason: string)
	debugWarn(string.format("Rejected GiantStructurePlacementRequest userId=%d reason=%s", player.UserId, reason))
end

local function logPlacementOutcome(status: string, player: Player, structureId: string, reason: string?)
	debugLog(
		string.format(
			"PlacementOutcome status=%s userId=%d structureId=%s reason=%s",
			status,
			player.UserId,
			structureId,
			tostring(reason)
		)
	)
end

local function isKnownStructureId(structureId: string): boolean
	return GiantStructureCatalog[structureId] ~= nil
end

local function getStructureCost(structureId: string): (number?, number?)
	local definition = GiantStructureCatalog[structureId]
	if type(definition) ~= "table" then
		return nil, nil
	end

	local woodCost = definition.woodCost
	local stoneCost = definition.stoneCost
	if type(woodCost) ~= "number" or type(stoneCost) ~= "number" then
		return nil, nil
	end
	if woodCost < 0 or stoneCost < 0 then
		return nil, nil
	end

	return woodCost, stoneCost
end

local function spendStructureCost(structureId: string): (boolean, any, string?, number, number)
	local woodCost, stoneCost = getStructureCost(structureId)
	if woodCost == nil or stoneCost == nil then
		return false, ResourceFlowState.GetSnapshot(), "insufficient_resources", 0, 0
	end

	local spent, flowSnapshot, spendError =
		ResourceFlowState.SpendStoredAtomic(woodCost, stoneCost, "GiantBuildMode:" .. structureId)
	if not spent then
		debugWarn(
			string.format(
				"Rejected GiantStructurePlacementRequest structureId=%s reason=insufficient_resources detail=%s",
				structureId,
				tostring(spendError)
			)
		)
		return false, flowSnapshot, "insufficient_resources", woodCost, stoneCost
	end

	return true, flowSnapshot, nil, woodCost, stoneCost
end

local function isAuthorizedRealmOwner(player: Player): boolean
	return realmOwnerUserId == nil or realmOwnerUserId == player.UserId
end

local function boxesOverlap(a: StructureBoxInput, b: StructureBoxInput): boolean
	return math.abs(a.worldCenter.x - b.worldCenter.x) < (a.halfExtents.x + b.halfExtents.x)
		and math.abs(a.worldCenter.y - b.worldCenter.y) < (a.halfExtents.y + b.halfExtents.y)
		and math.abs(a.worldCenter.z - b.worldCenter.z) < (a.halfExtents.z + b.halfExtents.z)
end

local function getSortedPlacedStructureIds(): { string }
	local structureIds = {}
	for structureId in pairs(placedStructureById) do
		table.insert(structureIds, structureId)
	end
	table.sort(structureIds)
	return structureIds
end

local function overlapsAcceptedOccupiedSpace(request: StructurePlacementRequest): boolean
	for _, structureId in ipairs(getSortedPlacedStructureIds()) do
		local placed = placedStructureById[structureId]
		if placed then
			for _, incomingBox in ipairs(request.proposedOccupiedSpace) do
				for _, acceptedBox in ipairs(placed.proposedOccupiedSpace) do
					if boxesOverlap(incomingBox, acceptedBox) then
						return true
					end
				end
			end
		end
	end

	return false
end

local remotesFolder = ensureRemotesFolder()
debugLog("Ensuring giant structure placement remote")
local placementRemote = ensureRemoteEvent(remotesFolder, GiantBuildModeConfig.StructurePlacementRemoteName)
debugLog(
	string.format("Giant structure placement remote ready name=%s", GiantBuildModeConfig.StructurePlacementRemoteName)
)

placementRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	debugLog(
		string.format(
			"Received GiantStructurePlacementRequest userId=%d payloadType=%s",
			player.UserId,
			typeof(payload)
		)
	)

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

	if not request then
		rejectPlacement(player, "malformed_payload")
		logPlacementOutcome("rejected", player, "<unknown>", "malformed_payload")
		return
	end

	if not isKnownStructureId(request.structureId) then
		rejectPlacement(player, "structure_not_in_catalog")
		logPlacementOutcome("rejected", player, request.structureId, "structure_not_in_catalog")
		return
	end

	if not isPlayerAlive(player) then
		rejectPlacement(player, "player_not_alive")
		logPlacementOutcome("rejected", player, request.structureId, "player_not_alive")
		return
	end

	if placedStructureById[request.structureId] ~= nil then
		rejectPlacement(player, "structure_already_placed")
		logPlacementOutcome("rejected", player, request.structureId, "structure_already_placed")
		return
	end

	if not isAuthorizedRealmOwner(player) then
		rejectPlacement(player, "giant_realm_owner_mismatch")
		logPlacementOutcome("rejected", player, request.structureId, "giant_realm_owner_mismatch")
		return
	end

	if overlapsAcceptedOccupiedSpace(request) then
		rejectPlacement(player, "structure_occupied_space_overlap")
		logPlacementOutcome("rejected", player, request.structureId, "structure_occupied_space_overlap")
		return
	end

	local spent, flowSnapshot, spendError, woodCost, stoneCost = spendStructureCost(request.structureId)
	if not spent then
		local reason = spendError or "insufficient_resources"
		rejectPlacement(player, reason)
		logPlacementOutcome("rejected", player, request.structureId, reason)
		return
	end

	local placedAt = os.clock()
	local accepted: AcceptedStructurePlacementState = {
		structureId = request.structureId,
		placedByUserId = player.UserId,
		placedAt = placedAt,
		proposedOccupiedSpace = request.proposedOccupiedSpace,
	}

	local previousState = placedStructureById[request.structureId]
	local appliedPlacement, placementError = pcall(function()
		placedStructureById[request.structureId] = accepted
		materializeAcceptedWorkspaceArtifact(accepted)
	end)

	if not appliedPlacement then
		placedStructureById[request.structureId] = previousState
		ResourceFlowState.AddStoredAtomic(woodCost, stoneCost, "GiantBuildModeRollback:" .. request.structureId)
		local applyFailureReason = string.format("placement_apply_failed detail=%s", tostring(placementError))
		rejectPlacement(player, applyFailureReason)
		logPlacementOutcome("rejected", player, request.structureId, applyFailureReason)
		return
	end

	if realmOwnerUserId == nil then
		realmOwnerUserId = player.UserId
	end

	debugLog(
		string.format(
			"Accepted GiantStructurePlacementRequest userId=%d structureId=%s boxCount=%d woodCost=%.0f stoneCost=%.0f woodStored=%.0f stoneStored=%.0f",
			player.UserId,
			request.structureId,
			#request.proposedOccupiedSpace,
			woodCost,
			stoneCost,
			flowSnapshot.Wood.stored,
			flowSnapshot.Stone.stored
		)
	)
	logPlacementOutcome("accepted", player, request.structureId, nil)
end)

debugLog("Giant build mode service ready")

local function GetPlacedStructure(structureId: string): AcceptedStructurePlacementState?
	if type(structureId) ~= "string" or structureId == "" then
		return nil
	end
	return placedStructureById[structureId]
end

local function GetAllPlacedStructures(): { [string]: AcceptedStructurePlacementState }
	local result: { [string]: AcceptedStructurePlacementState } = {}
	for structureId, state in pairs(placedStructureById) do
		result[structureId] = state
	end
	return result
end

local function IsStructurePlaced(structureId: string): boolean
	if type(structureId) ~= "string" or structureId == "" then
		return false
	end
	return placedStructureById[structureId] ~= nil
end

local function isValidOwnerUserId(ownerUserId: any): boolean
	return type(ownerUserId) == "number"
		and ownerUserId == ownerUserId
		and ownerUserId ~= math.huge
		and ownerUserId ~= -math.huge
		and ownerUserId > 0
end

local function BuildSaveSnapshot(ownerUserId: any): (any?, string?)
	if not isValidOwnerUserId(ownerUserId) then
		return nil, "save_snapshot_owner_user_id_invalid"
	end

	local root = GiantRealmSaveSchema.BuildSaveRoot(ownerUserId, GetAllPlacedStructures())
	local valid, reason = GiantRealmSaveSchema.ValidateSaveRoot(root)
	if not valid then
		return nil, reason or "save_snapshot_invalid"
	end

	return root, nil
end

local function ApplySaveSnapshot(root: any): (boolean, string?)
	local valid, reason = GiantRealmSaveSchema.ValidateSaveRoot(root)
	if not valid then
		return false, reason or "save_root_invalid"
	end

	for structureId in pairs(placedStructureById) do
		placedStructureById[structureId] = nil
	end
	clearGiantStructureArtifacts()

	for _, record in ipairs(root.placedStructures) do
		local state: AcceptedStructurePlacementState = GiantRealmSaveSchema.SerializePlacedStructureRecord(record)
		placedStructureById[state.structureId] = state
		materializeAcceptedWorkspaceArtifact(state)
	end

	realmOwnerUserId = root.ownerUserId

	return true, nil
end

_G._GiantBuildModeService_QueryAPI = {
	GetPlacedStructure = GetPlacedStructure,
	GetAllPlacedStructures = GetAllPlacedStructures,
	IsStructurePlaced = IsStructurePlaced,
	BuildSaveSnapshot = BuildSaveSnapshot,
	ApplySaveSnapshot = ApplySaveSnapshot,
}

_G._GiantBuildModeService_Registry = placedStructureById

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
end)
