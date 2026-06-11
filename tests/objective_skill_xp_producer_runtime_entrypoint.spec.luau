--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local MockPlayer = require("../tests/mocks/MockPlayer")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local SkillProgressionConfig = require("../src/ReplicatedStorage/Shared/Config/SkillProgressionConfig")
local SkillCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/SkillCatalogSchema")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in pairs(value) do
		result[key] = cloneTable(child)
	end
	return result
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

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
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
		local walk: (current: any) -> ()
		walk = function(current: any)
			for _, child in pairs(current._Children) do
				table.insert(descendants, child)
				if type(child._Children) == "table" then
					walk(child)
				end
			end
		end
		walk(self)
		return descendants
	end

	function node.GetFullName(self: any): string
		return self._FullName
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

if Color3 == nil then
	Color3 = {
		fromRGB = function(r: number, g: number, b: number)
			return { R = r, G = g, B = b }
		end,
	} :: any
end

if Enum == nil then
	Enum = {
		Material = {
			Grass = "Grass",
		},
	} :: any
end

if Vector3 == nil then
	local vector3Mt: any = {}
	vector3Mt.__index = function(self: any, key: string)
		if key == "Magnitude" then
			return math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
		end
		return nil
	end
	vector3Mt.__sub = function(a: any, b: any)
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector3Mt)
	end

	Vector3 = {
		new = function(x: number, y: number, z: number)
			return setmetatable({ X = x, Y = y, Z = z }, vector3Mt)
		end,
	} :: any
end

local profileDataByUserId: { [number]: any } = {}

local ownerLayer = {
	LoadPlayerProfile = function(_profileKey: string, userId: number): any
		local data = profileDataByUserId[userId]
		if type(data) ~= "table" then
			data = ProfilePersistenceGateway.LoadDefaultPlayerProfile(userId).data
			profileDataByUserId[userId] = cloneTable(data)
		end
		return {
			ok = true,
			operation = "LoadPlayerProfile",
			data = cloneTable(profileDataByUserId[userId]),
		}
	end,
	SavePlayerProfile = function(_profileKey: string, userId: number, data: any): any
		profileDataByUserId[userId] = cloneTable(data)
		return { ok = true, operation = "SavePlayerProfile" }
	end,
	ReleasePlayerProfile = function(): any
		return { ok = true, operation = "ReleasePlayerProfile" }
	end,
	LoadGiantRealmProfile = function(): any
		return { ok = true, operation = "LoadGiantRealmProfile", data = {} }
	end,
	SaveGiantRealmProfile = function(): any
		return { ok = true, operation = "SaveGiantRealmProfile" }
	end,
	ReleaseGiantRealmProfile = function(): any
		return { ok = true, operation = "ReleaseGiantRealmProfile" }
	end,
}

ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.ConfigureOwnerLayer(ownerLayer)

local progressionSkillId = "objective_craft"
local configuredAward = SkillProgressionConfig.XpAwardsByOutcomeKind.objective_qte_success
assertTrue(type(configuredAward) == "table", "design assigns objective qte xp source")
assertEqual(configuredAward.skillId, progressionSkillId, "objective qte xp maps to objective_craft")

local catalogRecord = SkillCatalogSchema.GetSkillRecord(progressionSkillId)
assertTrue(catalogRecord ~= nil, "default catalog includes objective progression skill")

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
		_ClientPayload = nil,
	}

	function remote.IsA(_self: any, expectedClass: string): boolean
		return expectedClass == "RemoteEvent"
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireServer(_self: any, firePlayer: any, payload: any)
		if remote._Handler == nil then
			error(string.format("remote %s handler not connected", remote.Name))
		end
		remote._Handler(firePlayer, payload)
	end

	function remote.FireClient(_self: any, _player: any, payload: any)
		remote._ClientPayload = payload
	end

	return remote
end

local function makeBasePart(name: string, x: number, y: number, z: number)
	local part = makeNode(name, "BasePart")
	part.Position = Vector3.new(x, y, z)
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Material = Enum.Material.Grass
	return part
end

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
local buildRemote = makeRemoteEvent("ConstructionBuildRequest")
addChild(remotesFolder, "ConstructionBuildRequest", buildRemote)
addChild(remotesFolder, "ConstructionDebugStateRequest", makeRemoteEvent("ConstructionDebugStateRequest"))
addChild(remotesFolder, "ConstructionDebugStateResponse", makeRemoteEvent("ConstructionDebugStateResponse"))

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
configFolder._Children["ConstructionConfig"] = "../../ReplicatedStorage/Shared/Config/ConstructionConfig"
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["SkillProgressionConfig"] = "../../ReplicatedStorage/Shared/Config/SkillProgressionConfig"
configFolder._Children["SkillCatalogSchema"] = "../../ReplicatedStorage/Shared/Config/SkillCatalogSchema"

local skillsFolder = makeNode("Skills", "Folder", "ReplicatedStorage.Shared.Skills")
skillsFolder._Children["SkillXpAwardPolicy"] = "../../ReplicatedStorage/Shared/Skills/SkillXpAwardPolicy"
skillsFolder._Children["SkillsProfileState"] = "../../ReplicatedStorage/Shared/Skills/SkillsProfileState"

local sharedConstructionFolder = makeNode("Construction", "Folder", "ReplicatedStorage.Shared.Construction")
sharedConstructionFolder._Children["ContextualTaskProgressLogic"] =
	"../../ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic"
sharedConstructionFolder._Children["TaskQteTimingLogic"] =
	"../../ReplicatedStorage/Shared/Construction/TaskQteTimingLogic"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "Skills", skillsFolder)
addChild(sharedFolder, "Construction", sharedConstructionFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local constructionSitePart = makeBasePart("ConstructionSite_A", 10, 0, 10)
addChild(mapFolder, "ConstructionSite_A", constructionSitePart)
addChild(workspaceService, "Map", mapFolder)

local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerRemoving = {
		Connect = function() end,
	},
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
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

require("../src/ServerScriptService/Services/SkillProgressionService.server")

local progressionApi = _G._SkillProgressionService_QueryAPI
assertTrue(type(progressionApi) == "table", "skill progression query api present")

local player = MockPlayer.new(2451, "Tinyfolk_Qte_Player", { role = "Tinyfolk", health = 100 })
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(player).ok, "player profile loaded")

local unlockResult = progressionApi.UnlockSkill(player, progressionSkillId)
assertTrue(unlockResult.accepted, "objective skill unlocked before xp award")

local ObjectiveSkillXpProducer = require("../src/ServerScriptService/Services/ObjectiveSkillXpProducer")

local directAwardAccepted, directAwardReason = ObjectiveSkillXpProducer.RecordObjectiveQteSuccessXp(player)
assertTrue(directAwardAccepted, "producer awards xp for unlocked objective skill")
assertEqual(directAwardReason, "accepted", "producer accepted reason")

local progress = progressionApi.GetSkillProgress(player, progressionSkillId)
assertEqual(progress.xp, configuredAward.xpAmount, "producer writes configured objective qte xp")

local persisted = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertTrue(persisted.ok, "profile persisted after objective qte xp award")
assertEqual(
	persisted.data.skillsProfileState.skillProgressById[progressionSkillId].xp,
	configuredAward.xpAmount,
	"profile stores objective qte awarded xp"
)

_G._DistrictPlacementService_QueryAPI = {
	GetAllPlacedDistricts = function()
		return {}
	end,
	GetPlacedDistrict = function()
		return nil
	end,
	GetPlacedDistrictsByPlayer = function()
		return {}
	end,
	IsDistrictPlaced = function()
		return false
	end,
}

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
scriptParent._Children["ObjectiveSkillXpProducer"] = "../../ServerScriptService/Services/ObjectiveSkillXpProducer"
script = {
	Parent = scriptParent,
} :: any

local function makeAlivePlayer(userId: number, position: Vector3)
	local root = makeBasePart("HumanoidRootPart", position.X, position.Y, position.Z)
	local humanoid = { Health = 100 }
	local character = {
		FindFirstChild = function(_self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return root
			end
			return nil
		end,
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
		_Attributes = {},
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
	}
end

local serviceLoaded, serviceError = pcall(function()
	require("../src/ServerScriptService/Services/ConstructionService.server")
end)
assertTrue(serviceLoaded, "construction service loads for qte xp integration: " .. tostring(serviceError))

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")
ResourceFlowState.AddStoredAtomic(100, 100, "objective_skill_xp_producer_test_seed", 100)

local ConstructionConfig = require("../src/ReplicatedStorage/Shared/Config/ConstructionConfig")
ConstructionConfig.TaskQteEnabled = true
ConstructionConfig.TaskQteWindowSeconds = 5.0
ConstructionConfig.TaskQteBonusSeconds = 0.35
ConstructionConfig.TaskQteFailureDisrupts = true

local integrationPlayer = makeAlivePlayer(2452, Vector3.new(16, 0, 10))
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(integrationPlayer).ok, "integration player profile loaded")
assertTrue(
	progressionApi.UnlockSkill(integrationPlayer, progressionSkillId).accepted,
	"integration player skill unlocked"
)

buildRemote:FireServer(integrationPlayer, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 400,
})
buildRemote:FireServer(integrationPlayer, {
	siteId = "ConstructionSite_A",
	mode = "complete",
	now = 401.35,
	qteTapAt = 401.35,
})

assertEqual(
	integrationPlayer:GetAttribute("ConstructionTaskQteResult"),
	"success",
	"construction qte success marks qte attribute"
)

local integrationProgress = progressionApi.GetSkillProgress(integrationPlayer, progressionSkillId)
assertEqual(integrationProgress.xp, configuredAward.xpAmount, "construction qte success awards configured skill xp")

local integrationPersisted = ProfilePersistenceGateway.GetLoadedPlayerProfileData(integrationPlayer)
assertEqual(
	integrationPersisted.data.skillsProfileState.skillProgressById[progressionSkillId].xp,
	configuredAward.xpAmount,
	"construction qte success persists awarded xp"
)

print("objective_skill_xp_producer_runtime_entrypoint.spec.luau: all checks passed")
