--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local STARTUP_WAIT_TIMEOUT_SECONDS = 10

local GiantBuildModeConfig: any
local GiantStructureCatalog: any
local GiantRealmSaveSchema: any
local ResourceFlowState: any
local SnareTrapConfig: any
local SnareTrapState: any

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

local placedStructureById: { [string]: AcceptedStructurePlacementState? } = {}
local snareTrapByTrapId: { [string]: any? } = {}
local lastRequestAtByUserId: { [number]: number? } = {}
local lastSnareTrapPlacementAtByUserId: { [number]: number? } = {}
local snareTrapSequence = 0
local realmOwnerUserId: number? = nil
local globalEnv: any = getfenv()

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
	SnareTrapConfig = requireChildModule(config, "SnareTrapConfig")
	local structureCatalogModuleName = GiantBuildModeConfig.StructureCatalogModuleName
	if type(structureCatalogModuleName) ~= "string" or structureCatalogModuleName == "" then
		error("startup_dependency_invalid giant_structure_catalog_module_name")
	end
	GiantStructureCatalog = requireChildModule(config, structureCatalogModuleName)
	GiantRealmSaveSchema = requireChildModule(giantRealm, "GiantRealmSaveSchema")
	SnareTrapState = requireChildModule(giantRealm, "SnareTrapState")
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

local function applySnareTrapArtifactAttributes(artifact: any, snapshot: any)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.TrapId, snapshot.trapId)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.Status, snapshot.status)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.Armed, snapshot.armed)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.TriggeredAt, snapshot.triggeredAt)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.TriggeredByUserId, snapshot.triggeredByUserId)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.ResolvedAt, snapshot.resolvedAt)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.ResolvedByUserId, snapshot.resolvedByUserId)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.ExpiresAt, snapshot.expiresAt)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.TriggerRadiusStuds, snapshot.triggerRadiusStuds)
	setArtifactAttribute(artifact, SnareTrapConfig.Attributes.PlacedAt, snapshot.placedAt)
end

local function materializeSnareTrapArtifact(record: any)
	local snapshot = SnareTrapState.BuildSnapshot(record, os.clock())
	if snapshot == nil then
		return
	end

	local mapFolder = ensureChildFolder(Workspace, "Map")
	local giantStructuresFolder = ensureChildFolder(mapFolder, "GiantStructures")
	removeChildFolderByName(giantStructuresFolder, snapshot.trapId)

	local artifact = createFolder(snapshot.trapId, giantStructuresFolder)
	setArtifactAttribute(artifact, "StructureId", snapshot.structureId)
	setArtifactAttribute(artifact, "PlacedByUserId", snapshot.placedByUserId)
	setArtifactAttribute(artifact, "PlacedAt", snapshot.placedAt)
	setArtifactAttribute(artifact, "OccupiedBoxCount", 1)
	applySnareTrapArtifactAttributes(artifact, snapshot)
	debugLog(string.format("Materialized snare trap artifact trapId=%s", snapshot.trapId))
end

local function updateSnareTrapArtifact(record: any, now: number)
	local snapshot = SnareTrapState.BuildSnapshot(record, now)
	if snapshot == nil then
		return
	end

	local mapFolder = ensureChildFolder(Workspace, "Map")
	local giantStructuresFolder = ensureChildFolder(mapFolder, "GiantStructures")
	local artifact = giantStructuresFolder:FindFirstChild(snapshot.trapId)
	if artifact ~= nil then
		applySnareTrapArtifactAttributes(artifact, snapshot)
	end
end

local function clearGiantStructureArtifacts()
	local mapFolder = ensureChildFolder(Workspace, "Map")
	local giantStructuresFolder = ensureChildFolder(mapFolder, "GiantStructures")
	local children = giantStructuresFolder:GetChildren()
	for _, child in ipairs(children) do
		removeChildFolderByName(giantStructuresFolder, child.Name)
	end
end

local function clearSnareTrapArtifacts()
	local structureIds = {}
	for trapId in pairs(snareTrapByTrapId) do
		table.insert(structureIds, trapId)
	end
	for _, trapId in ipairs(structureIds) do
		snareTrapByTrapId[trapId] = nil
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

local function isSnareTrapStructure(structureId: string): boolean
	local definition = GiantStructureCatalog[structureId]
	return type(definition) == "table" and definition.category == "trap"
end

local function getVectorDistance(a: { x: number, y: number, z: number }, b: { x: number, y: number, z: number }): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getFirstOccupiedCenter(request: StructurePlacementRequest): { x: number, y: number, z: number }?
	local occupiedBox = request.proposedOccupiedSpace[1]
	if occupiedBox == nil then
		return nil
	end
	return occupiedBox.worldCenter
end

local function collectBaseParts(node: any, output: { any })
	if node == nil then
		return
	end
	if type(node.IsA) == "function" and node:IsA("BasePart") then
		table.insert(output, node)
	end
	if type(node.GetChildren) == "function" then
		for _, child in ipairs(node:GetChildren()) do
			collectBaseParts(child, output)
		end
		return
	end
	if type(node._Children) == "table" then
		for _, child in pairs(node._Children) do
			collectBaseParts(child, output)
		end
	end
end

local function getSnareTrapPlacementAnchors(): { any }
	local anchors: { any } = {}
	local mapFolder = Workspace:FindFirstChild("Map")
	if mapFolder == nil then
		return anchors
	end

	for _, folderName in ipairs({ "Objectives", "EscapeRoutes", "Spawns", "CaptureZones", "RescueEntryRoutes" }) do
		local folder = mapFolder:FindFirstChild(folderName)
		if folder ~= nil then
			collectBaseParts(folder, anchors)
		end
	end

	return anchors
end

local function snareTrapProtectedReason(anchor: any): string
	local name = tostring(anchor.Name)
	local parentName = if anchor.Parent ~= nil then tostring(anchor.Parent.Name) else ""
	if string.find(name, "Objective", 1, true) ~= nil or string.find(parentName, "Objectives", 1, true) ~= nil then
		return "snare_trap_near_objective"
	end
	if string.find(name, "Spawn", 1, true) ~= nil or string.find(parentName, "Spawns", 1, true) ~= nil then
		return "snare_trap_near_spawn"
	end
	if string.find(name, "Capture", 1, true) ~= nil or string.find(parentName, "CaptureZones", 1, true) ~= nil then
		return "snare_trap_near_capture_zone"
	end
	if string.find(name, "Rescue", 1, true) ~= nil or string.find(parentName, "RescueEntryRoutes", 1, true) ~= nil then
		return "snare_trap_near_rescue_entry"
	end
	return "snare_trap_near_exit"
end

local function validateSnareTrapPlacement(request: StructurePlacementRequest): (boolean, string?)
	local trapCenter = getFirstOccupiedCenter(request)
	if trapCenter == nil then
		return false, "snare_trap_missing_center"
	end

	for _, anchor in ipairs(getSnareTrapPlacementAnchors()) do
		local anchorPosition = anchor.Position
		if type(anchorPosition) == "table" then
			if getVectorDistance(trapCenter, anchorPosition) < SnareTrapConfig.NoBuildRadiusStuds then
				return false, snareTrapProtectedReason(anchor)
			end
		end
	end

	return true, nil
end

local function createSnareTrapState(request: StructurePlacementRequest, placedByUserId: number, placedAt: number)
	local trapCenter = getFirstOccupiedCenter(request)
	if trapCenter == nil then
		return nil
	end

	snareTrapSequence += 1
	local trapId = string.format("%s_%d", request.structureId, snareTrapSequence)
	return SnareTrapState.NewRecord(
		trapId,
		request.structureId,
		placedByUserId,
		placedAt,
		trapCenter,
		SnareTrapConfig.TriggerRadiusStuds,
		SnareTrapConfig.TriggerDurationSeconds
	)
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
	if math.abs(a.worldCenter.x - b.worldCenter.x) >= (a.halfExtents.x + b.halfExtents.x) then
		return false
	end
	if math.abs(a.worldCenter.y - b.worldCenter.y) >= (a.halfExtents.y + b.halfExtents.y) then
		return false
	end
	if math.abs(a.worldCenter.z - b.worldCenter.z) >= (a.halfExtents.z + b.halfExtents.z) then
		return false
	end
	return true
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

local function getSnareTrapRechargeRemaining(userId: number, now: number): number
	local last = lastSnareTrapPlacementAtByUserId[userId]
	if type(last) ~= "number" then
		return 0
	end
	local recharge = tonumber(SnareTrapConfig.PlacementRechargeSeconds) or 0
	return math.max(0, recharge - (now - last))
end

local function getSortedSnareTrapIds(): { string }
	local trapIds = {}
	for trapId in pairs(snareTrapByTrapId) do
		table.insert(trapIds, trapId)
	end
	table.sort(trapIds, function(a: string, b: string): boolean
		local left = snareTrapByTrapId[a]
		local right = snareTrapByTrapId[b]
		if left ~= nil and right ~= nil and left.placedAt ~= right.placedAt then
			return left.placedAt < right.placedAt
		end
		return a < b
	end)
	return trapIds
end

local function countActiveSnareTrapsForUser(userId: number, now: number): number
	local count = 0
	for _, trapId in ipairs(getSortedSnareTrapIds()) do
		local record = snareTrapByTrapId[trapId]
		if record ~= nil and record.placedByUserId == userId then
			local snapshot = SnareTrapState.BuildSnapshot(record, now)
			if snapshot ~= nil and (snapshot.armed or snapshot.status == SnareTrapState.Status.Triggered) then
				count += 1
			end
		end
	end
	return count
end

local function removeOldestReplaceableSnareTrapForUser(userId: number, now: number): string?
	for _, trapId in ipairs(getSortedSnareTrapIds()) do
		local record = snareTrapByTrapId[trapId]
		if record ~= nil and record.placedByUserId == userId then
			local snapshot = SnareTrapState.BuildSnapshot(record, now)
			if snapshot ~= nil and snapshot.armed then
				snareTrapByTrapId[trapId] = nil
				local mapFolder = ensureChildFolder(Workspace, "Map")
				local giantStructuresFolder = ensureChildFolder(mapFolder, "GiantStructures")
				removeChildFolderByName(giantStructuresFolder, trapId)
				return trapId
			end
		end
	end
	for _, trapId in ipairs(getSortedSnareTrapIds()) do
		local record = snareTrapByTrapId[trapId]
		if record ~= nil and record.placedByUserId == userId then
			local snapshot = SnareTrapState.BuildSnapshot(record, now)
			if snapshot ~= nil and SnareTrapState.IsTerminalStatus(snapshot.status) then
				snareTrapByTrapId[trapId] = nil
				local mapFolder = ensureChildFolder(Workspace, "Map")
				local giantStructuresFolder = ensureChildFolder(mapFolder, "GiantStructures")
				removeChildFolderByName(giantStructuresFolder, trapId)
				return trapId
			end
		end
	end
	return nil
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

	if isSnareTrapStructure(request.structureId) then
		local placementAllowed, placementReason = validateSnareTrapPlacement(request)
		if not placementAllowed then
			rejectPlacement(player, placementReason or "snare_trap_invalid_placement")
			logPlacementOutcome("rejected", player, request.structureId, placementReason)
			return
		end
	end

	if not isPlayerAlive(player) then
		rejectPlacement(player, "player_not_alive")
		logPlacementOutcome("rejected", player, request.structureId, "player_not_alive")
		return
	end

	if not isSnareTrapStructure(request.structureId) and placedStructureById[request.structureId] ~= nil then
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

	local placedAt = os.clock()
	if isSnareTrapStructure(request.structureId) and getSnareTrapRechargeRemaining(player.UserId, placedAt) > 0 then
		rejectPlacement(player, "snare_trap_recharge_active")
		logPlacementOutcome("rejected", player, request.structureId, "snare_trap_recharge_active")
		return
	end

	local spent, flowSnapshot, spendError, woodCost, stoneCost = spendStructureCost(request.structureId)
	if not spent then
		local reason = spendError or "insufficient_resources"
		rejectPlacement(player, reason)
		logPlacementOutcome("rejected", player, request.structureId, reason)
		return
	end

	local accepted: AcceptedStructurePlacementState = {
		structureId = request.structureId,
		placedByUserId = player.UserId,
		placedAt = placedAt,
		proposedOccupiedSpace = request.proposedOccupiedSpace,
	}

	if isSnareTrapStructure(request.structureId) then
		local trapRecord = createSnareTrapState(request, player.UserId, placedAt)
		if trapRecord == nil then
			rejectPlacement(player, "snare_trap_invalid_state")
			logPlacementOutcome("rejected", player, request.structureId, "snare_trap_invalid_state")
			ResourceFlowState.AddStoredAtomic(woodCost, stoneCost, "GiantBuildModeRollback:" .. request.structureId)
			return
		end
		if
			countActiveSnareTrapsForUser(player.UserId, placedAt)
			>= (tonumber(SnareTrapConfig.MaxActiveTrapsPerGiant) or 3)
		then
			removeOldestReplaceableSnareTrapForUser(player.UserId, placedAt)
		end

		local appliedTrap, trapError = pcall(function()
			snareTrapByTrapId[trapRecord.trapId] = trapRecord
			materializeSnareTrapArtifact(trapRecord)
		end)
		if not appliedTrap then
			snareTrapByTrapId[trapRecord.trapId] = nil
			ResourceFlowState.AddStoredAtomic(woodCost, stoneCost, "GiantBuildModeRollback:" .. request.structureId)
			local applyFailureReason = string.format("snare_trap_apply_failed detail=%s", tostring(trapError))
			rejectPlacement(player, applyFailureReason)
			logPlacementOutcome("rejected", player, request.structureId, applyFailureReason)
			return
		end
		lastSnareTrapPlacementAtByUserId[player.UserId] = placedAt
	else
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
		if state ~= nil then
			result[structureId] = state
		end
	end
	return result
end

local function GetSaveablePlacedStructures(): { [string]: AcceptedStructurePlacementState }
	local result: { [string]: AcceptedStructurePlacementState } = {}
	for structureId, state in pairs(placedStructureById) do
		if state ~= nil and not isSnareTrapStructure(structureId) then
			result[structureId] = state
		end
	end
	return result
end

local function findSnareTrapRecord(trapIdOrStructureId: string): (string?, any?)
	local direct = snareTrapByTrapId[trapIdOrStructureId]
	if direct ~= nil then
		return trapIdOrStructureId, direct
	end
	for _, trapId in ipairs(getSortedSnareTrapIds()) do
		local record = snareTrapByTrapId[trapId]
		if record ~= nil and record.structureId == trapIdOrStructureId then
			return trapId, record
		end
	end
	return nil, nil
end

local function getEventLogQueryApi(): any?
	local api = rawget(globalEnv, "_EventLogService_QueryAPI")
	if type(api) == "table" and type(api.RecordEvent) == "function" then
		return api
	end
	return nil
end

local function getTinyfolkStatusQueryApi(): any?
	local api = rawget(globalEnv, "_TinyfolkStatusService_QueryAPI")
	if type(api) == "table" then
		return api
	end
	return nil
end

local function clearSnareTrapStunIfTriggered(record: any, now: number)
	if type(record) ~= "table" then
		return
	end
	if type(record.triggeredByUserId) ~= "number" then
		return
	end
	local statusApi = getTinyfolkStatusQueryApi()
	if statusApi ~= nil and type(statusApi.ClearConditionForUserId) == "function" then
		pcall(statusApi.ClearConditionForUserId, record.triggeredByUserId, "stun", now)
	end
end

local function coarseGridCell(position: any): any
	local gridSize = tonumber(SnareTrapConfig.CoarseAlertGridSizeStuds) or 50
	gridSize = math.max(1, gridSize)
	return {
		x = math.floor(position.x / gridSize),
		z = math.floor(position.z / gridSize),
	}
end

local function recordSnareTrapEvent(message: string, severity: string, snapshot: any)
	local eventLog = getEventLogQueryApi()
	if eventLog == nil or snapshot == nil then
		return
	end
	pcall(
		eventLog.RecordEvent,
		"snare_trap",
		message,
		severity,
		snapshot.resolvedAt or snapshot.triggeredAt or os.clock(),
		{
			trapId = snapshot.trapId,
			structureId = snapshot.structureId,
			placedByUserId = snapshot.placedByUserId,
			status = snapshot.status,
			coarseGridCell = coarseGridCell(snapshot.center),
		}
	)
end

local function getPlayerByUserId(userId: number): any?
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function isTinyfolkUserId(userId: number): boolean
	local player = getPlayerByUserId(userId)
	return player ~= nil and player:GetAttribute("Role") == "Tinyfolk"
end

local function validateTimedInteraction(position: any, startedAt: any, completedAt: any, record: any): (boolean, string)
	if type(position) ~= "table" then
		return false, "snare_trap_interaction_position_invalid"
	end
	if type(startedAt) ~= "number" or type(completedAt) ~= "number" then
		return false, "snare_trap_interaction_time_invalid"
	end
	if completedAt < startedAt then
		return false, "snare_trap_interaction_time_invalid"
	end
	if completedAt - startedAt < math.max(0, tonumber(SnareTrapConfig.InteractionDurationSeconds) or 2) then
		return false, "snare_trap_interaction_incomplete"
	end
	if
		not SnareTrapState.IsInteractionInRange(
			record,
			position,
			tonumber(SnareTrapConfig.InteractionRadiusStuds) or 10
		)
	then
		return false, "snare_trap_interaction_out_of_range"
	end
	return true, "accepted"
end

local function GetPlacedSnareTrap(trapIdOrStructureId: string): any?
	local _trapId, trapRecord = findSnareTrapRecord(trapIdOrStructureId)
	if trapRecord == nil then
		return nil
	end
	return SnareTrapState.BuildSnapshot(trapRecord, os.clock())
end

local function GetAllPlacedSnareTraps(): { [string]: any }
	local result: { [string]: any } = {}
	local snapshotAt = os.clock()
	for trapId, trapRecord in pairs(snareTrapByTrapId) do
		result[trapId] = SnareTrapState.BuildSnapshot(trapRecord, snapshotAt)
	end
	return result
end

local function ResolveSnareTrapContact(userId: number, position: any, at: number?): any
	if type(userId) ~= "number" or type(position) ~= "table" then
		return {
			accepted = false,
			reason = "snare_trap_contact_invalid",
			trap = nil,
		}
	end
	if not isTinyfolkUserId(userId) then
		return {
			accepted = false,
			reason = "snare_trap_contact_requires_tinyfolk",
			trap = nil,
		}
	end

	local resolvedAt = if type(at) == "number" then at else os.clock()
	for _, trapId in ipairs(getSortedSnareTrapIds()) do
		local trapRecord = snareTrapByTrapId[trapId]
		local triggered, reason, nextRecord = SnareTrapState.ResolveContact(trapRecord, userId, position, resolvedAt)
		if triggered == true and nextRecord ~= nil then
			snareTrapByTrapId[trapId] = nextRecord
			updateSnareTrapArtifact(nextRecord, resolvedAt)
			local snapshot = SnareTrapState.BuildSnapshot(nextRecord, resolvedAt)
			recordSnareTrapEvent("snare_trap_triggered", "warn", snapshot)
			return {
				accepted = true,
				reason = reason,
				trap = snapshot,
			}
		end
		if nextRecord ~= nil and nextRecord.status == SnareTrapState.Status.Expired then
			snareTrapByTrapId[trapId] = nextRecord
			clearSnareTrapStunIfTriggered(nextRecord, resolvedAt)
			updateSnareTrapArtifact(nextRecord, resolvedAt)
			recordSnareTrapEvent("expired", "info", SnareTrapState.BuildSnapshot(nextRecord, resolvedAt))
		end
	end

	return {
		accepted = false,
		reason = "snare_trap_not_triggered",
		trap = nil,
	}
end

local function ResolveSnareTrapDisarm(
	userId: number,
	trapId: string,
	position: any,
	startedAt: number,
	completedAt: number
): any
	if not isTinyfolkUserId(userId) then
		return { accepted = false, reason = "snare_trap_disarm_requires_tinyfolk", trap = nil }
	end
	local resolvedTrapId, record = findSnareTrapRecord(trapId)
	if resolvedTrapId == nil or record == nil then
		return { accepted = false, reason = "snare_trap_missing", trap = nil }
	end
	local interactionOk, interactionReason = validateTimedInteraction(position, startedAt, completedAt, record)
	if not interactionOk then
		return { accepted = false, reason = interactionReason, trap = SnareTrapState.BuildSnapshot(record, completedAt) }
	end
	local disarmed, reason, nextRecord = SnareTrapState.ResolveDisarm(record, userId, completedAt)
	if not disarmed or nextRecord == nil then
		return {
			accepted = false,
			reason = reason,
			trap = SnareTrapState.BuildSnapshot(nextRecord or record, completedAt),
		}
	end
	snareTrapByTrapId[resolvedTrapId] = nextRecord
	updateSnareTrapArtifact(nextRecord, completedAt)
	local snapshot = SnareTrapState.BuildSnapshot(nextRecord, completedAt)
	recordSnareTrapEvent("disarmed", "info", snapshot)
	return { accepted = true, reason = reason, trap = snapshot }
end

local function ResolveSnareTrapRescue(
	rescuerUserId: number,
	trappedUserId: number,
	trapId: string,
	position: any,
	startedAt: number,
	completedAt: number
): any
	if not isTinyfolkUserId(rescuerUserId) then
		return { accepted = false, reason = "snare_trap_rescue_requires_tinyfolk", trap = nil }
	end
	if rescuerUserId == trappedUserId then
		return { accepted = false, reason = "snare_trap_rescue_requires_teammate", trap = nil }
	end
	local resolvedTrapId, record = findSnareTrapRecord(trapId)
	if resolvedTrapId == nil or record == nil then
		return { accepted = false, reason = "snare_trap_missing", trap = nil }
	end
	if record.triggeredByUserId ~= trappedUserId then
		return {
			accepted = false,
			reason = "snare_trap_rescue_target_mismatch",
			trap = SnareTrapState.BuildSnapshot(record, completedAt),
		}
	end
	local interactionOk, interactionReason = validateTimedInteraction(position, startedAt, completedAt, record)
	if not interactionOk then
		return { accepted = false, reason = interactionReason, trap = SnareTrapState.BuildSnapshot(record, completedAt) }
	end
	local rescued, reason, nextRecord = SnareTrapState.ResolveRescue(record, rescuerUserId, completedAt)
	if not rescued or nextRecord == nil then
		return {
			accepted = false,
			reason = reason,
			trap = SnareTrapState.BuildSnapshot(nextRecord or record, completedAt),
		}
	end
	snareTrapByTrapId[resolvedTrapId] = nextRecord
	updateSnareTrapArtifact(nextRecord, completedAt)
	local statusApi = getTinyfolkStatusQueryApi()
	if statusApi ~= nil and type(statusApi.ClearConditionForUserId) == "function" then
		pcall(statusApi.ClearConditionForUserId, trappedUserId, "stun", completedAt)
	end
	local snapshot = SnareTrapState.BuildSnapshot(nextRecord, completedAt)
	recordSnareTrapEvent("rescued", "info", snapshot)
	return { accepted = true, reason = reason, trap = snapshot }
end

local function RefreshSnareTrapLegality(now: number?): any
	local resolvedAt = if type(now) == "number" then now else os.clock()
	local refreshed = {}
	for _, trapId in ipairs(getSortedSnareTrapIds()) do
		local record = snareTrapByTrapId[trapId]
		if record ~= nil then
			local expired, _, expiredRecord = SnareTrapState.ResolveExpiry(record, resolvedAt)
			if expired and expiredRecord ~= nil then
				snareTrapByTrapId[trapId] = expiredRecord
				clearSnareTrapStunIfTriggered(expiredRecord, resolvedAt)
				updateSnareTrapArtifact(expiredRecord, resolvedAt)
				local snapshot = SnareTrapState.BuildSnapshot(expiredRecord, resolvedAt)
				recordSnareTrapEvent("expired", "info", snapshot)
				table.insert(refreshed, snapshot)
			elseif record.status == SnareTrapState.Status.Armed or record.status == SnareTrapState.Status.Triggered then
				local fakeRequest: StructurePlacementRequest = {
					structureId = record.structureId,
					proposedOccupiedSpace = {
						{
							tag = "snare",
							worldCenter = record.center,
							halfExtents = { x = 1, y = 1, z = 1 },
						},
					},
				}
				local legal = validateSnareTrapPlacement(fakeRequest)
				if not legal then
					local invalidated, _, invalidatedRecord = SnareTrapState.ResolveInvalidated(record, resolvedAt)
					if invalidated and invalidatedRecord ~= nil then
						snareTrapByTrapId[trapId] = invalidatedRecord
						clearSnareTrapStunIfTriggered(invalidatedRecord, resolvedAt)
						updateSnareTrapArtifact(invalidatedRecord, resolvedAt)
						local snapshot = SnareTrapState.BuildSnapshot(invalidatedRecord, resolvedAt)
						recordSnareTrapEvent("invalidated", "info", snapshot)
						table.insert(refreshed, snapshot)
					end
				end
			end
		end
	end
	return refreshed
end

local function ResetSnareTrapRechargeForTests(userId: number?)
	if type(userId) == "number" then
		lastSnareTrapPlacementAtByUserId[userId] = nil
		return
	end
	lastSnareTrapPlacementAtByUserId = {}
end

local function IsStructurePlaced(structureId: string): boolean
	if type(structureId) ~= "string" or structureId == "" then
		return false
	end
	return placedStructureById[structureId] ~= nil
end

local function isValidOwnerUserId(ownerUserId: any): boolean
	if type(ownerUserId) ~= "number" then
		return false
	end
	if ownerUserId ~= ownerUserId or ownerUserId == math.huge or ownerUserId == -math.huge then
		return false
	end
	if ownerUserId <= 0 then
		return false
	end
	return true
end

local function getEmergencyReinforcementQueryApi(): any
	local globalValue = globalEnv
	if type(globalValue._EmergencyReinforcementService_QueryAPI) == "table" then
		return globalValue._EmergencyReinforcementService_QueryAPI
	end
	return nil
end

local function getShrineQueryApi(): any
	local globalValue = globalEnv
	if type(globalValue._ShrineService_QueryAPI) == "table" then
		return globalValue._ShrineService_QueryAPI
	end
	return nil
end

local function getRescueContractQueryApi(): any
	local globalValue = globalEnv
	if type(globalValue._RescueContractService_QueryAPI) == "table" then
		return globalValue._RescueContractService_QueryAPI
	end
	return nil
end

local function BuildSaveSnapshot(ownerUserId: any): (any?, string?)
	if not isValidOwnerUserId(ownerUserId) then
		return nil, "save_snapshot_owner_user_id_invalid"
	end

	local emergencyReinforcementState = nil
	local reinforcementQueryApi = getEmergencyReinforcementQueryApi()
	if reinforcementQueryApi ~= nil then
		if type(reinforcementQueryApi.BuildPersistenceState) ~= "function" then
			return nil, "emergency_reinforcement_build_persistence_missing"
		end

		emergencyReinforcementState = reinforcementQueryApi.BuildPersistenceState()
	end

	local shrinePersistenceState = nil
	local shrineQueryApi = getShrineQueryApi()
	if shrineQueryApi ~= nil then
		if type(shrineQueryApi.BuildPersistenceState) ~= "function" then
			return nil, "shrine_build_persistence_missing"
		end

		shrinePersistenceState = shrineQueryApi.BuildPersistenceState()
	end

	local rescuePersistenceState = nil
	local rescueContractQueryApi = getRescueContractQueryApi()
	if rescueContractQueryApi ~= nil then
		if type(rescueContractQueryApi.BuildPersistenceState) ~= "function" then
			return nil, "rescue_build_persistence_missing"
		end

		rescuePersistenceState = rescueContractQueryApi.BuildPersistenceState()
	end

	local root = GiantRealmSaveSchema.BuildSaveRoot(
		ownerUserId,
		GetSaveablePlacedStructures(),
		emergencyReinforcementState,
		shrinePersistenceState,
		rescuePersistenceState
	)
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

	local reinforcementQueryApi = getEmergencyReinforcementQueryApi()
	if root.emergencyReinforcement ~= nil then
		if reinforcementQueryApi == nil then
			return false, "emergency_reinforcement_query_api_missing"
		end
		if type(reinforcementQueryApi.ApplyPersistenceState) ~= "function" then
			return false, "emergency_reinforcement_apply_persistence_missing"
		end

		local appliedReinforcement, reinforcementReason =
			reinforcementQueryApi.ApplyPersistenceState(root.emergencyReinforcement)
		if not appliedReinforcement then
			return false, reinforcementReason or "emergency_reinforcement_apply_persistence_failed"
		end
	elseif reinforcementQueryApi ~= nil and type(reinforcementQueryApi.ApplyPersistenceState) == "function" then
		local appliedReinforcement, reinforcementReason = reinforcementQueryApi.ApplyPersistenceState(nil)
		if not appliedReinforcement then
			return false, reinforcementReason or "emergency_reinforcement_apply_persistence_failed"
		end
	end

	clearSnareTrapArtifacts()

	local shrineQueryApi = getShrineQueryApi()
	if root.shrinePersistence ~= nil then
		if shrineQueryApi == nil then
			return false, "shrine_query_api_missing"
		end
		if type(shrineQueryApi.ApplyPersistenceState) ~= "function" then
			return false, "shrine_apply_persistence_missing"
		end

		local appliedShrine, shrineReason = shrineQueryApi.ApplyPersistenceState(root.shrinePersistence)
		if not appliedShrine then
			return false, shrineReason or "shrine_apply_persistence_failed"
		end
	elseif shrineQueryApi ~= nil and type(shrineQueryApi.ApplyPersistenceState) == "function" then
		local appliedShrine, shrineReason = shrineQueryApi.ApplyPersistenceState(nil)
		if not appliedShrine then
			return false, shrineReason or "shrine_apply_persistence_failed"
		end
	end

	local rescueContractQueryApi = getRescueContractQueryApi()
	if root.rescuePersistence ~= nil then
		if rescueContractQueryApi == nil then
			return false, "rescue_query_api_missing"
		end
		if type(rescueContractQueryApi.ApplyPersistenceState) ~= "function" then
			return false, "rescue_apply_persistence_missing"
		end

		local appliedRescue, rescueReason = rescueContractQueryApi.ApplyPersistenceState(root.rescuePersistence)
		if not appliedRescue then
			return false, rescueReason or "rescue_apply_persistence_failed"
		end
	elseif rescueContractQueryApi ~= nil and type(rescueContractQueryApi.ApplyPersistenceState) == "function" then
		local appliedRescue, rescueReason = rescueContractQueryApi.ApplyPersistenceState(nil)
		if not appliedRescue then
			return false, rescueReason or "rescue_apply_persistence_failed"
		end
	end

	local structureIds = {}
	for structureId in pairs(placedStructureById) do
		table.insert(structureIds, structureId)
	end
	for _, structureId in ipairs(structureIds) do
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

globalEnv._GiantBuildModeService_QueryAPI = {
	GetPlacedStructure = GetPlacedStructure,
	GetAllPlacedStructures = GetAllPlacedStructures,
	GetPlacedSnareTrap = GetPlacedSnareTrap,
	GetAllPlacedSnareTraps = GetAllPlacedSnareTraps,
	ResolveSnareTrapContact = ResolveSnareTrapContact,
	ResolveSnareTrapDisarm = ResolveSnareTrapDisarm,
	ResolveSnareTrapRescue = ResolveSnareTrapRescue,
	RefreshSnareTrapLegality = RefreshSnareTrapLegality,
	ResetSnareTrapRechargeForTests = ResetSnareTrapRechargeForTests,
	IsStructurePlaced = IsStructurePlaced,
	BuildSaveSnapshot = BuildSaveSnapshot,
	ApplySaveSnapshot = ApplySaveSnapshot,
}

globalEnv._GiantBuildModeService_Registry = placedStructureById

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
end)
