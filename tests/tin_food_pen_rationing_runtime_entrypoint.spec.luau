--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local MockPlayer = require("../tests/mocks/MockPlayer")

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

local function makeSignal()
	local callbacks: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			table.insert(callbacks, callback)
		end,
		Fire = function(_self: any, ...: any)
			for _, callback in ipairs(callbacks) do
				callback(...)
			end
		end,
	}
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
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

local function makeBasePart(name: string)
	local part = makeNode(name, "BasePart")
	return part
end

local configFolder = makeNode("Config")
configFolder._Children["CaptureConfig"] = "../../ReplicatedStorage/Shared/Config/CaptureConfig"
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["PenRationingConfig"] = "../../ReplicatedStorage/Shared/Config/PenRationingConfig"
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["CaptureState"] = "../../ReplicatedStorage/Shared/GiantRealm/CaptureState"
giantRealmFolder._Children["PenRationingState"] = "../../ReplicatedStorage/Shared/GiantRealm/PenRationingState"
giantRealmFolder._Children["VillageWorksiteUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local workspaceService = makeNode("Workspace")
local mapFolder = makeNode("Map")
local stationsFolder = makeNode("Stations")
local penPart = makeBasePart("Pen_A")
local granaryPart = makeBasePart("Granary_A")
addChild(stationsFolder, "Pen_A", penPart)
addChild(stationsFolder, "Granary_A", granaryPart)
addChild(mapFolder, "Stations", stationsFolder)
addChild(workspaceService, "Map", mapFolder)

local playersList: { any } = {}
local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "RunService" then
		return { Heartbeat = makeSignal() }
	end
	if serviceName == "Players" then
		return {
			PlayerAdded = { Connect = function() end },
			PlayerRemoving = makeSignal(),
			GetPlayers = function()
				return playersList
			end,
		}
	end
	return nil
end

game = fakeGame

_G._VillageWorksiteUpgradeService_QueryAPI = {
	GetHeldCapacityMultiplier = function(_penId: string): number
		return 2
	end,
}
_G._ScoreService_QueryAPI = {
	RequestScoreEvent = function(): any
		return { accepted = true, reason = "accepted" }
	end,
}

local PenRationingConfig = require("../src/ReplicatedStorage/Shared/Config/PenRationingConfig")

local giant = MockPlayer.new(9201, "Giant", { role = "Giant", positionZ = 0, health = 100 })
local targetA = MockPlayer.new(9202, "TargetA", { role = "Tinyfolk", positionZ = 0, health = 100 })
local targetB = MockPlayer.new(9203, "TargetB", { role = "Tinyfolk", positionZ = 1, health = 100 })
targetA:SetAttribute("DownedIsDowned", true)
targetB:SetAttribute("DownedIsDowned", true)
playersList = { giant, targetA, targetB }

require("../src/ServerScriptService/Services/CaptureService.server")

local scriptParent = makeNode("Services")
function scriptParent:WaitForChild(childName: string, _timeout: number?): any
	return self._Children[childName]
end
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = { Parent = scriptParent } :: any

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")
require("../src/ServerScriptService/Services/PenRationingService.server")

ResourceFlowState.ResetSession("tin_food_pen_rationing_runtime_entrypoint")
ResourceFlowState.RefreshDeliveryPoints()
ResourceFlowState.AddStoredAtomic(0, 0, "pen_rationing_e2e_seed", 6)

local captureApi = _G._CaptureService_QueryAPI
local rationApi = _G._PenRationingService_QueryAPI
assertTrue(type(captureApi) == "table", "capture api present")
assertTrue(type(rationApi) == "table", "pen rationing api present")

local captureA = captureApi.RequestCapture(9201, 9202, 100)
assertTrue(captureA.accepted == true, "first capture accepted")
local captureB = captureApi.RequestCapture(9201, 9203, 100.5)
assertTrue(captureB.accepted == true, "second capture accepted with pen capacity upgrade")
assertEqual(#captureApi.GetAllCaptures(101), 2, "two active captives")

local beforeFood = ResourceFlowState.GetMaterialSnapshot("Food")
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 101)
local afterFood = ResourceFlowState.GetMaterialSnapshot("Food")
assertEqual(afterFood.stored, beforeFood.stored - 2, "pen rationing spends food for held captives")
assertEqual(
	penPart:GetAttribute(PenRationingConfig.StateAttributes.FoodConsumedTotal),
	2,
	"pen attributes track rationing spend"
)

for tickIndex = 1, 5 do
	rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 101 + tickIndex)
end
assertTrue(captureApi.GetTargetCapture(9202, 106) == nil, "starvation releases oldest captive")
assertTrue(captureApi.GetTargetCapture(9203, 106) ~= nil, "newer captive remains after starvation")
assertEqual(
	penPart:GetAttribute(PenRationingConfig.StateAttributes.StarvationReleasesTotal),
	1,
	"pen tracks starvation release"
)
assertTrue(
	giant:GetAttribute(PenRationingConfig.StateAttributes.CustodianMorale) < PenRationingConfig.MoraleDefault,
	"starvation shortfall reduces custodian morale"
)

print("tin_food_pen_rationing_runtime_entrypoint.spec.luau: all checks passed")
