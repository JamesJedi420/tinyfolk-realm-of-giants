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
	vector3Mt.__sub = function(a: any, b: any)
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector3Mt)
	end
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

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	child.Parent = parent
end

local function makeBasePart(name: string, x: number, y: number, z: number)
	local part = makeNode(name, "BasePart")
	part.Position = Vector3.new(x, y, z)
	return part
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		Parent = nil,
		_Handler = nil,
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
		remote._ClientPayload = payload
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
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["TinyfolkLaborUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/TinyfolkLaborUpgradeConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["TinyfolkLaborUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/TinyfolkLaborUpgradeState"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local remotesFolder = makeNode("Remotes")
addChild(remotesFolder, "TinyfolkLaborUpgradeRequest", makeRemoteEvent("TinyfolkLaborUpgradeRequest"))
addChild(remotesFolder, "TinyfolkLaborUpgradeResponse", makeRemoteEvent("TinyfolkLaborUpgradeResponse"))
addChild(remotesFolder, "TinyfolkLaborUpgradeDebugRequest", makeRemoteEvent("TinyfolkLaborUpgradeDebugRequest"))
addChild(remotesFolder, "TinyfolkLaborUpgradeDebugResponse", makeRemoteEvent("TinyfolkLaborUpgradeDebugResponse"))

local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local laborBenchFolder = makeNode("TinyfolkLaborBench", "Model")
addChild(laborBenchFolder, "TinyfolkLaborBench_Haul_A", makeBasePart("TinyfolkLaborBench_Haul_A", -100, 2.5, 12))
addChild(laborBenchFolder, "TinyfolkLaborBench_Pace_A", makeBasePart("TinyfolkLaborBench_Pace_A", -108, 2.5, 12))

local stationsFolder = makeNode("Stations")
addChild(stationsFolder, "TinyfolkLaborBench", laborBenchFolder)

local mapFolder = makeNode("Map")
addChild(mapFolder, "Stations", stationsFolder)

local workspaceService = makeNode("Workspace")
addChild(workspaceService, "Map", mapFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "Players" then
		return {
			PlayerRemoving = {
				Connect = function(_signal: any, _handler: any)
					return {}
				end,
			},
		}
	end
	return nil
end

game = fakeGame

local scriptParent = makeNode("Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = {
	Parent = scriptParent,
} :: any

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local TinyfolkLaborUpgradeConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkLaborUpgradeConfig")
local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")

ResourceFlowState.ResetSession("tinyfolk_labor_upgrade_test")
ResourceFlowState.AddStoredAtomic(0, 0, "test_seed", 20)

local tinyfolkPlayer: any = {
	UserId = 8101,
	_Attributes = { Role = RoleConfig.Roles.Tinyfolk },
	Character = {
		FindFirstChild = function(_self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return {
					Position = Vector3.new(-100, 2.5, 12),
					IsA = function(_root: any, className: string): boolean
						return className == "BasePart"
					end,
				}
			end
			return nil
		end,
	},
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
}

local giantPlayer: any = {
	UserId = 8102,
	_Attributes = { Role = RoleConfig.Roles.Giant },
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
}

require("../src/ServerScriptService/Services/TinyfolkLaborUpgradeService.server")

local upgradeApi = globalEnv._TinyfolkLaborUpgradeService_QueryAPI
assertTrue(type(upgradeApi) == "table", "tinyfolk labor upgrade query api available")

upgradeApi.SetPlayerStateForTests(8101, {
	laborTokens = 3,
	haulYieldLevel = 0,
	taskPaceLevel = 0,
})

local haulResult = upgradeApi.RequestUpgradeForTests(tinyfolkPlayer, "TinyfolkLaborBench_Haul_A", 10)
assertTrue(haulResult.accepted, "haul bench upgrade accepted")
assertEqual(haulResult.level, 1, "haul bench reaches level 1")
assertEqual(
	tinyfolkPlayer:GetAttribute(TinyfolkLaborUpgradeConfig.HaulYieldLevelAttribute),
	1,
	"haul level exposed on player debug attributes"
)
assertEqual(
	tinyfolkPlayer:GetAttribute(TinyfolkLaborUpgradeConfig.EffectiveHaulYieldMultiplierAttribute),
	1.25,
	"haul multiplier exposed on player debug attributes"
)

local paceResult = upgradeApi.RequestUpgradeForTests(tinyfolkPlayer, "TinyfolkLaborBench_Pace_A", 20)
assertTrue(paceResult.accepted, "pace bench upgrade accepted")
assertEqual(paceResult.level, 1, "pace bench reaches level 1")
assertEqual(
	tinyfolkPlayer:GetAttribute(TinyfolkLaborUpgradeConfig.TaskPaceLevelAttribute),
	1,
	"task pace level exposed on player debug attributes"
)

local foodSnapshot = ResourceFlowState.GetMaterialSnapshot("Food")
assertTrue(foodSnapshot.stored <= 16, "pace upgrade spends stored food from granary pool")

local rejectedGiant = upgradeApi.RequestUpgradeForTests(giantPlayer, "TinyfolkLaborBench_Haul_A", 30)
assertEqual(rejectedGiant.reason, "requester_not_tinyfolk", "giant cannot purchase tinyfolk labor upgrades")

upgradeApi.RecordWorkActionCompleted(tinyfolkPlayer)
assertEqual(
	tinyfolkPlayer:GetAttribute(TinyfolkLaborUpgradeConfig.LaborTokensAttribute),
	1,
	"completed labor work action grants one token"
)

print("tinyfolk_labor_upgrade_service_runtime_entrypoint: all checks passed")
