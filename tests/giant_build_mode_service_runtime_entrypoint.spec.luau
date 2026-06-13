--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local GiantBuildModeConfig = require("../src/ReplicatedStorage/Shared/Config/GiantBuildModeConfig")
local GiantStructureCatalog = require("../src/ReplicatedStorage/Shared/Config/GiantStructureCatalog")
local GiantRealmSaveSchema = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")
local globalEnv: any = getfenv()

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected %q got %q", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local warns: { string } = {}
local originalWarn = warn
warn = function(...: any)
	local packed: any = table.pack(...)
	local parts: { string } = {}
	for i = 1, packed.n :: number do
		table.insert(parts, tostring(packed[i]))
	end
	local line = table.concat(parts, " ")
	table.insert(warns, line)
	originalWarn(...)
end

local function makeNode(name: string, className: string?, fullName: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_FullName = fullName or name,
		_Children = {},
		_Attributes = {},
		Parent = nil,
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.GetFullName(self: any): string
		return self._FullName
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	function node.GetChildren(self: any): { any }
		local children: { any } = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function node.GetDescendants(self: any): { any }
		local descendants: { any } = {}
		local function walk(nodeToWalk: any)
			for _, child in pairs(nodeToWalk._Children) do
				table.insert(descendants, child)
				walk(child)
			end
		end
		walk(self)
		return descendants
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	child.Parent = parent
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireServer(self: any, player: any, payload: any)
		if self._Handler == nil then
			error(string.format("remote %s handler not connected", self.Name))
		end
		self._Handler(player, payload)
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
local giantPlacementRemote = makeRemoteEvent("GiantStructurePlacementRequest")
local constructionBuildRemote = makeRemoteEvent("ConstructionBuildRequest")
addChild(remotesFolder, "GiantStructurePlacementRequest", giantPlacementRemote)
addChild(remotesFolder, "ConstructionBuildRequest", constructionBuildRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
configFolder._Children["GiantBuildModeConfig"] = "../../ReplicatedStorage/Shared/Config/GiantBuildModeConfig"
configFolder._Children["GiantStructureCatalog"] = "../../ReplicatedStorage/Shared/Config/GiantStructureCatalog"
configFolder._Children["SnareTrapConfig"] = "../../ReplicatedStorage/Shared/Config/SnareTrapConfig"
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["EscapeConfig"] = "../../ReplicatedStorage/Shared/Config/EscapeConfig"
configFolder._Children["GiantRealmTreasuryConfig"] = "../../ReplicatedStorage/Shared/Config/GiantRealmTreasuryConfig"

local giantRealmFolder = makeNode("GiantRealm", "Folder", "ReplicatedStorage.Shared.GiantRealm")
giantRealmFolder._Children["GiantRealmSaveSchema"] = "../../ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema"
giantRealmFolder._Children["GiantRealmResourceState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState"
giantRealmFolder._Children["GiantRealmTreasuryPresentation"] =
	"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmTreasuryPresentation"
giantRealmFolder._Children["SnareTrapState"] = "../../ReplicatedStorage/Shared/GiantRealm/SnareTrapState"
giantRealmFolder._Children["GiantMacroRouteAccess"] = "../../ReplicatedStorage/Shared/GiantRealm/GiantMacroRouteAccess"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
addChild(workspaceService, "Map", mapFolder)

local objectivesFolder = makeNode("Objectives", "Folder", "Workspace.Map.Objectives")
local objectiveSite = makeNode("ObjectiveSite_A", "BasePart", "Workspace.Map.Objectives.ObjectiveSite_A")
objectiveSite.Position = { x = 20, y = 0, z = 20 }
addChild(objectivesFolder, "ObjectiveSite_A", objectiveSite)
addChild(mapFolder, "Objectives", objectivesFolder)

local escapeRoutesFolder = makeNode("EscapeRoutes", "Folder", "Workspace.Map.EscapeRoutes")
local escapeRoute = makeNode("EscapeRoute_A", "BasePart", "Workspace.Map.EscapeRoutes.EscapeRoute_A")
escapeRoute.Position = { x = 100, y = 0, z = 100 }
addChild(escapeRoutesFolder, "EscapeRoute_A", escapeRoute)
addChild(mapFolder, "EscapeRoutes", escapeRoutesFolder)

local giantRoutesFolder = makeNode("GiantRoutes", "Folder", "Workspace.Map.GiantRoutes")
local giantMacroRoute =
	makeNode("GiantRoute_PlazaToHearth", "BasePart", "Workspace.Map.GiantRoutes.GiantRoute_PlazaToHearth")
giantMacroRoute.Position = { x = 0, y = 0.38, z = -36 }
giantMacroRoute:SetAttribute("GiantOnlyRoute", true)
giantMacroRoute:SetAttribute("RouteEnabled", true)
giantMacroRoute:SetAttribute("WidthStuds", 18)
addChild(giantRoutesFolder, "GiantRoute_PlazaToHearth", giantMacroRoute)
addChild(mapFolder, "GiantRoutes", giantRoutesFolder)

local playerAddedConnections: { (any) -> () } = {}
local playerRemovingConnections: { (any) -> () } = {}
local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	_playerList = {},
	PlayerAdded = {
		Connect = function(_signal: any, callback: (any) -> ())
			table.insert(playerAddedConnections, callback)
		end,
	},
	PlayerRemoving = {
		Connect = function(_signal: any, callback: (any) -> ())
			table.insert(playerRemovingConnections, callback)
		end,
	},
	GetPlayers = function(self: any): { any }
		return self._playerList
	end,
}

local function clearRequestCooldownFor(player: any)
	for _, callback in ipairs(playerRemovingConnections) do
		callback(player)
	end
end

local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
-- String path stored directly to avoid child.Parent = parent on a string value
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = {
	Parent = scriptParent,
} :: any

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")

GiantStructureCatalog.GiantStructure_Runtime_C = {
	displayName = "Runtime Test Structure C",
	category = "utility",
	woodCost = 50,
	stoneCost = 50,
}
GiantStructureCatalog.GiantStructure_Runtime_D = {
	displayName = "Runtime Test Structure D",
	category = "utility",
	woodCost = 60,
	stoneCost = 60,
}
GiantStructureCatalog.GiantStructure_Runtime_E = {
	displayName = "Runtime Test Structure E",
	category = "utility",
	woodCost = 20,
	stoneCost = 20,
}
GiantStructureCatalog.GiantStructure_Runtime_F = {
	displayName = "Runtime Test Structure F",
	category = "utility",
	woodCost = 10,
	stoneCost = 10,
}
GiantStructureCatalog.GiantStructure_Runtime_G = {
	displayName = "Runtime Test Structure G",
	category = "utility",
	woodCost = 10,
	stoneCost = 10,
}
GiantStructureCatalog.GiantStructure_Runtime_Snare_B = {
	displayName = "Runtime Test Snare Trap B",
	category = "trap",
	woodCost = 10,
	stoneCost = 4,
}
GiantStructureCatalog.GiantStructure_Runtime_Snare_C = {
	displayName = "Runtime Test Snare Trap C",
	category = "trap",
	woodCost = 10,
	stoneCost = 4,
}
GiantStructureCatalog.GiantStructure_Runtime_Snare_D = {
	displayName = "Runtime Test Snare Trap D",
	category = "trap",
	woodCost = 10,
	stoneCost = 4,
}

local function makeAlivePlayer(userId: number, role: string?)
	local humanoid = {
		Health = 100,
	}
	local attributes = {
		Role = role or "Giant",
	}
	local character = {
		FindFirstChildOfClass = function(_self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}
	return {
		UserId = userId,
		Character = character,
		GetAttribute = function(_self: any, attributeName: string): any
			return attributes[attributeName]
		end,
		SetAttribute = function(_self: any, attributeName: string, value: any)
			attributes[attributeName] = value
		end,
	}
end

local function makeAcceptedPayloadAt(structureId: string, x: number, y: number, z: number): any
	return {
		structureId = structureId,
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = x, y = y, z = z },
				halfExtents = { x = 20, y = 8, z = 20 },
			},
		},
	}
end

local function makeAcceptedPayload(structureId: string): any
	return makeAcceptedPayloadAt(structureId, 120, 0, 300)
end

local function assertStoredTotals(expectedWood: number, expectedStone: number, label: string)
	local snapshot = ResourceFlowState.GetSnapshot()
	assertEqual(snapshot.Wood.stored, expectedWood, label .. " wood stored")
	assertEqual(snapshot.Stone.stored, expectedStone, label .. " stone stored")
end

local function assertStoredTotalsUnchanged(beforeSnapshot: any, label: string)
	local afterSnapshot = ResourceFlowState.GetSnapshot()
	assertEqual(afterSnapshot.Wood.stored, beforeSnapshot.Wood.stored, label .. " wood unchanged")
	assertEqual(afterSnapshot.Stone.stored, beforeSnapshot.Stone.stored, label .. " stone unchanged")
end

globalEnv._EmergencyReinforcementService_QueryAPI = {
	BuildPersistenceState = function(): any
		return {
			used = true,
			callStartedAt = 55,
			cooldownEndsAt = 100,
			triggeredByUserId = 1101,
			spawnedUserId = 1103,
			lastReason = "accepted",
			lastObjectiveId = "CallCenter_A",
		}
	end,
	_LastAppliedPersistenceState = nil,
	ApplyPersistenceState = function(_persistedState: any): (boolean, string?)
		globalEnv._EmergencyReinforcementService_QueryAPI._LastAppliedPersistenceState = _persistedState
		return true, nil
	end,
}

globalEnv._ShrineService_QueryAPI = {
	BuildPersistenceState = function(): any
		return {
			shrines = {
				{
					shrineId = "Shrine_B",
					isActive = false,
					essenceTotal = 15,
					tickCount = 5,
					lastTickAt = 99,
					activatedByUserId = nil,
				},
				{
					shrineId = "Shrine_A",
					isActive = true,
					essenceTotal = 40,
					tickCount = 10,
					lastTickAt = 120,
					activatedByUserId = 7201,
				},
			},
		}
	end,
	_LastAppliedPersistenceState = nil,
	ApplyPersistenceState = function(_persistedState: any): (boolean, string?)
		globalEnv._ShrineService_QueryAPI._LastAppliedPersistenceState = _persistedState
		return true, nil
	end,
}

globalEnv._RescueContractService_QueryAPI = {
	BuildPersistenceState = function(): any
		return {
			contracts = {
				{
					rescuerUserId = 9404,
					targetUserId = 9409,
					targetRealmOwnerUserId = 9402,
					entryRouteId = "RescueRoute_B",
					entryRouteKind = "RealmEntry",
					startedAt = 90,
					expiresAt = 125,
					isAccelerated = false,
				},
				{
					rescuerUserId = 9401,
					targetUserId = 9408,
					targetRealmOwnerUserId = 9402,
					entryRouteId = "RescueRoute_A",
					entryRouteKind = "RealmEntry",
					startedAt = 80,
					expiresAt = 130,
					isAccelerated = true,
				},
			},
			queueEntries = {
				{
					queueEntryId = "RQ_02",
					capturedUserId = 7402,
					realmId = "Realm_A",
					sessionId = "Session_A",
					rewardHint = "high",
					dangerRating = 0.8,
					expiration = 220,
					rescuerUserId = 9404,
					targetRealmOwnerUserId = 9402,
					entryRouteId = "RescueRoute_B",
					entryRouteKind = "RealmEntry",
					createdAt = 110,
					status = "pending",
					acceptedAt = nil,
					acceptedByUserId = nil,
					resolvedAt = nil,
					resolvedReason = nil,
				},
				{
					queueEntryId = "RQ_01",
					capturedUserId = 7401,
					realmId = "Realm_A",
					sessionId = "Session_A",
					rewardHint = "medium",
					dangerRating = 0.4,
					expiration = 210,
					rescuerUserId = 9401,
					targetRealmOwnerUserId = 9402,
					entryRouteId = "RescueRoute_A",
					entryRouteKind = "RealmEntry",
					createdAt = 100,
					status = "accepted",
					acceptedAt = 105,
					acceptedByUserId = 9401,
					resolvedAt = nil,
					resolvedReason = nil,
				},
			},
		}
	end,
	_LastAppliedPersistenceState = nil,
	ApplyPersistenceState = function(_persistedState: any): (boolean, string?)
		globalEnv._RescueContractService_QueryAPI._LastAppliedPersistenceState = _persistedState
		return true, nil
	end,
}

local eventLogRecords: { any } = {}
globalEnv._EventLogService_QueryAPI = {
	RecordEvent = function(category: any, message: any, severity: any, timestamp: any, metadata: any): any
		local record = {
			category = category,
			message = message,
			severity = severity,
			timestamp = timestamp,
			metadata = metadata,
		}
		table.insert(eventLogRecords, record)
		return {
			accepted = true,
			reason = "accepted",
			record = record,
		}
	end,
}

local clearedConditions: { any } = {}
globalEnv._TinyfolkStatusService_QueryAPI = {
	ClearConditionForUserId = function(userId: number, conditionName: string, now: number?)
		table.insert(clearedConditions, {
			userId = userId,
			conditionName = conditionName,
			now = now,
		})
		return {
			stunActive = false,
			stunUntil = nil,
		}
	end,
}

local serviceLoaded, serviceError = pcall(function()
	require("../src/ServerScriptService/Services/GiantBuildModeService.server")
end)
if not serviceLoaded then
	error(string.format("FAIL [giant build mode service loads]: %s", tostring(serviceError)))
end

assertEqual(
	GiantBuildModeConfig.StructurePlacementRemoteName,
	"GiantStructurePlacementRequest",
	"config remote name matches giant structure placement remote"
)
assertEqual(
	GiantBuildModeConfig.StructureCatalogModuleName,
	"GiantStructureCatalog",
	"config structure catalog module name matches giant structure catalog"
)
assertTrue(type(GiantStructureCatalog.GiantStructure_Runtime_A) == "table", "catalog exposes runtime structure A")

do
	local queryApi = globalEnv._GiantBuildModeService_QueryAPI
	assertTrue(type(queryApi.GetGiantMacroRouteAccess) == "function", "query api exposes giant macro route access")
	assertTrue(type(queryApi.GetRegisteredGiantMacroRouteIds) == "function", "query api exposes giant macro route ids")

	local routeIds = queryApi.GetRegisteredGiantMacroRouteIds()
	assertTrue(#routeIds >= 1, "registers authored giant macro routes from workspace")
	assertEqual(routeIds[1], "GiantRoute_PlazaToHearth", "registers plaza macro route id")

	local giant = makeAlivePlayer(8801, "Giant")
	local tinyfolk = makeAlivePlayer(8802, "Tinyfolk")
	local giantAccess = queryApi.GetGiantMacroRouteAccess(giant, "GiantRoute_PlazaToHearth")
	assertEqual(giantAccess.accepted, true, "giant macro route access accepts giant requester")
	assertEqual(giantAccess.reason, "accepted", "giant macro route access accepted reason")
	assertEqual(giantAccess.giantOnly, true, "giant macro route access projects giant-only metadata")

	local tinyfolkAccess = queryApi.GetGiantMacroRouteAccess(tinyfolk, "GiantRoute_PlazaToHearth")
	assertEqual(tinyfolkAccess.accepted, false, "giant macro route access rejects tinyfolk requester")
	assertEqual(tinyfolkAccess.reason, "requester_not_giant", "giant macro route tinyfolk rejection reason")

	giantMacroRoute:SetAttribute("RouteEnabled", false)
	local disabledAccess = queryApi.GetGiantMacroRouteAccess(giant, "GiantRoute_PlazaToHearth")
	assertEqual(disabledAccess.accepted, false, "disabled giant macro route rejects access")
	assertEqual(disabledAccess.reason, "route_disabled", "disabled giant macro route reason")
	giantMacroRoute:SetAttribute("RouteEnabled", true)
end

assertEqual(
	GiantStructureCatalog.GiantStructure_Runtime_A.displayName,
	"Runtime Test Structure A",
	"catalog runtime structure A stores display name"
)
assertEqual(
	GiantStructureCatalog.GiantStructure_Runtime_A.category,
	"utility",
	"catalog runtime structure A stores category"
)
assertEqual(GiantStructureCatalog.GiantStructure_Runtime_A.woodCost, 12, "catalog runtime structure A stores wood cost")
assertEqual(
	GiantStructureCatalog.GiantStructure_Runtime_A.stoneCost,
	8,
	"catalog runtime structure A stores stone cost"
)
assertTrue(type(GiantStructureCatalog.GiantStructure_Runtime_Snare_A) == "table", "catalog exposes runtime snare trap")
assertEqual(
	GiantStructureCatalog.GiantStructure_Runtime_Snare_A.category,
	"trap",
	"catalog runtime snare trap stores category"
)
assertTrue(giantPlacementRemote._Handler ~= nil, "service binds GiantStructurePlacementRequest OnServerEvent")
assertTrue(constructionBuildRemote._Handler == nil, "service does not bind ConstructionBuildRequest")

local registry = globalEnv._GiantBuildModeService_Registry
assertTrue(type(registry) == "table", "registry export is available")

-- Rejected malformed payload must not mutate registry or world artifacts.
local malformedPlayer = makeAlivePlayer(9401)
local resourcesBeforeMalformed = ResourceFlowState.GetSnapshot()
local warnsBeforeMalformed = #warns
giantPlacementRemote:FireServer(malformedPlayer, { structureId = "", proposedOccupiedSpace = {} })
assertTrue(registry[""] == nil, "malformed payload does not mutate registry")
assertStoredTotalsUnchanged(resourcesBeforeMalformed, "malformed payload does not debit resources")

local mapAfterMalformed = workspaceService:FindFirstChild("Map")
local giantStructuresAfterMalformed = mapAfterMalformed and mapAfterMalformed:FindFirstChild("GiantStructures")
assertTrue(giantStructuresAfterMalformed == nil, "malformed payload does not materialize giant structure artifact")

local sawMalformedReject = false
for i = warnsBeforeMalformed + 1, #warns do
	if string.find(warns[i], "malformed_payload_structure_id", 1, true) then
		sawMalformedReject = true
		break
	end
end
assertTrue(sawMalformedReject, "malformed payload rejection reason is deterministic")

-- Unknown structure ids must reject before registry or world mutation.
local unknownPlayer = makeAlivePlayer(9405)
local resourcesBeforeUnknown = ResourceFlowState.GetSnapshot()
local warnsBeforeUnknown = #warns
giantPlacementRemote:FireServer(unknownPlayer, makeAcceptedPayload("GiantStructure_Unknown"))
assertTrue(registry["GiantStructure_Unknown"] == nil, "unknown structure id does not mutate registry")
assertStoredTotalsUnchanged(resourcesBeforeUnknown, "unknown structure id does not debit resources")

local mapAfterUnknown = workspaceService:FindFirstChild("Map")
local giantStructuresAfterUnknown = mapAfterUnknown and mapAfterUnknown:FindFirstChild("GiantStructures")
assertTrue(giantStructuresAfterUnknown == nil, "unknown structure id does not materialize giant structure artifact")

local sawUnknownReject = false
for i = warnsBeforeUnknown + 1, #warns do
	if string.find(warns[i], "structure_not_in_catalog", 1, true) then
		sawUnknownReject = true
		break
	end
end
assertTrue(sawUnknownReject, "unknown structure rejection reason is deterministic")

-- Accepted payload creates server-owned registry entry and one workspace artifact.
local acceptedPlayer = makeAlivePlayer(9402)
local trappedTinyfolk = makeAlivePlayer(8401, "Tinyfolk")
local rescuerTinyfolk = makeAlivePlayer(8402, "Tinyfolk")
playersService._playerList = { acceptedPlayer, trappedTinyfolk, rescuerTinyfolk }
local acceptedStructureId = "GiantStructure_Runtime_A"
local resourcesBeforeAccept = ResourceFlowState.GetSnapshot()
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayload(acceptedStructureId))

local acceptedState = registry[acceptedStructureId]
assertTrue(acceptedState ~= nil, "accepted payload records structure placement state")
if acceptedState then
	assertEqual(acceptedState.structureId, acceptedStructureId, "accepted state stores structure id")
	assertEqual(acceptedState.placedByUserId, acceptedPlayer.UserId, "accepted state stores placer user id")
	assertEqual(
		acceptedState.placedByUserId,
		acceptedPlayer.UserId,
		"first accepted placement establishes session owner"
	)
	assertTrue(
		type(acceptedState.placedAt) == "number" and acceptedState.placedAt > 0,
		"accepted state stores placedAt"
	)
	assertEqual(#acceptedState.proposedOccupiedSpace, 1, "accepted state stores occupied space entries")
end

local mapFolderAfterAccept = workspaceService:FindFirstChild("Map")
assertTrue(mapFolderAfterAccept ~= nil, "map folder still exists after accepted placement")

local giantStructuresFolder = mapFolderAfterAccept and mapFolderAfterAccept:FindFirstChild("GiantStructures")
assertTrue(giantStructuresFolder ~= nil, "accepted placement materializes GiantStructures folder")

local artifact = giantStructuresFolder and giantStructuresFolder:FindFirstChild(acceptedStructureId)
assertTrue(artifact ~= nil, "accepted placement materializes structure artifact")
if artifact then
	assertEqual(artifact:GetAttribute("StructureId"), acceptedStructureId, "artifact exposes StructureId attribute")
	assertEqual(
		artifact:GetAttribute("PlacedByUserId"),
		acceptedPlayer.UserId,
		"artifact exposes PlacedByUserId attribute"
	)
	assertEqual(artifact:GetAttribute("OccupiedBoxCount"), 1, "artifact exposes OccupiedBoxCount attribute")
	assertTrue(type(artifact:GetAttribute("PlacedAt")) == "number", "artifact exposes PlacedAt attribute")
end

assertStoredTotals(
	resourcesBeforeAccept.Wood.stored - GiantStructureCatalog.GiantStructure_Runtime_A.woodCost,
	resourcesBeforeAccept.Stone.stored - GiantStructureCatalog.GiantStructure_Runtime_A.stoneCost,
	"accepted placement debits exact structure cost"
)

local queryApi = globalEnv._GiantBuildModeService_QueryAPI
assertTrue(type(queryApi) == "table", "query API export is available")
assertTrue(type(queryApi.GetPlacedStructure) == "function", "query API exposes GetPlacedStructure")
assertTrue(type(queryApi.GetAllPlacedStructures) == "function", "query API exposes GetAllPlacedStructures")
assertTrue(type(queryApi.GetPlacedSnareTrap) == "function", "query API exposes GetPlacedSnareTrap")
assertTrue(type(queryApi.GetAllPlacedSnareTraps) == "function", "query API exposes GetAllPlacedSnareTraps")
assertTrue(type(queryApi.ResolveSnareTrapContact) == "function", "query API exposes ResolveSnareTrapContact")
assertTrue(type(queryApi.ResolveSnareTrapDisarm) == "function", "query API exposes ResolveSnareTrapDisarm")
assertTrue(type(queryApi.ResolveSnareTrapRescue) == "function", "query API exposes ResolveSnareTrapRescue")
assertTrue(type(queryApi.RefreshSnareTrapLegality) == "function", "query API exposes RefreshSnareTrapLegality")
assertTrue(type(queryApi.IsStructurePlaced) == "function", "query API exposes IsStructurePlaced")
assertTrue(type(queryApi.BuildSaveSnapshot) == "function", "query API exposes BuildSaveSnapshot")
assertTrue(type(queryApi.ApplySaveSnapshot) == "function", "query API exposes ApplySaveSnapshot")

assertTrue(queryApi.IsStructurePlaced(acceptedStructureId), "query API reports placed structure")
assertTrue(not queryApi.IsStructurePlaced("Unknown_Giant_Structure"), "query API reports unknown structure not placed")

local fetched = queryApi.GetPlacedStructure(acceptedStructureId)
assertTrue(fetched ~= nil, "query API returns accepted structure state")
if fetched then
	assertEqual(fetched.structureId, acceptedStructureId, "query API state structureId matches")
end

-- Snare traps should place, expose query state, trigger, emit coarse alerts, and support counterplay.
local snareTrapStructureId = "GiantStructure_Runtime_Snare_A"
local resourcesBeforeSnareTrap = ResourceFlowState.GetSnapshot()
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt(snareTrapStructureId, 300, 0, 300))

local allSnareTraps = queryApi.GetAllPlacedSnareTraps()
local snareTrapSnapshot = queryApi.GetPlacedSnareTrap(snareTrapStructureId)
assertTrue(snareTrapSnapshot ~= nil, "snare trap query returns snapshot")
if snareTrapSnapshot then
	assertEqual(snareTrapSnapshot.structureId, snareTrapStructureId, "snare trap snapshot stores structure id")
	assertTrue(type(snareTrapSnapshot.trapId) == "string", "snare trap snapshot stores generated trap id")
	assertEqual(snareTrapSnapshot.status, "armed", "snare trap snapshot starts armed")
	assertTrue(snareTrapSnapshot.armed, "snare trap snapshot starts armed")
	assertTrue(allSnareTraps[snareTrapSnapshot.trapId] ~= nil, "all snare traps keyed by trap id")
	assertTrue(registry[snareTrapStructureId] == nil, "snare trap does not enter saveable structure registry")
end

local snareTrapId = snareTrapSnapshot.trapId
local snareTrapArtifact = giantStructuresFolder and giantStructuresFolder:FindFirstChild(snareTrapId)
assertTrue(snareTrapArtifact ~= nil, "snare trap placement materializes artifact")
if snareTrapArtifact then
	assertEqual(snareTrapArtifact:GetAttribute("SnareTrapId"), snareTrapId, "snare trap artifact stores trap id")
	assertEqual(snareTrapArtifact:GetAttribute("SnareTrapStatus"), "armed", "snare trap artifact starts armed")
	assertEqual(snareTrapArtifact:GetAttribute("SnareTrapArmed"), true, "snare trap artifact starts armed")
end

local giantContact = queryApi.ResolveSnareTrapContact(acceptedPlayer.UserId, { x = 300, y = 0, z = 300 }, 998)
assertTrue(not giantContact.accepted, "snare trap contact requires Tinyfolk role")
assertEqual(giantContact.reason, "snare_trap_contact_requires_tinyfolk", "wrong role contact reason")

local snareTrapContact = queryApi.ResolveSnareTrapContact(trappedTinyfolk.UserId, { x = 300, y = 0, z = 300 }, 999)
assertTrue(snareTrapContact.accepted, "snare trap contact triggers when inside radius")
assertEqual(snareTrapContact.reason, "triggered", "snare trap contact reason is deterministic")
assertTrue(snareTrapContact.trap ~= nil, "snare trap contact returns trap snapshot")
if snareTrapContact.trap then
	assertEqual(snareTrapContact.trap.status, "triggered", "snare trap trigger records status")
	assertEqual(snareTrapContact.trap.triggeredByUserId, trappedTinyfolk.UserId, "snare trap trigger records user id")
	assertTrue(not snareTrapContact.trap.armed, "snare trap becomes unarmed after trigger")
end
assertEqual(eventLogRecords[#eventLogRecords].category, "snare_trap", "trigger emits event-log category")
assertEqual(eventLogRecords[#eventLogRecords].message, "snare_trap_triggered", "trigger emits event-log message")
assertEqual(eventLogRecords[#eventLogRecords].severity, "warn", "trigger emits warn severity")
assertEqual(eventLogRecords[#eventLogRecords].metadata.trapId, snareTrapId, "trigger event metadata stores trap id")
assertTrue(eventLogRecords[#eventLogRecords].metadata.coarseGridCell ~= nil, "trigger event uses coarse location")

local snareTrapSnapshotAfterTrigger = queryApi.GetPlacedSnareTrap(snareTrapId)
assertTrue(snareTrapSnapshotAfterTrigger ~= nil, "snare trap snapshot still available after trigger")
if snareTrapSnapshotAfterTrigger then
	assertTrue(not snareTrapSnapshotAfterTrigger.armed, "snare trap snapshot is unarmed after trigger")
	assertEqual(
		snareTrapSnapshotAfterTrigger.triggeredByUserId,
		trappedTinyfolk.UserId,
		"snare trap snapshot stores triggering user"
	)
end

local earlyRescue = queryApi.ResolveSnareTrapRescue(
	rescuerTinyfolk.UserId,
	trappedTinyfolk.UserId,
	snareTrapId,
	{ x = 300, y = 0, z = 300 },
	1000,
	1001
)
assertTrue(not earlyRescue.accepted, "snare rescue rejects incomplete timed interaction")
assertEqual(earlyRescue.reason, "snare_trap_interaction_incomplete", "incomplete rescue reason")

local rescue = queryApi.ResolveSnareTrapRescue(
	rescuerTinyfolk.UserId,
	trappedTinyfolk.UserId,
	snareTrapId,
	{ x = 300, y = 0, z = 300 },
	1000,
	1002
)
assertTrue(rescue.accepted, "snare rescue accepts valid teammate interaction")
assertEqual(rescue.reason, "rescued", "snare rescue reason")
assertEqual(rescue.trap.status, "rescued", "snare rescue status")
assertEqual(
	clearedConditions[#clearedConditions].userId,
	trappedTinyfolk.UserId,
	"snare rescue clears trapped user's stun"
)
assertEqual(clearedConditions[#clearedConditions].conditionName, "stun", "snare rescue clears stun")

queryApi.ResetSnareTrapRechargeForTests(acceptedPlayer.UserId)
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_C", 340, 0, 300))
local expiringTrap = queryApi.GetPlacedSnareTrap("GiantStructure_Runtime_Snare_C")
assertTrue(expiringTrap ~= nil, "expiring trap placed")
local expiringContact = queryApi.ResolveSnareTrapContact(trappedTinyfolk.UserId, { x = 340, y = 0, z = 300 }, 1200)
assertTrue(expiringContact.accepted, "expiring trap contact triggers")
local expiringContactSnapshot = expiringContact.trap
assertTrue(expiringContactSnapshot ~= nil, "expiring trap contact returns snapshot")
local clearCountBeforeExpiry = #clearedConditions
local expiryCheckAt = (if expiringContactSnapshot ~= nil then expiringContactSnapshot.expiresAt else 1300) + 1
local expiryContact =
	queryApi.ResolveSnareTrapContact(rescuerTinyfolk.UserId, { x = 340, y = 0, z = 300 }, expiryCheckAt)
assertTrue(not expiryContact.accepted, "expired trap does not retrigger")
assertEqual(expiryContact.reason, "snare_trap_not_triggered", "expired trap contact reason")
assertEqual(#clearedConditions, clearCountBeforeExpiry + 1, "expired triggered trap clears stun once")
assertEqual(clearedConditions[#clearedConditions].userId, trappedTinyfolk.UserId, "expiry clear targets trapped user")
assertEqual(clearedConditions[#clearedConditions].conditionName, "stun", "expiry clear condition is stun")

queryApi.ResetSnareTrapRechargeForTests(acceptedPlayer.UserId)
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_D", 380, 0, 300))
local invalidatingTrap = queryApi.GetPlacedSnareTrap("GiantStructure_Runtime_Snare_D")
assertTrue(invalidatingTrap ~= nil, "invalidating trap placed")
local invalidatingContact = queryApi.ResolveSnareTrapContact(trappedTinyfolk.UserId, { x = 380, y = 0, z = 300 }, 1310)
assertTrue(invalidatingContact.accepted, "invalidating trap contact triggers")
local clearCountBeforeInvalidation = #clearedConditions
local protectedSpawnNearTriggered = makeNode("Spawn_B", "BasePart", "Workspace.Map.Spawns.Spawn_B")
protectedSpawnNearTriggered.Position = { x = 380, y = 0, z = 300 }
if mapFolder:FindFirstChild("Spawns") == nil then
	local spawnsFolderForTriggered = makeNode("Spawns", "Folder", "Workspace.Map.Spawns")
	addChild(mapFolder, "Spawns", spawnsFolderForTriggered)
end
addChild(mapFolder:FindFirstChild("Spawns"), "Spawn_B", protectedSpawnNearTriggered)
local invalidatedTriggered = queryApi.RefreshSnareTrapLegality(1311)
assertTrue(#invalidatedTriggered >= 1, "refresh returns invalidated triggered trap")
assertEqual(#clearedConditions, clearCountBeforeInvalidation + 1, "invalidated triggered trap clears stun once")
assertEqual(
	clearedConditions[#clearedConditions].userId,
	trappedTinyfolk.UserId,
	"invalidation clear targets trapped user"
)
assertEqual(clearedConditions[#clearedConditions].conditionName, "stun", "invalidation clear condition is stun")

queryApi.ResetSnareTrapRechargeForTests(acceptedPlayer.UserId)
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_B", 360, 0, 300))
local disarmTrap = queryApi.GetPlacedSnareTrap("GiantStructure_Runtime_Snare_B")
assertTrue(disarmTrap ~= nil, "second trap placed for disarm")
local wrongRoleDisarm =
	queryApi.ResolveSnareTrapDisarm(acceptedPlayer.UserId, disarmTrap.trapId, { x = 360, y = 0, z = 300 }, 1100, 1102)
assertTrue(not wrongRoleDisarm.accepted, "disarm requires Tinyfolk role")
assertEqual(wrongRoleDisarm.reason, "snare_trap_disarm_requires_tinyfolk", "wrong role disarm reason")
local disarm =
	queryApi.ResolveSnareTrapDisarm(rescuerTinyfolk.UserId, disarmTrap.trapId, { x = 360, y = 0, z = 300 }, 1100, 1102)
assertTrue(disarm.accepted, "disarm accepts valid Tinyfolk interaction")
assertEqual(disarm.reason, "disarmed", "disarm reason")
assertEqual(disarm.trap.status, "disarmed", "disarm status")

assertStoredTotals(
	resourcesBeforeSnareTrap.Wood.stored
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_A.woodCost
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_B.woodCost
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_C.woodCost
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_D.woodCost,
	resourcesBeforeSnareTrap.Stone.stored
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_A.stoneCost
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_B.stoneCost
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_C.stoneCost
		- GiantStructureCatalog.GiantStructure_Runtime_Snare_D.stoneCost,
	"snare trap placements debit exact structure cost"
)

local warnsBeforeSnareReject = #warns
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_B", 22, 0, 22))
local sawSnareTrapNearObjective = false
for i = warnsBeforeSnareReject + 1, #warns do
	if string.find(warns[i], "snare_trap_near_objective", 1, true) then
		sawSnareTrapNearObjective = true
		break
	end
end
assertTrue(sawSnareTrapNearObjective, "snare trap objective proximity rejection is deterministic")

local warnsBeforeExitReject = #warns
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_B", 100, 0, 100))
local sawSnareTrapNearExit = false
for i = warnsBeforeExitReject + 1, #warns do
	if string.find(warns[i], "snare_trap_near_exit", 1, true) then
		sawSnareTrapNearExit = true
		break
	end
end
assertTrue(sawSnareTrapNearExit, "snare trap exit proximity rejection is deterministic")

ResourceFlowState.ResetSession("snare_trap_cap_and_recharge")
queryApi.ResetSnareTrapRechargeForTests(acceptedPlayer.UserId)
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_A", 600, 0, 300))
local rechargeBaseline = ResourceFlowState.GetSnapshot()
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_B", 660, 0, 300))
assertStoredTotalsUnchanged(rechargeBaseline, "snare recharge reject does not debit resources")
queryApi.ResetSnareTrapRechargeForTests(acceptedPlayer.UserId)

clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_B", 660, 0, 300))
queryApi.ResetSnareTrapRechargeForTests(acceptedPlayer.UserId)
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_C", 720, 0, 300))
local beforeReplacement = queryApi.GetAllPlacedSnareTraps()
local activeBeforeReplacement = 0
for _, trap in pairs(beforeReplacement) do
	if trap.status == "armed" then
		activeBeforeReplacement += 1
	end
end
assertEqual(activeBeforeReplacement, 3, "snare cap allows three armed traps")

clearRequestCooldownFor(acceptedPlayer)
queryApi.ResetSnareTrapRechargeForTests(acceptedPlayer.UserId)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt("GiantStructure_Runtime_Snare_D", 780, 0, 300))
local afterReplacement = queryApi.GetAllPlacedSnareTraps()
local activeAfterReplacement = 0
for _, trap in pairs(afterReplacement) do
	if trap.status == "armed" then
		activeAfterReplacement += 1
	end
end
assertEqual(activeAfterReplacement, 3, "snare cap replacement preserves active max")

local protectedSpawn = makeNode("Spawn_A", "BasePart", "Workspace.Map.Spawns.Spawn_A")
protectedSpawn.Position = { x = 780, y = 0, z = 300 }
local spawnsFolder = makeNode("Spawns", "Folder", "Workspace.Map.Spawns")
addChild(spawnsFolder, "Spawn_A", protectedSpawn)
addChild(mapFolder, "Spawns", spawnsFolder)
local invalidatedTraps = queryApi.RefreshSnareTrapLegality(1300)
assertTrue(#invalidatedTraps >= 1, "refresh invalidates trap that becomes illegal near spawn")
assertEqual(invalidatedTraps[1].status, "invalidated", "refresh stores invalidated status")

-- Non-overlapping occupied space should accept a second known structure.
local nonOverlappingStructureId = "GiantStructure_Runtime_F"
local resourcesBeforeNonOverlap = ResourceFlowState.GetSnapshot()
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt(nonOverlappingStructureId, 200, 0, 300))

local nonOverlappingState = registry[nonOverlappingStructureId]
assertTrue(nonOverlappingState ~= nil, "same owner can place non-overlapping second structure")
if nonOverlappingState then
	assertEqual(nonOverlappingState.structureId, nonOverlappingStructureId, "non-overlap state stores structure id")
	assertEqual(nonOverlappingState.placedByUserId, acceptedPlayer.UserId, "non-overlap state stores owner user id")
end

local nonOverlappingArtifact = giantStructuresFolder and giantStructuresFolder:FindFirstChild(nonOverlappingStructureId)
assertTrue(nonOverlappingArtifact ~= nil, "non-overlapping accept materializes structure artifact")
assertStoredTotals(
	resourcesBeforeNonOverlap.Wood.stored - GiantStructureCatalog.GiantStructure_Runtime_F.woodCost,
	resourcesBeforeNonOverlap.Stone.stored - GiantStructureCatalog.GiantStructure_Runtime_F.stoneCost,
	"non-overlapping accept debits exact structure cost"
)

for index = 1, 52 do
	local recordedDefense = queryApi.RecordEscapeDefenseOutcome({
		operationId = string.format("escape-defense-op-%02d", index),
		escapedUserId = 8000 + index,
		escapedAt = index,
		sourceKind = "route_escape",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
		difficulty = 1,
		lootValue = index,
		rewardPoints = 100 + index,
	})
	assertTrue(recordedDefense.accepted, "defense history record accepted")
end

local duplicateDefense = queryApi.RecordEscapeDefenseOutcome({
	operationId = "escape-defense-op-52",
	escapedUserId = 8052,
	escapedAt = 52,
	sourceKind = "route_escape",
	sourceId = "EscapeRoute_A",
	routeId = "EscapeRoute_A",
	difficulty = 1,
	lootValue = 52,
	rewardPoints = 152,
})
assertTrue(duplicateDefense.accepted, "duplicate defense history record no-ops")
assertEqual(duplicateDefense.duplicate, true, "duplicate defense history flag")

local saveRoot, saveRootReason = queryApi.BuildSaveSnapshot(acceptedPlayer.UserId)
assertTrue(saveRoot ~= nil, "save snapshot returns root for valid owner")
assertEqual(saveRootReason, nil, "save snapshot valid owner has no failure reason")
if saveRoot then
	assertEqual(
		saveRoot.schemaVersion,
		GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
		"save snapshot schema version matches initial schema version"
	)
	assertEqual(saveRoot.ownerUserId, acceptedPlayer.UserId, "save snapshot preserves owner user id")

	local saveRootValid, saveRootValidationReason = GiantRealmSaveSchema.ValidateSaveRoot(saveRoot)
	assertTrue(saveRootValid, "save snapshot validates against GiantRealmSaveSchema")
	assertEqual(saveRootValidationReason, nil, "save snapshot validation has no reason")
	assertEqual(#saveRoot.placedStructures, 2, "save snapshot includes accepted structure count")
	assertTrue(type(saveRoot.emergencyReinforcement) == "table", "save snapshot includes reinforcement state")
	assertTrue(type(saveRoot.shrinePersistence) == "table", "save snapshot includes shrine persistence")
	assertTrue(type(saveRoot.rescuePersistence) == "table", "save snapshot includes rescue persistence")
	assertTrue(type(saveRoot.defenseHistory) == "table", "save snapshot includes defense history")
	assertEqual(#saveRoot.defenseHistory.escapeOutcomes, 50, "save snapshot bounds defense history")
	assertEqual(
		saveRoot.defenseHistory.escapeOutcomes[1].operationId,
		"escape-defense-op-03",
		"save snapshot prunes oldest defense history"
	)
	assertEqual(
		saveRoot.defenseHistory.escapeOutcomes[50].operationId,
		"escape-defense-op-52",
		"save snapshot keeps latest defense history"
	)
	assertEqual(saveRoot.shrinePersistence.shrines[1].shrineId, "Shrine_A", "save snapshot shrine order first")
	assertEqual(saveRoot.shrinePersistence.shrines[2].shrineId, "Shrine_B", "save snapshot shrine order second")
	assertEqual(
		saveRoot.rescuePersistence.contracts[1].rescuerUserId,
		9401,
		"save snapshot rescue contract order first"
	)
	assertEqual(
		saveRoot.rescuePersistence.contracts[2].rescuerUserId,
		9404,
		"save snapshot rescue contract order second"
	)
	assertEqual(
		saveRoot.rescuePersistence.queueEntries[1].queueEntryId,
		"RQ_01",
		"save snapshot rescue queue order first"
	)
	assertEqual(
		saveRoot.rescuePersistence.queueEntries[2].queueEntryId,
		"RQ_02",
		"save snapshot rescue queue order second"
	)
	assertEqual(saveRoot.emergencyReinforcement.used, true, "save snapshot reinforcement used")
	assertEqual(saveRoot.emergencyReinforcement.triggeredByUserId, 1101, "save snapshot reinforcement requester")
	assertEqual(
		saveRoot.placedStructures[1].structureId,
		acceptedStructureId,
		"save snapshot structures are ordered deterministically first"
	)
	assertEqual(
		saveRoot.placedStructures[2].structureId,
		nonOverlappingStructureId,
		"save snapshot structures are ordered deterministically second"
	)
end

-- Different players should reject before affordability debit or placement mutation.
local ownerMismatchStructureId = "GiantStructure_Runtime_G"
local ownerMismatchPlayer = makeAlivePlayer(9411)
local resourcesBeforeOwnerMismatch = ResourceFlowState.GetSnapshot()
local warnsBeforeOwnerMismatch = #warns
giantPlacementRemote:FireServer(ownerMismatchPlayer, makeAcceptedPayloadAt(ownerMismatchStructureId, 280, 0, 300))
assertTrue(registry[ownerMismatchStructureId] == nil, "owner mismatch rejection does not mutate registry")

local ownerMismatchArtifact = giantStructuresFolder and giantStructuresFolder:FindFirstChild(ownerMismatchStructureId)
assertTrue(ownerMismatchArtifact == nil, "owner mismatch rejection does not materialize structure artifact")
assertStoredTotalsUnchanged(resourcesBeforeOwnerMismatch, "owner mismatch rejection does not debit resources")

local sawOwnerMismatchReject = false
for i = warnsBeforeOwnerMismatch + 1, #warns do
	if string.find(warns[i], "giant_realm_owner_mismatch", 1, true) then
		sawOwnerMismatchReject = true
		break
	end
end
assertTrue(sawOwnerMismatchReject, "owner mismatch rejection reason is deterministic")

-- Overlapping occupied space should reject before affordability debit or placement mutation.
local overlappingStructureId = "GiantStructure_Runtime_G"
local resourcesBeforeOverlap = ResourceFlowState.GetSnapshot()
local warnsBeforeOverlap = #warns
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt(overlappingStructureId, 130, 0, 300))
assertTrue(registry[overlappingStructureId] == nil, "overlap rejection does not mutate registry")

local overlappingArtifact = giantStructuresFolder and giantStructuresFolder:FindFirstChild(overlappingStructureId)
assertTrue(overlappingArtifact == nil, "overlap rejection does not materialize structure artifact")
assertStoredTotalsUnchanged(resourcesBeforeOverlap, "overlap rejection does not debit resources")

local sawOverlapReject = false
for i = warnsBeforeOverlap + 1, #warns do
	if string.find(warns[i], "structure_occupied_space_overlap", 1, true) then
		sawOverlapReject = true
		break
	end
end
assertTrue(sawOverlapReject, "overlap rejection reason is deterministic")

local originalStateAfterOverlap = registry[acceptedStructureId]
assertTrue(originalStateAfterOverlap ~= nil, "overlap rejection preserves original accepted state")
if originalStateAfterOverlap then
	assertEqual(
		originalStateAfterOverlap.placedByUserId,
		acceptedPlayer.UserId,
		"overlap rejection does not disturb original accepted state"
	)
end

local originalArtifactAfterOverlap = giantStructuresFolder and giantStructuresFolder:FindFirstChild(acceptedStructureId)
assertTrue(originalArtifactAfterOverlap ~= nil, "overlap rejection preserves original accepted artifact")

-- Duplicate structure id should reject and preserve prior accepted state.
local duplicatePlayer = makeAlivePlayer(9403)
local resourcesBeforeDuplicate = ResourceFlowState.GetSnapshot()
local warnsBeforeDuplicate = #warns
giantPlacementRemote:FireServer(duplicatePlayer, makeAcceptedPayload(acceptedStructureId))

local sawAlreadyPlaced = false
for i = warnsBeforeDuplicate + 1, #warns do
	if string.find(warns[i], "structure_already_placed", 1, true) then
		sawAlreadyPlaced = true
		break
	end
end
assertTrue(sawAlreadyPlaced, "duplicate placement rejection reason is deterministic")

local stateAfterDuplicate = registry[acceptedStructureId]
assertTrue(stateAfterDuplicate ~= nil, "duplicate rejection preserves existing accepted state")
if stateAfterDuplicate then
	assertEqual(
		stateAfterDuplicate.placedByUserId,
		acceptedPlayer.UserId,
		"duplicate rejection keeps original placer in accepted state"
	)
end
assertStoredTotalsUnchanged(resourcesBeforeDuplicate, "duplicate placement does not debit resources")

-- Insufficient stored resources should reject without mutating registry or spending partially.
ResourceFlowState.ResetSession("giant_build_mode_insufficient_resources")
local drainForInsufficientOk = ResourceFlowState.SpendStoredAtomic(110, 0, "TestDrainBeforeGiantBuildInsufficient")
assertTrue(drainForInsufficientOk, "test drain before insufficient resource case succeeds")
assertStoredTotals(10, 120, "test drain leaves insufficient wood for runtime B")

local insufficientStructureId = "GiantStructure_Runtime_B"
local resourcesBeforeInsufficient = ResourceFlowState.GetSnapshot()
local warnsBeforeInsufficient = #warns
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt(insufficientStructureId, 1280, 0, 300))
assertTrue(registry[insufficientStructureId] == nil, "insufficient resources do not mutate registry")
assertStoredTotalsUnchanged(resourcesBeforeInsufficient, "insufficient resources do not debit resources")

local sawInsufficientResources = false
for i = warnsBeforeInsufficient + 1, #warns do
	if string.find(warns[i], "insufficient_resources", 1, true) then
		sawInsufficientResources = true
		break
	end
end
assertTrue(sawInsufficientResources, "insufficient resources rejection reason is deterministic")

local saveRootAfterRejects, saveRootAfterRejectsReason = queryApi.BuildSaveSnapshot(acceptedPlayer.UserId)
assertTrue(saveRootAfterRejects ~= nil, "save snapshot still returns root after rejected placements")
assertEqual(saveRootAfterRejectsReason, nil, "save snapshot after rejected placements has no failure reason")
if saveRootAfterRejects then
	local sawAcceptedStructure = false
	local sawNonOverlappingStructure = false
	local sawOwnerMismatchStructure = false
	local sawOverlappingStructure = false
	local sawInsufficientStructure = false
	for _, record in ipairs(saveRootAfterRejects.placedStructures) do
		if record.structureId == acceptedStructureId then
			sawAcceptedStructure = true
		end
		if record.structureId == nonOverlappingStructureId then
			sawNonOverlappingStructure = true
		end
		if record.structureId == ownerMismatchStructureId then
			sawOwnerMismatchStructure = true
		end
		if record.structureId == overlappingStructureId then
			sawOverlappingStructure = true
		end
		if record.structureId == insufficientStructureId then
			sawInsufficientStructure = true
		end
	end

	assertTrue(sawAcceptedStructure, "save snapshot keeps first accepted structure")
	assertTrue(sawNonOverlappingStructure, "save snapshot keeps non-overlapping accepted structure")
	assertTrue(not sawOwnerMismatchStructure, "save snapshot excludes owner mismatch rejected structure")
	assertTrue(not sawOverlappingStructure, "save snapshot excludes overlap rejected structure")
	assertTrue(not sawInsufficientStructure, "save snapshot excludes insufficient resource rejected structure")
end

local nilOwnerRoot, nilOwnerReason = queryApi.BuildSaveSnapshot(nil)
assertEqual(nilOwnerRoot, nil, "save snapshot nil owner returns nil root")
assertEqual(nilOwnerReason, "save_snapshot_owner_user_id_invalid", "save snapshot nil owner reason")

local zeroOwnerRoot, zeroOwnerReason = queryApi.BuildSaveSnapshot(0)
assertEqual(zeroOwnerRoot, nil, "save snapshot zero owner returns nil root")
assertEqual(zeroOwnerReason, "save_snapshot_owner_user_id_invalid", "save snapshot zero owner reason")

local stringOwnerRoot, stringOwnerReason = queryApi.BuildSaveSnapshot("9402")
assertEqual(stringOwnerRoot, nil, "save snapshot string owner returns nil root")
assertEqual(stringOwnerReason, "save_snapshot_owner_user_id_invalid", "save snapshot string owner reason")

local registryBeforeApply = globalEnv._GiantBuildModeService_Registry
assertTrue(registryBeforeApply == registry, "apply setup registry reference starts stable")

local appliedStructureA = "GiantStructure_Applied_A"
local appliedStructureB = "GiantStructure_Applied_B"
local applyRoot = {
	schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
	ownerUserId = acceptedPlayer.UserId,
	placedStructures = {
		{
			structureId = appliedStructureB,
			placedByUserId = acceptedPlayer.UserId,
			placedAt = 808.25,
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 700, y = 0, z = 300 },
					halfExtents = { x = 12, y = 6, z = 12 },
				},
			},
		},
		{
			structureId = appliedStructureA,
			placedByUserId = acceptedPlayer.UserId,
			placedAt = 707.5,
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 640, y = 0, z = 300 },
					halfExtents = { x = 10, y = 5, z = 10 },
				},
			},
		},
	},
	defenseHistory = {
		escapeOutcomes = {
			{
				operationId = "applied-defense-op-1",
				escapedUserId = 9101,
				escapedAt = 70,
				sourceKind = "transport",
				sourceId = "Transport_A",
				routeId = "EscapeRoute_A",
				difficulty = 3,
				lootValue = 4,
				rewardPoints = 190,
			},
		},
	},
}

local applyRootValid, applyRootReason = GiantRealmSaveSchema.ValidateSaveRoot(applyRoot)
assertTrue(applyRootValid, "apply test root validates before apply")
assertEqual(applyRootReason, nil, "apply test root has no validation reason")

local applyOk, applyReason = queryApi.ApplySaveSnapshot(applyRoot)
assertTrue(applyOk, "valid save snapshot applies successfully")
assertEqual(applyReason, nil, "valid save snapshot apply has no failure reason")
assertTrue(
	type(globalEnv._EmergencyReinforcementService_QueryAPI._LastAppliedPersistenceState) == "nil",
	"apply without reinforcement record clears persistence state"
)
assertTrue(
	type(globalEnv._ShrineService_QueryAPI._LastAppliedPersistenceState) == "nil",
	"apply without shrine record clears persistence state"
)
assertTrue(
	type(globalEnv._RescueContractService_QueryAPI._LastAppliedPersistenceState) == "nil",
	"apply without rescue record clears persistence state"
)
assertTrue(globalEnv._GiantBuildModeService_Registry == registryBeforeApply, "apply preserves registry table reference")
assertTrue(queryApi.GetPlacedStructure(acceptedStructureId) == nil, "apply removes stale accepted structure state")
assertTrue(
	queryApi.GetPlacedStructure(nonOverlappingStructureId) == nil,
	"apply removes stale non-overlap structure state"
)
assertTrue(not queryApi.IsStructurePlaced(acceptedStructureId), "apply removes stale accepted query visibility")
assertTrue(
	not queryApi.IsStructurePlaced(nonOverlappingStructureId),
	"apply removes stale non-overlap query visibility"
)
assertTrue(queryApi.IsStructurePlaced(appliedStructureA), "apply exposes applied structure A via query")
assertTrue(queryApi.IsStructurePlaced(appliedStructureB), "apply exposes applied structure B via query")

local appliedStateA = queryApi.GetPlacedStructure(appliedStructureA)
local appliedStateB = queryApi.GetPlacedStructure(appliedStructureB)
assertTrue(appliedStateA ~= nil, "apply returns applied structure A state")
assertTrue(appliedStateB ~= nil, "apply returns applied structure B state")
if appliedStateA then
	assertEqual(appliedStateA.placedByUserId, acceptedPlayer.UserId, "apply structure A owner")
	assertEqual(appliedStateA.placedAt, 707.5, "apply structure A placedAt")
	assertEqual(#appliedStateA.proposedOccupiedSpace, 1, "apply structure A occupied count")
end
if appliedStateB then
	assertEqual(appliedStateB.placedByUserId, acceptedPlayer.UserId, "apply structure B owner")
	assertEqual(appliedStateB.placedAt, 808.25, "apply structure B placedAt")
	assertEqual(#appliedStateB.proposedOccupiedSpace, 1, "apply structure B occupied count")
end

local allAppliedStructures = queryApi.GetAllPlacedStructures()
local allAppliedCount = 0
for _ in pairs(allAppliedStructures) do
	allAppliedCount += 1
end
assertEqual(allAppliedCount, 2, "apply replaces live registry with exact applied count")

local giantStructuresAfterApply = mapFolderAfterAccept and mapFolderAfterAccept:FindFirstChild("GiantStructures")
assertTrue(giantStructuresAfterApply ~= nil, "apply keeps GiantStructures artifact folder")
local staleAcceptedArtifact = giantStructuresAfterApply
	and giantStructuresAfterApply:FindFirstChild(acceptedStructureId)
local staleNonOverlapArtifact = giantStructuresAfterApply
	and giantStructuresAfterApply:FindFirstChild(nonOverlappingStructureId)
assertTrue(staleAcceptedArtifact == nil, "apply removes stale accepted artifact")
assertTrue(staleNonOverlapArtifact == nil, "apply removes stale non-overlap artifact")

local appliedArtifactA = giantStructuresAfterApply and giantStructuresAfterApply:FindFirstChild(appliedStructureA)
local appliedArtifactB = giantStructuresAfterApply and giantStructuresAfterApply:FindFirstChild(appliedStructureB)
assertTrue(appliedArtifactA ~= nil, "apply materializes artifact A")
assertTrue(appliedArtifactB ~= nil, "apply materializes artifact B")
if appliedArtifactA then
	assertEqual(appliedArtifactA:GetAttribute("StructureId"), appliedStructureA, "apply artifact A structure id")
	assertEqual(appliedArtifactA:GetAttribute("PlacedByUserId"), acceptedPlayer.UserId, "apply artifact A owner")
	assertEqual(appliedArtifactA:GetAttribute("PlacedAt"), 707.5, "apply artifact A placedAt")
	assertEqual(appliedArtifactA:GetAttribute("OccupiedBoxCount"), 1, "apply artifact A occupied count")
end
if appliedArtifactB then
	assertEqual(appliedArtifactB:GetAttribute("StructureId"), appliedStructureB, "apply artifact B structure id")
	assertEqual(appliedArtifactB:GetAttribute("PlacedByUserId"), acceptedPlayer.UserId, "apply artifact B owner")
	assertEqual(appliedArtifactB:GetAttribute("PlacedAt"), 808.25, "apply artifact B placedAt")
	assertEqual(appliedArtifactB:GetAttribute("OccupiedBoxCount"), 1, "apply artifact B occupied count")
end

local snapshotAfterApply, snapshotAfterApplyReason = queryApi.BuildSaveSnapshot(applyRoot.ownerUserId)
assertTrue(snapshotAfterApply ~= nil, "post-apply save snapshot returns root")
assertEqual(snapshotAfterApplyReason, nil, "post-apply save snapshot has no reason")
if snapshotAfterApply then
	local snapshotAfterApplyValid, snapshotAfterApplyValidationReason =
		GiantRealmSaveSchema.ValidateSaveRoot(snapshotAfterApply)
	assertTrue(snapshotAfterApplyValid, "post-apply save snapshot validates")
	assertEqual(snapshotAfterApplyValidationReason, nil, "post-apply save snapshot validation reason")
	assertEqual(#snapshotAfterApply.placedStructures, 2, "post-apply save snapshot count")
	assertEqual(
		snapshotAfterApply.placedStructures[1].structureId,
		appliedStructureA,
		"post-apply save snapshot deterministic first"
	)
	assertEqual(
		snapshotAfterApply.placedStructures[2].structureId,
		appliedStructureB,
		"post-apply save snapshot deterministic second"
	)
	assertEqual(
		snapshotAfterApply.defenseHistory.escapeOutcomes[1].operationId,
		"applied-defense-op-1",
		"post-apply save snapshot preserves defense history"
	)
end

local applyWithReinforcementRoot = {
	schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
	ownerUserId = applyRoot.ownerUserId,
	placedStructures = applyRoot.placedStructures,
	emergencyReinforcement = {
		used = true,
		callStartedAt = 60,
		cooldownEndsAt = 105,
		triggeredByUserId = 2201,
		spawnedUserId = 2203,
		lastReason = "accepted",
		lastObjectiveId = "CallCenter_A",
	},
}
local applyWithReinforcementOk, applyWithReinforcementReason = queryApi.ApplySaveSnapshot(applyWithReinforcementRoot)
assertTrue(applyWithReinforcementOk, "apply with reinforcement state succeeds")
assertEqual(applyWithReinforcementReason, nil, "apply with reinforcement state has no reason")
assertEqual(
	globalEnv._EmergencyReinforcementService_QueryAPI._LastAppliedPersistenceState.triggeredByUserId,
	2201,
	"apply forwards reinforcement persistence state"
)

local originalEmergencyApplyPersistence = globalEnv._EmergencyReinforcementService_QueryAPI.ApplyPersistenceState
globalEnv._EmergencyReinforcementService_QueryAPI.ApplyPersistenceState = function(
	_persistedState: any
): (boolean, string?)
	return false, "emergency_apply_failed_for_test"
end

local failedEmergencyApplyOk, failedEmergencyApplyReason = queryApi.ApplySaveSnapshot(applyWithReinforcementRoot)
assertTrue(not failedEmergencyApplyOk, "failed emergency apply rejects snapshot apply")
assertEqual(failedEmergencyApplyReason, "emergency_apply_failed_for_test", "failed emergency apply reason")
assertTrue(queryApi.IsStructurePlaced(appliedStructureA), "failed emergency apply preserves applied structure A")
assertTrue(queryApi.IsStructurePlaced(appliedStructureB), "failed emergency apply preserves applied structure B")

globalEnv._EmergencyReinforcementService_QueryAPI.ApplyPersistenceState = originalEmergencyApplyPersistence

local applyWithShrineRoot = {
	schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
	ownerUserId = applyRoot.ownerUserId,
	placedStructures = applyRoot.placedStructures,
	shrinePersistence = {
		shrines = {
			{
				shrineId = "Shrine_A",
				isActive = true,
				essenceTotal = 20,
				tickCount = 8,
				lastTickAt = 200,
				activatedByUserId = 7202,
			},
		},
	},
}
local applyWithShrineOk, applyWithShrineReason = queryApi.ApplySaveSnapshot(applyWithShrineRoot)
assertTrue(applyWithShrineOk, "apply with shrine state succeeds")
assertEqual(applyWithShrineReason, nil, "apply with shrine state has no reason")
assertEqual(
	globalEnv._ShrineService_QueryAPI._LastAppliedPersistenceState.shrines[1].shrineId,
	"Shrine_A",
	"apply forwards shrine persistence state"
)

local applyWithRescueRoot = {
	schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
	ownerUserId = applyRoot.ownerUserId,
	placedStructures = applyRoot.placedStructures,
	rescuePersistence = {
		contracts = {
			{
				rescuerUserId = 9501,
				targetUserId = 9502,
				targetRealmOwnerUserId = applyRoot.ownerUserId,
				entryRouteId = "RescueRoute_A",
				entryRouteKind = "RealmEntry",
				startedAt = 500,
				expiresAt = 560,
				isAccelerated = true,
			},
		},
		queueEntries = {
			{
				queueEntryId = "RQ_03",
				capturedUserId = 9502,
				realmId = "Realm_A",
				sessionId = "Session_A",
				rewardHint = "high",
				dangerRating = 0.9,
				expiration = 580,
				rescuerUserId = 9501,
				targetRealmOwnerUserId = applyRoot.ownerUserId,
				entryRouteId = "RescueRoute_A",
				entryRouteKind = "RealmEntry",
				createdAt = 500,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	},
}
local applyWithRescueOk, applyWithRescueReason = queryApi.ApplySaveSnapshot(applyWithRescueRoot)
assertTrue(applyWithRescueOk, "apply with rescue state succeeds")
assertEqual(applyWithRescueReason, nil, "apply with rescue state has no reason")
assertEqual(
	globalEnv._RescueContractService_QueryAPI._LastAppliedPersistenceState.contracts[1].rescuerUserId,
	9501,
	"apply forwards rescue persistence state"
)

local originalShrineApplyPersistence = globalEnv._ShrineService_QueryAPI.ApplyPersistenceState
globalEnv._ShrineService_QueryAPI.ApplyPersistenceState = function(_persistedState: any): (boolean, string?)
	return false, "shrine_apply_failed_for_test"
end

local failedShrineApplyOk, failedShrineApplyReason = queryApi.ApplySaveSnapshot(applyWithShrineRoot)
assertTrue(not failedShrineApplyOk, "failed shrine apply rejects snapshot apply")
assertEqual(failedShrineApplyReason, "shrine_apply_failed_for_test", "failed shrine apply reason")
assertTrue(queryApi.IsStructurePlaced(appliedStructureA), "failed shrine apply preserves applied structure A")
assertTrue(queryApi.IsStructurePlaced(appliedStructureB), "failed shrine apply preserves applied structure B")

globalEnv._ShrineService_QueryAPI.ApplyPersistenceState = originalShrineApplyPersistence

local originalRescueApplyPersistence = globalEnv._RescueContractService_QueryAPI.ApplyPersistenceState
globalEnv._RescueContractService_QueryAPI.ApplyPersistenceState = function(_persistedState: any): (boolean, string?)
	return false, "rescue_apply_failed_for_test"
end

local failedRescueApplyOk, failedRescueApplyReason = queryApi.ApplySaveSnapshot(applyWithRescueRoot)
assertTrue(not failedRescueApplyOk, "failed rescue apply rejects snapshot apply")
assertEqual(failedRescueApplyReason, "rescue_apply_failed_for_test", "failed rescue apply reason")
assertTrue(queryApi.IsStructurePlaced(appliedStructureA), "failed rescue apply preserves applied structure A")
assertTrue(queryApi.IsStructurePlaced(appliedStructureB), "failed rescue apply preserves applied structure B")

globalEnv._RescueContractService_QueryAPI.ApplyPersistenceState = originalRescueApplyPersistence

local invalidApplyRoot = {
	schemaVersion = 999,
	ownerUserId = applyRoot.ownerUserId,
	placedStructures = applyRoot.placedStructures,
}
local invalidApplyOk, invalidApplyReason = queryApi.ApplySaveSnapshot(invalidApplyRoot)
assertTrue(not invalidApplyOk, "invalid save snapshot apply rejects")
assertEqual(invalidApplyReason, "save_root_schema_version_invalid", "invalid save snapshot apply reason")
assertTrue(
	globalEnv._GiantBuildModeService_Registry == registryBeforeApply,
	"invalid apply preserves registry reference"
)
assertTrue(queryApi.IsStructurePlaced(appliedStructureA), "invalid apply preserves applied structure A")
assertTrue(queryApi.IsStructurePlaced(appliedStructureB), "invalid apply preserves applied structure B")
assertTrue(
	not queryApi.IsStructurePlaced(acceptedStructureId),
	"invalid apply does not restore stale accepted structure"
)
local appliedArtifactAAfterInvalid = giantStructuresAfterApply
	and giantStructuresAfterApply:FindFirstChild(appliedStructureA)
local staleArtifactAfterInvalid = giantStructuresAfterApply
	and giantStructuresAfterApply:FindFirstChild(acceptedStructureId)
assertTrue(appliedArtifactAAfterInvalid ~= nil, "invalid apply preserves applied artifact")
assertTrue(staleArtifactAfterInvalid == nil, "invalid apply keeps stale artifact absent")

local cleanupApplyRoot = {
	schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
	ownerUserId = applyRoot.ownerUserId,
	placedStructures = {},
}
local cleanupApplyOk, cleanupApplyReason = queryApi.ApplySaveSnapshot(cleanupApplyRoot)
assertTrue(cleanupApplyOk, "cleanup apply clears placement state before resource exhaustion block")
assertEqual(cleanupApplyReason, nil, "cleanup apply has no failure reason")

-- Repeated accepted placements should deplete stored totals until a later known placement rejects.
ResourceFlowState.ResetSession("giant_build_mode_repeated_depletion")
local repeatedFirstStructureId = "GiantStructure_Runtime_C"
local repeatedSecondStructureId = "GiantStructure_Runtime_D"
local repeatedRejectedStructureId = "GiantStructure_Runtime_E"

clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt(repeatedFirstStructureId, 360, 0, 300))
assertTrue(registry[repeatedFirstStructureId] ~= nil, "first repeated placement accepted")
assertStoredTotals(70, 70, "first repeated placement debits stored totals")

clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt(repeatedSecondStructureId, 440, 0, 300))
assertTrue(registry[repeatedSecondStructureId] ~= nil, "second repeated placement accepted")
assertStoredTotals(10, 10, "second repeated placement debits stored totals")

local resourcesBeforeDepletedReject = ResourceFlowState.GetSnapshot()
local warnsBeforeDepletedReject = #warns
clearRequestCooldownFor(acceptedPlayer)
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayloadAt(repeatedRejectedStructureId, 520, 0, 300))
assertTrue(registry[repeatedRejectedStructureId] == nil, "depleted resources do not mutate registry")
assertStoredTotalsUnchanged(resourcesBeforeDepletedReject, "depleted resources reject does not debit resources")

local sawDepletedInsufficientResources = false
for i = warnsBeforeDepletedReject + 1, #warns do
	if string.find(warns[i], "insufficient_resources", 1, true) then
		sawDepletedInsufficientResources = true
		break
	end
end
assertTrue(sawDepletedInsufficientResources, "depleted repeated placement rejection reason is deterministic")

-- TIN-56: Deterministic rejection-path coverage (smallest next slice)
do
	-- request_cooldown
	local cooldownPlayer = makeAlivePlayer(9501)
	local warnsBeforeCooldown = #warns
	-- First request to mark cooldown
	giantPlacementRemote:FireServer(cooldownPlayer, makeAcceptedPayload("GiantStructure_Runtime_A"))
	-- Immediate second request should trigger cooldown rejection
	giantPlacementRemote:FireServer(cooldownPlayer, makeAcceptedPayload("GiantStructure_Runtime_F"))
	local sawCooldownReject = false
	for i = warnsBeforeCooldown + 1, #warns do
		if string.find(warns[i], "request_cooldown", 1, true) then
			sawCooldownReject = true
			break
		end
	end
	assertTrue(sawCooldownReject, "request_cooldown rejection reason is deterministic")

	-- player_not_alive
	local deadPlayer = makeAlivePlayer(9502)
	deadPlayer.Character.FindFirstChildOfClass = function(_self, className)
		if className == "Humanoid" then
			return { Health = 0 }
		end
		return nil
	end
	local warnsBeforeDead = #warns
	giantPlacementRemote:FireServer(deadPlayer, makeAcceptedPayload("GiantStructure_Runtime_B"))
	local sawDeadReject = false
	for i = warnsBeforeDead + 1, #warns do
		if string.find(warns[i], "player_not_alive", 1, true) then
			sawDeadReject = true
			break
		end
	end
	assertTrue(sawDeadReject, "player_not_alive rejection reason is deterministic")

	-- payload_box_world_center_out_of_bounds
	local outOfBoundsPayload = makeAcceptedPayloadAt("GiantStructure_Runtime_C", 99999, 0, 0)
	local warnsBeforeBounds = #warns
	clearRequestCooldownFor(cooldownPlayer)
	giantPlacementRemote:FireServer(cooldownPlayer, outOfBoundsPayload)
	local sawBoundsReject = false
	for i = warnsBeforeBounds + 1, #warns do
		if string.find(warns[i], "payload_box_world_center_out_of_bounds", 1, true) then
			sawBoundsReject = true
			break
		end
	end
	assertTrue(sawBoundsReject, "payload_box_world_center_out_of_bounds rejection reason is deterministic")

	-- payload_box_half_extents_invalid
	local invalidHalfExtentsPayload = makeAcceptedPayload("GiantStructure_Runtime_D")
	invalidHalfExtentsPayload.proposedOccupiedSpace[1].halfExtents = { x = -1, y = 2, z = 2 }
	local warnsBeforeHalfExtents = #warns
	clearRequestCooldownFor(cooldownPlayer)
	giantPlacementRemote:FireServer(cooldownPlayer, invalidHalfExtentsPayload)
	local sawHalfExtentsReject = false
	for i = warnsBeforeHalfExtents + 1, #warns do
		if string.find(warns[i], "payload_box_half_extents_invalid", 1, true) then
			sawHalfExtentsReject = true
			break
		end
	end
	assertTrue(sawHalfExtentsReject, "payload_box_half_extents_invalid rejection reason is deterministic")

	-- malformed_payload_box_fields (non-string tag)
	local malformedBoxPayload = makeAcceptedPayload("GiantStructure_Runtime_E")
	malformedBoxPayload.proposedOccupiedSpace[1].tag = 12345
	local warnsBeforeMalformedBox = #warns
	clearRequestCooldownFor(cooldownPlayer)
	giantPlacementRemote:FireServer(cooldownPlayer, malformedBoxPayload)
	local sawMalformedBoxReject = false
	for i = warnsBeforeMalformedBox + 1, #warns do
		if string.find(warns[i], "malformed_payload_box_fields", 1, true) then
			sawMalformedBoxReject = true
			break
		end
	end
	assertTrue(sawMalformedBoxReject, "malformed_payload_box_fields rejection reason is deterministic")
end

do
	local buildApi = globalEnv._GiantBuildModeService_QueryAPI
	assertTrue(type(buildApi.SpendWorksiteUpgradeCost) == "function", "worksite upgrade spend api exposed")

	buildApi.ApplyResourceAward({
		operationId = "test-seed-worksite-ledger-1",
		sourceKind = "defense_escape_outcome",
		awardedAt = 1,
		essence = 0,
		wood = 10,
		stone = 4,
		counterpartyUserId = nil,
	})

	local ledgerSpend = buildApi.SpendWorksiteUpgradeCost({
		operationId = "worksite-upgrade-test-ledger-1",
		spentAt = 10,
		essence = 0,
		wood = 10,
		stone = 4,
	})
	assertTrue(ledgerSpend.accepted == true, "worksite upgrade spends from ledger when affordable")
	assertEqual(ledgerSpend.spentFrom, "ledger", "worksite upgrade ledger spend source")

	local sessionBaseline = ResourceFlowState.GetSnapshot()
	local sessionSpend = buildApi.SpendWorksiteUpgradeCost({
		operationId = "worksite-upgrade-test-session-1",
		spentAt = 11,
		essence = 0,
		wood = 10,
		stone = 4,
	})
	assertTrue(sessionSpend.accepted == true, "worksite upgrade spends from session when ledger lacks wood/stone")
	assertEqual(sessionSpend.spentFrom, "session", "worksite upgrade session spend source")
	assertEqual(
		ResourceFlowState.GetSnapshot().Wood.stored,
		sessionBaseline.Wood.stored - 10,
		"session wood debited for worksite upgrade"
	)

	buildApi.ApplyResourceAward({
		operationId = "test-seed-worksite-ledger-essence-1",
		sourceKind = "defense_escape_outcome",
		awardedAt = 12,
		essence = 8,
		wood = 0,
		stone = 0,
		counterpartyUserId = nil,
	})
	ResourceFlowState.ResetSession("worksite_upgrade_mixed_test")
	ResourceFlowState.AddStoredAtomic(20, 10, "SeedWorksiteUpgradeMixedTest")
	local mixedBaseline = ResourceFlowState.GetSnapshot()
	local mixedSpend = buildApi.SpendWorksiteUpgradeCost({
		operationId = "worksite-upgrade-test-mixed-1",
		spentAt = 13,
		essence = 8,
		wood = 10,
		stone = 4,
	})
	assertTrue(mixedSpend.accepted == true, "worksite upgrade mixed ledger essence and session wood/stone")
	assertEqual(mixedSpend.spentFrom, "mixed", "worksite upgrade mixed spend source")
	assertEqual(buildApi.GetResourceLedgerSnapshot().essence, 0, "mixed spend debits ledger essence")
	assertEqual(
		ResourceFlowState.GetSnapshot().Wood.stored,
		mixedBaseline.Wood.stored - 10,
		"mixed spend debits session wood"
	)

	ResourceFlowState.AddStoredAtomic(0, 0, "SeedWorksiteUpgradeFoodTest", 4)
	local foodBaseline = ResourceFlowState.GetSnapshot()
	local foodSpend = buildApi.SpendWorksiteUpgradeCost({
		operationId = "worksite-upgrade-test-food-1",
		spentAt = 14,
		essence = 0,
		wood = 9,
		stone = 3,
		food = 2,
	})
	assertTrue(foodSpend.accepted == true, "worksite upgrade spends stored food from session")
	assertEqual(foodSpend.spentFrom, "session", "food-inclusive session spend source")
	assertEqual(
		ResourceFlowState.GetSnapshot().Food.stored,
		foodBaseline.Food.stored - 2,
		"session food debited for worksite upgrade"
	)

	buildApi.ApplyResourceAward({
		operationId = "test-seed-worksite-ledger-food-1",
		sourceKind = "defense_escape_outcome",
		awardedAt = 15,
		essence = 0,
		wood = 9,
		stone = 3,
		counterpartyUserId = nil,
	})
	ResourceFlowState.AddStoredAtomic(0, 0, "SeedWorksiteUpgradeLedgerFoodTest", 2)
	local ledgerFoodBaseline = ResourceFlowState.GetSnapshot()
	local ledgerFoodSpend = buildApi.SpendWorksiteUpgradeCost({
		operationId = "worksite-upgrade-test-ledger-food-1",
		spentAt = 16,
		essence = 0,
		wood = 9,
		stone = 3,
		food = 2,
	})
	assertTrue(ledgerFoodSpend.accepted == true, "worksite upgrade spends ledger wood/stone and session food")
	assertEqual(ledgerFoodSpend.spentFrom, "ledger", "ledger path remains ledger when food debited from granary")
	assertEqual(
		ResourceFlowState.GetSnapshot().Food.stored,
		ledgerFoodBaseline.Food.stored - 2,
		"ledger upgrade debits stored food"
	)
end

print("giant_build_mode_service_runtime_entrypoint: all checks passed")
