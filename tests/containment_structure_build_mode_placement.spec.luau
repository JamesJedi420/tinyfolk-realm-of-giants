--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
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
	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end
	function node:GetFullName(): string
		return self._FullName
	end
	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end
	function node:WaitForChild(childName: string, _timeout: number?): any
		return self._Children[childName]
	end
	function node:GetChildren(): { any }
		local children = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end
	function node:GetDescendants(): { any }
		local descendants = {}
		for _, child in pairs(self._Children) do
			table.insert(descendants, child)
			if type(child.GetDescendants) == "function" then
				for _, descendant in ipairs(child:GetDescendants()) do
					table.insert(descendants, descendant)
				end
			end
		end
		return descendants
	end
	function node:SetAttribute(attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end
	function node:GetAttribute(attributeName: string): any
		return self._Attributes[attributeName]
	end
	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		child.Parent = parent
	end
end

local function makeRemoteEvent(name: string): any
	local remote: any = {
		Name = name,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}
	function remote:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end
	remote.OnServerEvent = {
		Connect = function(_signal: any, callback: (any, any) -> ())
			remote._Handler = callback
		end,
	}
	function remote:FireServer(player: any, payload: any)
		if self._Handler ~= nil then
			self._Handler(player, payload)
		end
	end
	return remote
end

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
addChild(configFolder, "GiantBuildModeConfig", "../../ReplicatedStorage/Shared/Config/GiantBuildModeConfig")
addChild(configFolder, "GiantStructureCatalog", "../../ReplicatedStorage/Shared/Config/GiantStructureCatalog")
addChild(configFolder, "ContainmentStructureConfig", "../../ReplicatedStorage/Shared/Config/ContainmentStructureConfig")
addChild(configFolder, "SnareTrapConfig", "../../ReplicatedStorage/Shared/Config/SnareTrapConfig")
addChild(configFolder, "StationConfig", "../../ReplicatedStorage/Shared/Config/StationConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(configFolder, "GiantRealmTreasuryConfig", "../../ReplicatedStorage/Shared/Config/GiantRealmTreasuryConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder", "ReplicatedStorage.Shared.GiantRealm")
addChild(giantRealmFolder, "GiantRealmSaveSchema", "../../ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")
addChild(
	giantRealmFolder,
	"GiantRealmResourceState",
	"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState"
)
addChild(
	giantRealmFolder,
	"GiantRealmTreasuryPresentation",
	"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmTreasuryPresentation"
)
addChild(giantRealmFolder, "SnareTrapState", "../../ReplicatedStorage/Shared/GiantRealm/SnareTrapState")
addChild(
	giantRealmFolder,
	"ContainmentStructurePlacementState",
	"../../ReplicatedStorage/Shared/GiantRealm/ContainmentStructurePlacementState"
)
addChild(
	giantRealmFolder,
	"ContainmentStructureState",
	"../../ReplicatedStorage/Shared/GiantRealm/ContainmentStructureState"
)
addChild(giantRealmFolder, "GiantMacroRouteAccess", "../../ReplicatedStorage/Shared/GiantRealm/GiantMacroRouteAccess")

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
local placementRemote = makeRemoteEvent("GiantStructurePlacementRequest")
addChild(remotesFolder, "GiantStructurePlacementRequest", placementRemote)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
addChild(workspaceService, "Map", mapFolder)

local objectivesFolder = makeNode("Objectives")
local objectiveSite = makeNode("ObjectiveSite_A", "BasePart")
objectiveSite.Position = { x = 20, y = 0, z = 20 }
addChild(objectivesFolder, "ObjectiveSite_A", objectiveSite)
addChild(mapFolder, "Objectives", objectivesFolder)

local playersService: any = {
	_playerList = {},
	PlayerAdded = { Connect = function() end },
	PlayerRemoving = { Connect = function() end },
	GetPlayers = function(self: any)
		return self._playerList
	end,
}

local fakeGame: any = {}
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
	return {
		GetPlayers = function()
			return {}
		end,
	}
end

game = fakeGame

local scriptParent = makeNode("Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = { Parent = scriptParent } :: any

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")
ResourceFlowState.ResetSession("containment_build_mode_placement")

local ContainmentStructureService =
	require("../src/ServerScriptService/Services/ContainmentStructureService.server")(fakeGame, {
		disableScheduling = true,
	})

require("../src/ServerScriptService/Services/GiantBuildModeService.server")

local GiantRealmSaveSchema = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")
local queryApi = (getfenv() :: any)._GiantBuildModeService_QueryAPI

local giantPlayer = {
	UserId = 9101,
	Character = {
		FindFirstChildOfClass = function(_self: any, className: string): any
			if className == "Humanoid" then
				return { Health = 100 }
			end
			return nil
		end,
	},
	GetAttribute = function(_self: any, attributeName: string): any
		if attributeName == "Role" then
			return "Giant"
		end
		return nil
	end,
	SetAttribute = function() end,
}
playersService._playerList = { giantPlayer }

local containmentStructureId = "GiantStructure_Containment_Cage_A"
local placementPayload = {
	structureId = containmentStructureId,
	proposedOccupiedSpace = {
		{
			tag = "body",
			worldCenter = { x = 120, y = 2, z = 300 },
			halfExtents = { x = 12, y = 6, z = 12 },
		},
	},
}

local countBefore = ContainmentStructureService.getRegisteredStructureCount()
placementRemote:FireServer(giantPlayer, placementPayload)

local structuresFolder = mapFolder:FindFirstChild("ContainmentStructures")
local zonesFolder = mapFolder:FindFirstChild("ContainmentStructureZones")
assertTrue(structuresFolder ~= nil, "placement materializes ContainmentStructures folder")
assertTrue(zonesFolder ~= nil, "placement materializes ContainmentStructureZones folder")

local expectedStructureId = "ContainmentStructure_GiantStructure_Containment_Cage_A"
local expectedZoneId = "ContainmentStructureZone_GiantStructure_Containment_Cage_A"
assertTrue(structuresFolder:FindFirstChild(expectedStructureId) ~= nil, "placement materializes structure part")
assertTrue(zonesFolder:FindFirstChild(expectedZoneId) ~= nil, "placement materializes zone part")

local countAfter = ContainmentStructureService.getRegisteredStructureCount()
assertEqual(countAfter, countBefore + 1, "containment service registers placed structure")

local snapshot = ContainmentStructureService.getStructureSnapshot(expectedStructureId)
assertEqual(snapshot.structureType, "cage", "registered structure type")
assertEqual(snapshot.capacity, 2, "registered structure capacity")
assertEqual(snapshot.zoneId, expectedZoneId, "registered structure zone id")

local assign = ContainmentStructureService.resolveAssignOccupantForCapture({
	targetUserId = 4201,
	structureId = expectedStructureId,
	custodianPosition = { x = 120, y = 2, z = 300 },
	targetPosition = { x = 120, y = 2, z = 300 },
})
assertTrue(assign.accepted, "placed structure accepts occupant assignment")

local saveRoot, saveRootReason = queryApi.BuildSaveSnapshot(giantPlayer.UserId)
assertTrue(saveRoot ~= nil, "save snapshot includes containment placement")
assertEqual(saveRootReason, nil, "save snapshot has no failure reason")
if saveRoot then
	assertEqual(#saveRoot.placedStructures, 1, "save snapshot includes one placed structure")
	assertEqual(
		saveRoot.placedStructures[1].structureId,
		containmentStructureId,
		"save snapshot preserves containment structure id"
	)
	assertEqual(
		saveRoot.placedStructures[1].proposedOccupiedSpace[1].worldCenter.x,
		120,
		"save snapshot preserves containment placement center"
	)
end

local replayRoot = {
	schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
	ownerUserId = giantPlayer.UserId,
	placedStructures = if saveRoot then saveRoot.placedStructures else {},
}

local applyOk, applyReason = queryApi.ApplySaveSnapshot(replayRoot)
assertTrue(applyOk, "save snapshot apply replays containment placement")
assertEqual(applyReason, nil, "save snapshot apply has no failure reason")

structuresFolder = mapFolder:FindFirstChild("ContainmentStructures")
zonesFolder = mapFolder:FindFirstChild("ContainmentStructureZones")
assertTrue(structuresFolder:FindFirstChild(expectedStructureId) ~= nil, "replay materializes structure part")
assertTrue(zonesFolder:FindFirstChild(expectedZoneId) ~= nil, "replay materializes zone part")

local replayCount = ContainmentStructureService.getRegisteredStructureCount()
assertEqual(replayCount, countAfter, "replay restores containment registry count")

local replaySnapshot = ContainmentStructureService.getStructureSnapshot(expectedStructureId)
assertEqual(replaySnapshot.structureType, "cage", "replayed structure type")
assertEqual(replaySnapshot.capacity, 2, "replayed structure capacity")
assertEqual(replaySnapshot.zoneId, expectedZoneId, "replayed structure zone id")

local replayState = queryApi.GetPlacedStructure(containmentStructureId)
assertTrue(replayState ~= nil, "replay restores build-mode placement state")
if replayState then
	assertEqual(replayState.placedByUserId, giantPlayer.UserId, "replay preserves placer user id")
	assertEqual(replayState.proposedOccupiedSpace[1].worldCenter.x, 120, "replay preserves occupied space center")
end

local giantStructuresFolder = mapFolder:FindFirstChild("GiantStructures")
local misplacedArtifact = giantStructuresFolder and giantStructuresFolder:FindFirstChild(containmentStructureId)
assertTrue(misplacedArtifact == nil, "replay does not materialize containment under GiantStructures")

print("containment_structure_build_mode_placement: all checks passed")
