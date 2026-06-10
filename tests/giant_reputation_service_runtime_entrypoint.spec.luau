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
configFolder._Children["GiantReputationConfig"] = "../../ReplicatedStorage/Shared/Config/GiantReputationConfig"
configFolder._Children["TrophyConfig"] = "../../ReplicatedStorage/Shared/Config/TrophyConfig"

local giantRealmFolder = makeNode("GiantRealm")
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

local GiantReputationConfig = require("../src/ReplicatedStorage/Shared/Config/GiantReputationConfig")
local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")

require("../src/ServerScriptService/Services/GiantReputationService.server")

local reputationApi = _G._GiantReputationService_QueryAPI
assertTrue(type(reputationApi) == "table", "reputation query api present")

reputationApi.ResetForTests()

local captureResult =
	reputationApi.RecordTrophyScore(TrophyConfig.Kinds.CaptureSuccess, "trophy-capture-5001-5101-12500", 12.5)
assertTrue(captureResult.accepted, "capture reputation recorded")
assertEqual(reputationApi.GetScore(), 15, "capture increments reputation score")
assertEqual(ownerPlayer:GetAttribute(GiantReputationConfig.StateAttributes.Score), 15, "realm owner score attribute")
assertEqual(ownerPlayer:GetAttribute(GiantReputationConfig.StateAttributes.Rank), 1, "realm owner rank attribute")

local escapeResult = reputationApi.RecordTrophyScore(
	TrophyConfig.Kinds.ContainmentEscapeFailure,
	"containment-escaped-5001-5101-20000",
	20
)
assertTrue(escapeResult.accepted, "escape failure reputation recorded")
assertEqual(reputationApi.GetScore(), 40, "escape failure increments reputation score")

local persistence = reputationApi.BuildPersistenceState()
assertEqual(#persistence.recentEvents, 2, "persistence includes reputation events")
assertEqual(persistence.recentEvents[2].trophyKind, TrophyConfig.Kinds.ContainmentEscapeFailure, "escape event kind")

reputationApi.ResetForTests()
local applied, applyReason = reputationApi.ApplyPersistenceState(persistence)
assertTrue(applied, "apply persistence accepted")
assertEqual(applyReason, nil, "apply persistence reason")
assertEqual(reputationApi.GetScore(), 40, "apply persistence restores score")

print("giant_reputation_service_runtime_entrypoint.spec.luau: all checks passed")
