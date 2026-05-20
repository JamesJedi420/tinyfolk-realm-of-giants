--!strict

local MockPlayer = require("../tests/mocks/MockPlayer")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
	}

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.GetChildren(self: any): { any }
		local children = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
local sharedFolder = makeNode("Shared", "Folder")
local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "RealmObjectiveState", "../../ReplicatedStorage/Shared/GiantRealm/RealmObjectiveState")
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(replicatedStorage, "Shared", sharedFolder)

local workspaceService = makeNode("Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder")
local objectivesFolder = makeNode("Objectives", "Folder")

local constructionSiteA = makeNode("ConstructionSite_A", "Part")
local constructionSiteB = makeNode("ConstructionSite_B", "Part")
local stationA = makeNode("Station_A", "Part")
local shrineA = makeNode("Shrine_A", "Part")
local customObjectiveSite = makeNode("Marker_Custom", "Part")
customObjectiveSite:SetAttribute("ObjectiveSiteId", "ObjectiveSite_Custom_A")

addChild(objectivesFolder, "ConstructionSite_A", constructionSiteA)
addChild(objectivesFolder, "ConstructionSite_B", constructionSiteB)
addChild(objectivesFolder, "Station_A", stationA)
addChild(objectivesFolder, "Shrine_A", shrineA)
addChild(objectivesFolder, "Marker_Custom", customObjectiveSite)

addChild(mapFolder, "Objectives", objectivesFolder)
addChild(workspaceService, "Map", mapFolder)

local playersList: { any } = {
	MockPlayer.new(5001, "Tinyfolk_A", { role = "Tinyfolk", health = 100 }),
	MockPlayer.new(5002, "Tinyfolk_B", { role = "Tinyfolk", health = 100 }),
	MockPlayer.new(5003, "Tinyfolk_C", { role = "Tinyfolk", health = 100 }),
	MockPlayer.new(5101, "Giant_A", { role = "Giant", health = 100 }),
}

local playersService: any = {}
function playersService:GetPlayers(): { any }
	return playersList
end

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

require("../src/ServerScriptService/Services/RealmObjectiveService.server")

local queryApi: any = _G._RealmObjectiveService_QueryAPI
assertTrue(type(queryApi) == "table", "realm objective service exposes query api")

local initialSnapshot = queryApi.GetObjectiveSnapshot()
assertEqual(initialSnapshot.totalSiteCount, 5, "startup discovers expected objective site count")
assertEqual(initialSnapshot.completedCount, 0, "startup completed count is zero")
assertEqual(initialSnapshot.unresolvedCount, 5, "startup unresolved count matches total")
assertEqual(initialSnapshot.requiredCompletions, 2, "required completions scale at three tinyfolk")
assertFalse(initialSnapshot.escapeReady, "escape not ready at startup")

local firstCompletion = queryApi.RecordObjectiveCompletion("ConstructionSite_A", 5001, 10)
assertTrue(firstCompletion.accepted, "first completion accepted")
assertEqual(firstCompletion.reason, "accepted", "first completion accepted reason")
assertEqual(firstCompletion.alert.kind, "objective_completed", "first completion alert kind")
assertEqual(firstCompletion.alert.siteId, "ConstructionSite_A", "first completion alert site id")
assertTrue(firstCompletion.alert.sitePosition == nil, "completion alert does not expose exact tinyfolk position")
assertFalse(firstCompletion.snapshot.escapeReady, "escape still not ready after first completion")

local secondCompletion = queryApi.RecordObjectiveCompletion("Station_A", 5002, 11)
assertTrue(secondCompletion.accepted, "second completion accepted")
assertTrue(secondCompletion.snapshot.escapeReady, "escape ready once required completions reached")
assertTrue(queryApi.IsEscapeObjectiveThresholdMet(), "threshold query api reports met")

local unknownCompletion = queryApi.RecordObjectiveCompletion("Unknown_Objective_Site", 5002, 12)
assertFalse(unknownCompletion.accepted, "unknown site completion rejected")
assertEqual(unknownCompletion.reason, "site_not_found", "unknown site rejection reason")

playersList = {
	playersList[1],
	playersList[4],
}

local scaledDownSnapshot = queryApi.GetObjectiveSnapshot()
assertEqual(scaledDownSnapshot.requiredCompletions, 1, "required completions recompute when active tinyfolk changes")

workspaceService._Children["Map"] = nil
queryApi.ResetForTests()
local missingPathSnapshot = queryApi.GetObjectiveSnapshot()
assertEqual(missingPathSnapshot.totalSiteCount, 0, "missing objectives path yields empty objective snapshot")
assertEqual(missingPathSnapshot.requiredCompletions, 0, "missing objectives path yields zero required completions")
assertFalse(missingPathSnapshot.escapeReady, "missing objectives path cannot report escape ready")

print("realm_objective_service_runtime_entrypoint: all checks passed")
