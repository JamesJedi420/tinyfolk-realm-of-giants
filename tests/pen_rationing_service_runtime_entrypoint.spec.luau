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
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"

local giantRealmFolder = makeNode("GiantRealm")
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
		return { Heartbeat = { Connect = function() end } }
	end
	if serviceName == "Players" then
		return {
			GetPlayers = function()
				return playersList
			end,
		}
	end
	return nil
end

game = fakeGame

local activeCaptures: { any } = {}
local starvationReleases: { any } = {}
local penUpgradeLevel = 0

_G._CaptureService_QueryAPI = {
	GetAllCaptures = function(_at: number?): { any }
		return activeCaptures
	end,
	ResolveCustodyEnd = function(targetUserId: number, endReason: string, _at: number?, _operationId: string?): any
		table.insert(starvationReleases, { targetUserId = targetUserId, endReason = endReason })
		for index = #activeCaptures, 1, -1 do
			if activeCaptures[index].targetUserId == targetUserId then
				table.remove(activeCaptures, index)
			end
		end
		return { accepted = true, reason = endReason }
	end,
}

_G._VillageWorksiteUpgradeService_QueryAPI = {
	GetUpgradeLevel = function(_penId: string): number
		return penUpgradeLevel
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

activeCaptures = {}
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 10)
assertEqual(ResourceFlowState.GetMaterialSnapshot("Food").stored, 0, "no captives consume no food")
assertEqual(penState.foodConsumedTotal, 0, "no captives increment consumed total")

ResourceFlowState.AddStoredAtomic(0, 0, "pen_rationing_seed", 5)
activeCaptures = {
	{ custodianUserId = 9001, targetUserId = 9101, startedAt = 20 },
	{ custodianUserId = 9001, targetUserId = 9102, startedAt = 21 },
}
rationApi.ResetForTests()
local beforeFood = ResourceFlowState.GetMaterialSnapshot("Food")
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 20)

local afterFood = ResourceFlowState.GetMaterialSnapshot("Food")
local expectedCost = 2 * PenRationingConfig.FoodPerCaptivePerInterval
assertEqual(afterFood.stored, beforeFood.stored - expectedCost, "two captives consume food each interval")
assertEqual(penState.foodConsumedTotal, expectedCost, "pen tracks consumed food total")
assertEqual(
	penPart:GetAttribute(PenRationingConfig.StateAttributes.LastFoodShortfall),
	false,
	"successful tick clears shortfall"
)

penUpgradeLevel = 3
rationApi.ResetForTests()
ResourceFlowState.AddStoredAtomic(0, 0, "pen_rationing_pen_level_seed", 2)
activeCaptures = {
	{ custodianUserId = 9001, targetUserId = 9101, startedAt = 30 },
	{ custodianUserId = 9001, targetUserId = 9102, startedAt = 31 },
}
local beforePenLevelFood = ResourceFlowState.GetMaterialSnapshot("Food")
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 40)
assertEqual(
	ResourceFlowState.GetMaterialSnapshot("Food").stored,
	beforePenLevelFood.stored - 1,
	"pen level 3 reduces food cost for two captives"
)
assertEqual(penPart:GetAttribute(PenRationingConfig.StateAttributes.PenUpgradeLevel), 3, "pen upgrade level exposed")

local custodian = {
	UserId = 9001,
	_Attributes = {},
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
}
playersList = { custodian }

activeCaptures = {
	{ custodianUserId = 9001, targetUserId = 9101, startedAt = 50 },
}
rationApi.ResetForTests()
ResourceFlowState.ResetSession("pen_rationing_morale_shortfall")
rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 60)
assertTrue(rationApi.GetCustodianMorale(9001) < PenRationingConfig.MoraleDefault, "shortfall reduces custodian morale")
assertEqual(
	penPart:GetAttribute(PenRationingConfig.StateAttributes.ConsecutiveShortfallTicks),
	1,
	"consecutive shortfall ticks tracked"
)

penUpgradeLevel = 0
rationApi.ResetForTests()
activeCaptures = {
	{ custodianUserId = 9001, targetUserId = 9101, startedAt = 70 },
	{ custodianUserId = 9001, targetUserId = 9102, startedAt = 80 },
}
starvationReleases = {}
for tick = 1, 3 do
	rationApi.AdvanceRationingForTests(PenRationingConfig.IntervalSeconds, 100 + tick)
end
assertEqual(#starvationReleases, 1, "third shortfall tick forces starvation release")
assertEqual(starvationReleases[1].targetUserId, 9101, "oldest captive released on starvation")
assertEqual(starvationReleases[1].endReason, "starvation", "starvation end reason")
assertEqual(penState.starvationReleasesTotal, 1, "pen tracks starvation releases")
assertEqual(#activeCaptures, 1, "one captive remains after starvation release")

print("pen_rationing_service_runtime_entrypoint.spec.luau: all checks passed")
