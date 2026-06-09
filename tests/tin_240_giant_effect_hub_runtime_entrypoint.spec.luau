--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local globalEnv: any = getfenv()

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

if Vector3 == nil then
	local vector3Mt: any = {}
	vector3Mt.__index = function(self: any, key: string)
		if key == "Magnitude" then
			return math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
		end
		return nil
	end
	Vector3 = {
		new = function(x: number, y: number, z: number)
			return setmetatable({ X = x, Y = y, Z = z }, vector3Mt)
		end,
	} :: any
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
		Parent = nil,
	}

	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end

	function node:WaitForChild(childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	function node:GetDescendants(): { any }
		local descendants: { any } = {}
		local function walk(current: any)
			for _, child in pairs(current._Children) do
				table.insert(descendants, child)
				walk(child)
			end
		end
		walk(self)
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
	child.Parent = parent
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
		_LastClientPayload = nil,
	}

	function remote:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote:FireClient(_player: any, payload: any)
		self._LastClientPayload = payload
	end

	return remote
end

Instance = {
	new = function(className: string): any
		if className == "Folder" then
			return makeNode("Folder", "Folder")
		end
		if className == "RemoteEvent" then
			return makeRemoteEvent("GeneratedRemote")
		end
		error(string.format("unsupported Instance.new(%q)", className))
	end,
} :: any

local configFolder = makeNode("Config")
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["ShrineConfig"] = "../../ReplicatedStorage/Shared/Config/ShrineConfig"
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["UpgradeBoardConfig"] = "../../ReplicatedStorage/Shared/Config/UpgradeBoardConfig"
configFolder._Children["VillageUpgradeHubConfig"] = "../../ReplicatedStorage/Shared/Config/VillageUpgradeHubConfig"
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"

local upgradeBoardFolder = makeNode("UpgradeBoard")
upgradeBoardFolder._Children["UpgradeProgressionLogic"] =
	"../../ReplicatedStorage/Shared/UpgradeBoard/UpgradeProgressionLogic"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["VillageWorksiteUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"
giantRealmFolder._Children["GiantWorksiteEffectResolution"] =
	"../../ReplicatedStorage/Shared/GiantRealm/GiantWorksiteEffectResolution"
giantRealmFolder._Children["VillageUpgradeHubState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageUpgradeHubState"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(sharedFolder, "UpgradeBoard", upgradeBoardFolder)

local remotesFolder = makeNode("Remotes")
addChild(remotesFolder, "VillageWorksiteUpgradeRequest", makeRemoteEvent("VillageWorksiteUpgradeRequest"))
addChild(remotesFolder, "VillageWorksiteUpgradeResponse", makeRemoteEvent("VillageWorksiteUpgradeResponse"))
addChild(remotesFolder, "VillageUpgradeHubRequest", makeRemoteEvent("VillageUpgradeHubRequest"))
addChild(remotesFolder, "VillageUpgradeHubResponse", makeRemoteEvent("VillageUpgradeHubResponse"))
addChild(remotesFolder, "UpgradeBoardSelectRequest", makeRemoteEvent("UpgradeBoardSelectRequest"))
addChild(remotesFolder, "UpgradeBoardSelectResult", makeRemoteEvent("UpgradeBoardSelectResult"))
addChild(remotesFolder, "UpgradeBoardDebugStateRequest", makeRemoteEvent("UpgradeBoardDebugStateRequest"))
addChild(remotesFolder, "UpgradeBoardDebugStateResponse", makeRemoteEvent("UpgradeBoardDebugStateResponse"))
addChild(remotesFolder, "UpgradeBoardDebugEssenceDrain", makeRemoteEvent("UpgradeBoardDebugEssenceDrain"))

local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local boardPart = makeNode("GiantUpgradeBoard_A", "BasePart")
boardPart.Position = Vector3.new(0, 0, 0)
local stationsFolder = makeNode("Stations")
addChild(stationsFolder, "GiantUpgradeBoard_A", boardPart)
local mapFolder = makeNode("Map")
addChild(mapFolder, "Stations", stationsFolder)
local workspaceService = makeNode("Workspace")
addChild(workspaceService, "Map", mapFolder)

local playersList: { any } = {}
local playersService: any = {
	PlayerAdded = { Connect = function() end },
	PlayerRemoving = { Connect = function() end },
	GetPlayers = function()
		return playersList
	end,
	GetPlayerByUserId = function(_self: any, userId: number)
		for _, player in ipairs(playersList) do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end,
}

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "Players" then
		return playersService
	end
	return nil
end

game = fakeGame

local scriptParent = makeNode("Services", "Folder")
scriptParent._Children["GiantEssenceSession"] = "../../ServerScriptService/Services/GiantEssenceSession"
script = { Parent = scriptParent } :: any

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")

local humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16 }
local root = makeNode("HumanoidRootPart", "BasePart")
root.Position = Vector3.new(0, 0, 0)
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

local giantPlayer: any = {
	UserId = 9402,
	Character = character,
	CharacterAdded = { Connect = function() end },
	_Attributes = {},
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
	GetAttributeChangedSignal = function()
		return { Connect = function() end }
	end,
}
giantPlayer:SetAttribute("Role", RoleConfig.Roles.Giant)
table.insert(playersList, giantPlayer)

_G._GiantBuildModeService_QueryAPI = {
	GetRealmOwnerUserId = function()
		return 9402
	end,
	SpendWorksiteUpgradeCost = function(_spend: any): any
		return { accepted = true, spentFrom = "session" }
	end,
	RollbackWorksiteUpgradeSpend = function() end,
}

require("../src/ServerScriptService/Services/VillageWorksiteUpgradeService.server")
require("../src/ServerScriptService/Services/UpgradeBoardService.server")
require("../src/ServerScriptService/Services/VillageUpgradeHubService.server")

local worksiteApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
local boardApi = globalEnv._UpgradeBoardService_QueryAPI
local hubApi = globalEnv._VillageUpgradeHubService_QueryAPI
assertTrue(type(worksiteApi) == "table", "worksite query api")
assertTrue(type(boardApi) == "table", "board query api")
assertTrue(type(hubApi) == "table", "hub query api")

local hubResponseRemote = remotesFolder:WaitForChild("VillageUpgradeHubResponse")
local hubSnapshot = hubApi.RequestHubForTests(giantPlayer, { boardId = "GiantUpgradeBoard_A" }, 100, hubResponseRemote)
assertEqual(hubSnapshot.accepted, true, "hub snapshot accepted")
assertTrue(type(hubSnapshot.boardTrack) == "table", "hub board track present")
assertTrue(type(hubSnapshot.worksiteSummaries) == "table", "hub worksite summaries present")
assertTrue(#hubSnapshot.worksiteSummaries > 0, "hub worksite rows")

local baseEffects = boardApi.GetResolvedEffects(giantPlayer.UserId)
assertEqual(baseEffects.maxHealth, 100, "base max health")
assertEqual(baseEffects.walkSpeed, 16, "base walk speed")
assertEqual(baseEffects.powerBudget, 100, "base power budget")
assertEqual(baseEffects.movementControl, 1, "base movement control")

local shrineResponseRemote = remotesFolder:WaitForChild("VillageWorksiteUpgradeResponse")
local shrineResult = worksiteApi.RequestUpgradeForTests(giantPlayer, "Shrine_A", 101, shrineResponseRemote)
assertEqual(shrineResult.accepted, true, "shrine upgrade accepted")
assertEqual(shrineResult.level, 1, "shrine level 1")
assertEqual(giantPlayer:GetAttribute("GiantEffect_MaxHealth"), 117, "shrine L1 max health attribute")
assertEqual(giantPlayer:GetAttribute("GiantEffect_PowerBudget"), 108, "shrine L1 power budget attribute")

local dwellingResult = worksiteApi.RequestUpgradeForTests(giantPlayer, "GiantDwelling_A", 102, shrineResponseRemote)
assertEqual(dwellingResult.accepted, true, "dwelling upgrade accepted")
assertEqual(dwellingResult.level, 1, "dwelling level 1")
assertEqual(giantPlayer:GetAttribute("GiantEffect_WalkSpeed"), 18, "dwelling L1 walk speed attribute")
assertEqual(giantPlayer:GetAttribute("GiantEffect_MovementControl"), 1.08, "dwelling L1 movement control attribute")

print("tin_240_giant_effect_hub_runtime_entrypoint.spec.luau: all checks passed")
