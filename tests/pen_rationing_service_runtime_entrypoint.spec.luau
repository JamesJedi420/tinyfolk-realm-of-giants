--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

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
	Vector3 = {
		new = function(x: number, y: number, z: number)
			return { X = x, Y = y, Z = z }
		end,
	} :: any
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
	part.Position = Vector3.new(0, 0, 0)
	return part
end

local configFolder = makeNode("Config")
configFolder._Children["PenRationingConfig"] = "../../ReplicatedStorage/Shared/Config/PenRationingConfig"
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["PenRationingState"] = "../../ReplicatedStorage/Shared/GiantRealm/PenRationingState"

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

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "RunService" then
		return { Heartbeat = { Connect = function() end } }
	end
	return nil
end

game = fakeGame

local activeCaptiveCount = 0
_G._CaptureService_QueryAPI = {
	GetAllCaptures = function(_at: number?): { any }
		local captures: { any } = {}
		for index = 1, activeCaptiveCount do
			table.insert(captures, {
				custodianUserId = 9000 + index,
				targetUserId = 9100 + index,
			})
		end
		return captures
	end,
}

local scriptParent = makeNode("Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = { Parent = scriptParent } :: any

local PenRationingConfig = require("../src/ReplicatedStorage/Shared/Config/PenRationingConfig")
local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")

require("../src/ServerScriptService/Services/PenRationingService.server")

ResourceFlowState.ResetSession("pen_rationing_service_runtime_entrypoint")
ResourceFlowState.RefreshDeliveryPoints()

local rationApi = _G._PenRationingService_QueryAPI
assertTrue(type(rationApi) == "table", "pen rationing query api present")

local penState = rationApi.GetPenState("Pen_A")
assertTrue(penState ~= nil, "pen state registered")

activeCaptiveCount = 0
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 10)
assertEqual(ResourceFlowState.GetMaterialSnapshot("Food").stored, 0, "no captives consume no food")
assertEqual(penState.foodConsumedTotal, 0, "no captives increment consumed total")

ResourceFlowState.AddStoredAtomic(0, 0, "pen_rationing_seed", 5)
activeCaptiveCount = 2
rationApi.ResetForTests()
local beforeFood = ResourceFlowState.GetMaterialSnapshot("Food")
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 20)

local afterFood = ResourceFlowState.GetMaterialSnapshot("Food")
local expectedCost = 2 * PenRationingConfig.FoodPerCaptivePerInterval
assertEqual(afterFood.stored, beforeFood.stored - expectedCost, "two captives consume food each interval")
assertEqual(penState.foodConsumedTotal, expectedCost, "pen tracks consumed food total")
assertEqual(
	penPart:GetAttribute(PenRationingConfig.StateAttributes.ActiveCaptiveCount),
	2,
	"pen part mirrors active captive count"
)
assertEqual(
	penPart:GetAttribute(PenRationingConfig.StateAttributes.LastFoodShortfall),
	false,
	"successful tick clears shortfall"
)

activeCaptiveCount = 3
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 30)
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 40)
assertEqual(
	penPart:GetAttribute(PenRationingConfig.StateAttributes.LastFoodShortfall),
	true,
	"shortfall when granary empty"
)
assertTrue(penState.lastFoodShortfall == true, "pen state records shortfall")

print("pen_rationing_service_runtime_entrypoint.spec.luau: all checks passed")
