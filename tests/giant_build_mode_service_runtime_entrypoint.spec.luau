--!strict

local GiantBuildModeConfig = require("../src/ReplicatedStorage/Shared/Config/GiantBuildModeConfig")
local GiantStructureCatalog = require("../src/ReplicatedStorage/Shared/Config/GiantStructureCatalog")

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

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
addChild(workspaceService, "Map", mapFolder)

local playerRemovingConnections: { (any) -> () } = {}
local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerRemoving = {
		Connect = function(_signal: any, callback: (any) -> ())
			table.insert(playerRemovingConnections, callback)
		end,
	},
}

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

script = {
	Parent = makeNode("Services", "Folder", "ServerScriptService.Services"),
} :: any

local function makeAlivePlayer(userId: number)
	local humanoid = {
		Health = 100,
	}
	local character = {
		FindFirstChildOfClass = function(self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}
	return {
		UserId = userId,
		Character = character,
	}
end

local function makeAcceptedPayload(structureId: string): any
	return {
		structureId = structureId,
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 120, y = 0, z = 300 },
				halfExtents = { x = 20, y = 8, z = 20 },
			},
		},
	}
end

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
assertTrue(giantPlacementRemote._Handler ~= nil, "service binds GiantStructurePlacementRequest OnServerEvent")
assertTrue(constructionBuildRemote._Handler == nil, "service does not bind ConstructionBuildRequest")

local registry = _G._GiantBuildModeService_Registry
assertTrue(type(registry) == "table", "registry export is available")

-- Rejected malformed payload must not mutate registry or world artifacts.
local malformedPlayer = makeAlivePlayer(9401)
local warnsBeforeMalformed = #warns
giantPlacementRemote:FireServer(malformedPlayer, { structureId = "", proposedOccupiedSpace = {} })
assertTrue(registry[""] == nil, "malformed payload does not mutate registry")

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
local warnsBeforeUnknown = #warns
giantPlacementRemote:FireServer(unknownPlayer, makeAcceptedPayload("GiantStructure_Unknown"))
assertTrue(registry["GiantStructure_Unknown"] == nil, "unknown structure id does not mutate registry")

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
local acceptedStructureId = "GiantStructure_Runtime_A"
giantPlacementRemote:FireServer(acceptedPlayer, makeAcceptedPayload(acceptedStructureId))

local acceptedState = registry[acceptedStructureId]
assertTrue(acceptedState ~= nil, "accepted payload records structure placement state")
if acceptedState then
	assertEqual(acceptedState.structureId, acceptedStructureId, "accepted state stores structure id")
	assertEqual(acceptedState.placedByUserId, acceptedPlayer.UserId, "accepted state stores placer user id")
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

local queryApi = _G._GiantBuildModeService_QueryAPI
assertTrue(type(queryApi) == "table", "query API export is available")
assertTrue(type(queryApi.GetPlacedStructure) == "function", "query API exposes GetPlacedStructure")
assertTrue(type(queryApi.GetAllPlacedStructures) == "function", "query API exposes GetAllPlacedStructures")
assertTrue(type(queryApi.IsStructurePlaced) == "function", "query API exposes IsStructurePlaced")

assertTrue(queryApi.IsStructurePlaced(acceptedStructureId), "query API reports placed structure")
assertTrue(not queryApi.IsStructurePlaced("Unknown_Giant_Structure"), "query API reports unknown structure not placed")

local fetched = queryApi.GetPlacedStructure(acceptedStructureId)
assertTrue(fetched ~= nil, "query API returns accepted structure state")
if fetched then
	assertEqual(fetched.structureId, acceptedStructureId, "query API state structureId matches")
end

-- Duplicate structure id should reject and preserve prior accepted state.
local duplicatePlayer = makeAlivePlayer(9403)
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

print("giant_build_mode_service_runtime_entrypoint: all checks passed")
