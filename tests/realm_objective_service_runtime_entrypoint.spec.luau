--!nocheck
-- selene: allow(global_usage)
--!nolint BuiltinGlobalWrite

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
local configFolder = makeNode("Config", "Folder")
local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(
	configFolder,
	"EmergencyReinforcementConfig",
	"../../ReplicatedStorage/Shared/Config/EmergencyReinforcementConfig"
)
addChild(giantRealmFolder, "RealmObjectiveState", "../../ReplicatedStorage/Shared/GiantRealm/RealmObjectiveState")
addChild(sharedFolder, "Config", configFolder)
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
assertTrue(type(queryApi.GetEmergencyTokenSnapshot) == "function", "realm objective query exposes token snapshot api")
assertTrue(type(queryApi.RequestConsumeEmergencyToken) == "function", "realm objective query exposes token consume api")

local initialSnapshot = queryApi.GetObjectiveSnapshot()
assertEqual(initialSnapshot.totalSiteCount, 5, "startup discovers expected objective site count")
assertEqual(initialSnapshot.completedCount, 0, "startup completed count is zero")
assertEqual(initialSnapshot.unresolvedCount, 5, "startup unresolved count matches total")
assertEqual(initialSnapshot.requiredCompletions, 2, "required completions scale at three tinyfolk")
assertFalse(initialSnapshot.escapeReady, "escape not ready at startup")

local routeMetadataWithoutEscapeService = queryApi.GetObjectiveSafeRouteMetadata()
assertEqual(#routeMetadataWithoutEscapeService, 0, "objective route metadata empty when escape query unavailable")

local invalidTokenObjective = queryApi.GetEmergencyTokenSnapshot("WrongObjective", 0)
assertFalse(invalidTokenObjective.accepted, "token snapshot rejects wrong objective id")
assertEqual(invalidTokenObjective.reason, "invalid_objective", "token snapshot wrong objective reason")

local invalidTokenRequester = queryApi.RequestConsumeEmergencyToken(0, "CallCenter_A", 100)
assertFalse(invalidTokenRequester.accepted, "token consume rejects invalid requester id")
assertEqual(invalidTokenRequester.reason, "requester_user_id_invalid", "token consume invalid requester reason")

local invalidTokenConsumeObjective = queryApi.RequestConsumeEmergencyToken(5001, "WrongObjective", 100)
assertFalse(invalidTokenConsumeObjective.accepted, "token consume rejects wrong objective id")
assertEqual(invalidTokenConsumeObjective.reason, "invalid_objective", "token consume wrong objective reason")

local initialTokenSnapshot = queryApi.GetEmergencyTokenSnapshot("CallCenter_A", 100)
assertTrue(initialTokenSnapshot.accepted, "token snapshot accepts call-center objective")
assertEqual(initialTokenSnapshot.reason, "accepted", "token snapshot accepted reason")
assertEqual(initialTokenSnapshot.tokenState.remainingTokens, 1, "token snapshot starts with one token")

local consumedToken = queryApi.RequestConsumeEmergencyToken(5001, "CallCenter_A", 100)
assertTrue(consumedToken.accepted, "token consume accepted for valid requester/objective")
assertEqual(consumedToken.reason, "accepted", "token consume accepted reason")
assertEqual(consumedToken.tokenState.remainingTokens, 0, "token consume decrements remaining tokens")
assertEqual(consumedToken.tokenState.lastConsumedByUserId, 5001, "token consume records requester")

local exhaustedTokenSnapshot = queryApi.GetEmergencyTokenSnapshot("CallCenter_A", 101)
assertFalse(exhaustedTokenSnapshot.accepted, "token snapshot rejects exhausted token")
assertEqual(exhaustedTokenSnapshot.reason, "token_unavailable", "token snapshot exhausted reason")

local exhaustedTokenConsume = queryApi.RequestConsumeEmergencyToken(5001, "CallCenter_A", 101)
assertFalse(exhaustedTokenConsume.accepted, "token consume rejects exhausted token")
assertEqual(exhaustedTokenConsume.reason, "token_unavailable", "token consume exhausted reason")

_G._EscapeService_QueryAPI = {
	GetObjectiveSafeRouteMetadata = function(routeId: string?): any
		if routeId == "EscapeRoute_A" then
			return {
				routeId = "EscapeRoute_A",
				tinyfolkOnly = true,
				isEnabled = true,
				blockState = "Idle",
				finalExitPhase = "Open",
			}
		end
		return {
			{
				routeId = "EscapeRoute_A",
				tinyfolkOnly = true,
				isEnabled = true,
				blockState = "Idle",
				finalExitPhase = "Open",
			},
		}
	end,
}

local routeMetadata = queryApi.GetObjectiveSafeRouteMetadata("EscapeRoute_A")
assertEqual(routeMetadata.routeId, "EscapeRoute_A", "objective query returns route id")
assertEqual(routeMetadata.tinyfolkOnly, true, "objective query returns Tinyfolk-only route flag")
assertTrue(routeMetadata.position == nil, "objective route metadata omits exact Tinyfolk position")
assertTrue(routeMetadata.playerUserId == nil, "objective route metadata omits actor identity")

_G._EscapeService_QueryAPI = {
	GetObjectiveSafeRouteMetadata = function(_routeId: string?): any
		error("route metadata unavailable")
		return nil
	end,
}
local faultedRouteMetadata = queryApi.GetObjectiveSafeRouteMetadata("EscapeRoute_A")
assertTrue(faultedRouteMetadata == nil, "objective query handles faulted route metadata lookup")
local faultedAllRouteMetadata = queryApi.GetObjectiveSafeRouteMetadata()
assertEqual(#faultedAllRouteMetadata, 0, "objective query handles faulted all-route metadata lookup")

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

local beganProgress = queryApi.BeginObjectiveProgress("ConstructionSite_B", 5003, 12)
assertTrue(beganProgress.accepted, "runtime begin objective progress accepted")
assertEqual(
	beganProgress.snapshot.sitesById.ConstructionSite_B.objectiveState,
	"progressing",
	"runtime begin sets progressing state"
)

local malformedBegin = queryApi.BeginObjectiveProgress(nil :: any, 5003, 12)
assertFalse(malformedBegin.accepted, "runtime malformed objective id rejected")
assertEqual(malformedBegin.reason, "site_id_invalid", "runtime malformed objective id reason")

local appliedProgress = queryApi.ApplyObjectiveProgress("ConstructionSite_B", 50, 5003, 13)
assertTrue(appliedProgress.accepted, "runtime apply objective progress accepted")
assertEqual(appliedProgress.snapshot.sitesById.ConstructionSite_B.progress, 50, "runtime progress amount stored")

local canceledProgress = queryApi.CancelObjectiveProgress("ConstructionSite_B", 14)
assertTrue(canceledProgress.accepted, "runtime cancel objective progress accepted")
assertEqual(
	canceledProgress.snapshot.sitesById.ConstructionSite_B.objectiveState,
	"contested",
	"runtime cancel preserves contested progress"
)

local disruptedProgress = queryApi.DisruptObjectiveProgress("ConstructionSite_B", 5101, 15, 3)
assertTrue(disruptedProgress.accepted, "runtime disrupt objective progress accepted")
assertEqual(
	disruptedProgress.snapshot.sitesById.ConstructionSite_B.objectiveState,
	"regressing",
	"runtime disrupt starts regression"
)
assertEqual(
	disruptedProgress.snapshot.sitesById.ConstructionSite_B.regressionEventsUsed,
	1,
	"runtime disrupt increments regression count"
)

local tickedRegression = queryApi.TickObjectiveRegression("ConstructionSite_B", 30)
assertTrue(tickedRegression.accepted, "runtime tick objective regression accepted")
assertEqual(
	tickedRegression.snapshot.sitesById.ConstructionSite_B.objectiveState,
	"contested",
	"runtime regression tick stabilizes objective"
)

local blockedObjective = queryApi.BlockObjective("Shrine_A", 5101, 31, 2)
assertTrue(blockedObjective.accepted, "runtime block objective accepted")
assertEqual(blockedObjective.snapshot.sitesById.Shrine_A.objectiveState, "blocked", "runtime block state")

local blockedBegin = queryApi.BeginObjectiveProgress("Shrine_A", 5003, 32)
assertFalse(blockedBegin.accepted, "runtime blocked objective rejects begin")
assertEqual(blockedBegin.reason, "blocked", "runtime blocked begin reason")

local expiredBlockTick = queryApi.TickObjectiveRegression("Shrine_A", 34)
assertEqual(expiredBlockTick.snapshot.sitesById.Shrine_A.objectiveState, "idle", "runtime block expires")

local ruleLocked = queryApi.SetObjectiveRuleLocked("Shrine_A", true, 35)
assertTrue(ruleLocked.accepted, "runtime rule lock accepted")
local lockedBegin = queryApi.BeginObjectiveProgress("Shrine_A", 5003, 36)
assertFalse(lockedBegin.accepted, "runtime rule-locked objective rejects begin")
assertEqual(lockedBegin.reason, "rule_locked", "runtime rule-locked begin reason")
local unlocked = queryApi.UnlockObjective("Shrine_A", 37)
assertTrue(unlocked.accepted, "runtime unlock accepted")

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
local resetTokenSnapshot = queryApi.GetEmergencyTokenSnapshot("CallCenter_A", 200)
assertTrue(resetTokenSnapshot.accepted, "reset restores token availability")
assertEqual(resetTokenSnapshot.tokenState.remainingTokens, 1, "reset restores remaining token count")

local missingPathSnapshot = queryApi.GetObjectiveSnapshot()
assertEqual(missingPathSnapshot.totalSiteCount, 0, "missing objectives path yields empty objective snapshot")
assertEqual(missingPathSnapshot.requiredCompletions, 0, "missing objectives path yields zero required completions")
assertFalse(missingPathSnapshot.escapeReady, "missing objectives path cannot report escape ready")

print("realm_objective_service_runtime_entrypoint: all checks passed")
