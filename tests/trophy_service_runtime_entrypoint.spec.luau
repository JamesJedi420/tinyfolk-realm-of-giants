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

	function node:WaitForChild(childName: string): any
		return self._Children[childName]
	end

	return node
end

local configFolder = makeNode("Config")
configFolder._Children["TrophyConfig"] = "../../ReplicatedStorage/Shared/Config/TrophyConfig"
configFolder._Children["GiantReputationConfig"] = "../../ReplicatedStorage/Shared/Config/GiantReputationConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["TrophyState"] = "../../ReplicatedStorage/Shared/GiantRealm/TrophyState"
giantRealmFolder._Children["GiantReputationState"] = "../../ReplicatedStorage/Shared/GiantRealm/GiantReputationState"

local sharedFolder = makeNode("Shared")
sharedFolder._Children["Config"] = configFolder
sharedFolder._Children["GiantRealm"] = giantRealmFolder

local replicatedStorage = makeNode("ReplicatedStorage")
replicatedStorage._Children["Shared"] = sharedFolder

local ownerPlayer = {
	UserId = 5001,
	_Attributes = {},
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
}

local playersList = { ownerPlayer }

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
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

_G._GiantBuildModeService_QueryAPI = {
	GetActiveGiantRealmOwnerUserId = function(): number
		return 5001
	end,
}

local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")
local GiantReputationConfig = require("../src/ReplicatedStorage/Shared/Config/GiantReputationConfig")

require("../src/ServerScriptService/Services/GiantReputationService.server")
require("../src/ServerScriptService/Services/TrophyService.server")

local trophyApi = _G._TrophyService_QueryAPI
assertTrue(type(trophyApi) == "table", "trophy query api present")

trophyApi.ResetForTests()

local captureResult = trophyApi.RecordCaptureSuccess(5001, 5101, 12.5)
assertTrue(captureResult.accepted, "capture trophy recorded")
assertEqual(trophyApi.GetTrophyCount(), 1, "capture increments trophy count")
assertEqual(ownerPlayer:GetAttribute(TrophyConfig.StateAttributes.Count), 1, "realm owner trophy count attribute")
assertTrue(
	string.find(ownerPlayer:GetAttribute(TrophyConfig.StateAttributes.LatestSummary), "Capture Secured") ~= nil,
	"latest summary includes capture title"
)

local containmentResult = trophyApi.RecordContainmentEnd({
	operationId = "containment-released-5001-5101-1000",
	custodianUserId = 5001,
	targetUserId = 5101,
	endedAt = 20,
	endReason = "released",
	heldSeconds = 4,
})
assertTrue(containmentResult.accepted, "containment trophy recorded")
assertEqual(trophyApi.GetTrophyCount(), 2, "containment increments trophy count")

local escapeResult = trophyApi.RecordContainmentEnd({
	operationId = "containment-escaped-5001-5101-3000",
	custodianUserId = 5001,
	targetUserId = 5101,
	endedAt = 30,
	endReason = "escaped",
	heldSeconds = 8,
})
assertTrue(escapeResult.accepted, "escape failure trophy recorded")
assertEqual(escapeResult.record.trophyKind, TrophyConfig.Kinds.ContainmentEscapeFailure, "escape failure trophy kind")
assertEqual(trophyApi.GetTrophyCount(), 3, "escape failure increments trophy count")

local reputationApi = _G._GiantReputationService_QueryAPI
assertEqual(reputationApi.GetScore(), 60, "trophies grant reputation score")
assertEqual(ownerPlayer:GetAttribute(GiantReputationConfig.StateAttributes.Score), 60, "reputation score attribute")

local persistence = trophyApi.BuildPersistenceState()
assertEqual(#persistence.trophies, 3, "persistence includes trophies")
assertTrue(
	persistence.trophies[1].targetDisplayToken:find("^ref%-") ~= nil,
	"persisted trophy uses display token not raw target id"
)
assertEqual(persistence.trophies[1].targetUserId, nil, "persisted trophy omits raw target user id")

trophyApi.ResetForTests()
local applied, applyReason = trophyApi.ApplyPersistenceState(persistence)
assertTrue(applied, "apply persistence accepted")
assertEqual(applyReason, nil, "apply persistence reason")
assertEqual(trophyApi.GetTrophyCount(), 3, "apply persistence restores trophies")

print("trophy_service_runtime_entrypoint.spec.luau: all checks passed")
