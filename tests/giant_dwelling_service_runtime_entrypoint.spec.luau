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

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}
	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end
	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
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
	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		child.Parent = parent
	end
end

local configFolder = makeNode("Config")
addChild(configFolder, "GiantDwellingConfig", "../../ReplicatedStorage/Shared/Config/GiantDwellingConfig")
addChild(configFolder, "StationConfig", "../../ReplicatedStorage/Shared/Config/StationConfig")
addChild(configFolder, "VillageWorksiteUpgradeConfig", "../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig")

local giantRealmFolder = makeNode("GiantRealm")
addChild(giantRealmFolder, "GiantHousingCapacityState", "../../ReplicatedStorage/Shared/GiantRealm/GiantHousingCapacityState")
addChild(
	giantRealmFolder,
	"VillageWorksiteUpgradeState",
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"
)

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local dwellingPart = makeNode("GiantDwelling_A", "BasePart")
local stationsRoot = makeNode("Stations")
addChild(stationsRoot, "GiantDwelling_A", dwellingPart)
local mapFolder = makeNode("Map")
addChild(mapFolder, "Stations", stationsRoot)
local workspaceService = makeNode("Workspace", "Workspace")
addChild(workspaceService, "Map", mapFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	return nil
end

game = fakeGame
_G._VillageWorksiteUpgradeService_QueryAPI = {
	GetGiantHousingCapacityMultiplier = function(dwellingId: string): number
		if dwellingId == "GiantDwelling_A" then
			return 2
		end
		return 1
	end,
}

require("../src/ServerScriptService/Services/GiantDwellingService.server")

local dwellingApi = _G._GiantDwellingService_QueryAPI
assertTrue(type(dwellingApi) == "table", "dwelling query api exposed")

local registered = dwellingApi.GetRegisteredDwellingIds()
assertEqual(#registered, 1, "registered dwelling count")
assertEqual(registered[1], "GiantDwelling_A", "registered dwelling id")

local capacity = dwellingApi.GetGiantHousingCapacity("GiantDwelling_A")
assertEqual(capacity, 2, "dwelling publishes upgraded housing capacity")

local snapshot = dwellingApi.GetDwellingSnapshot("GiantDwelling_A")
assertTrue(type(snapshot) == "table", "dwelling snapshot available")
assertEqual(snapshot.effect.effectKind, "GiantHousingCapacity", "dwelling effect kind")
assertEqual(snapshot.effect.effectScope, "GiantRealm", "dwelling effect scope")
assertEqual(snapshot.effect.sourceType, "FixedMapAnchor", "dwelling source type")
assertEqual(snapshot.effect.publishedGiantHousingCapacity, 2, "dwelling snapshot capacity")

local GiantHousingCapacityState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantHousingCapacityState")
local maxGiants = GiantHousingCapacityState.ResolveMaxGiantsFromHousing(capacity)
assertEqual(maxGiants, 2, "realm capacity consumer reads dwelling housing")

print("giant_dwelling_service_runtime_entrypoint: all checks passed")
