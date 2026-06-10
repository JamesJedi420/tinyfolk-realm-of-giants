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
configFolder._Children["GiantLevelConfig"] = "../../ReplicatedStorage/Shared/Config/GiantLevelConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["GiantLevelState"] = "../../ReplicatedStorage/Shared/GiantRealm/GiantLevelState"

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

local GiantLevelConfig = require("../src/ReplicatedStorage/Shared/Config/GiantLevelConfig")

require("../src/ServerScriptService/Services/GiantLevelService.server")

local levelApi = _G._GiantLevelService_QueryAPI
assertTrue(type(levelApi) == "table", "giant level query api present")

levelApi.ResetForTests()

local captureResult = levelApi.RecordCaptureSuccess(5001, 5101, 12.5)
assertTrue(captureResult.accepted, "capture xp recorded")
assertEqual(levelApi.GetXp(), 25, "capture increments xp")
assertEqual(levelApi.GetLevel(), 1, "capture stays level 1")
assertEqual(ownerPlayer:GetAttribute(GiantLevelConfig.StateAttributes.Xp), 25, "realm owner xp attribute")
assertEqual(ownerPlayer:GetAttribute(GiantLevelConfig.StateAttributes.Level), 1, "realm owner level attribute")
assertEqual(ownerPlayer:GetAttribute(GiantLevelConfig.StateAttributes.XpToNextLevel), 75, "realm owner xp to next")

local containmentResult = levelApi.RecordContainmentEnd({
	operationId = "containment-released-5001-5101-1000",
	custodianUserId = 5001,
	targetUserId = 5101,
	endedAt = 20,
	endReason = "released",
	heldSeconds = 4,
})
assertTrue(containmentResult.accepted, "containment xp recorded")
assertEqual(levelApi.GetXp(), 65, "containment increments xp")

local skippedContainment = levelApi.RecordContainmentEnd({
	operationId = "containment-starvation-5001-5102-1000",
	custodianUserId = 5001,
	targetUserId = 5102,
	endedAt = 25,
	endReason = "starvation",
})
assertEqual(skippedContainment.reason, "end_reason_not_xp_eligible", "starvation not xp eligible")

local upgradeResult = levelApi.RecordWorksiteUpgrade("worksite-upgrade:MiningStation_A:2:30.000000", 30)
assertTrue(upgradeResult.accepted, "worksite upgrade xp recorded")
assertEqual(levelApi.GetXp(), 80, "worksite upgrade increments xp")

local levelUpResult = levelApi.GrantXpEvent({
	operationId = "containment-timeout-5001-5103-9000",
	eventKind = GiantLevelConfig.EventKinds.ContainmentHeld,
	awardedAt = 40,
})
assertTrue(levelUpResult.accepted, "level up xp accepted")
assertTrue(levelUpResult.leveledUp, "level up flag set")
assertEqual(levelApi.GetLevel(), 2, "level up to 2")
assertEqual(ownerPlayer:GetAttribute(GiantLevelConfig.StateAttributes.ResolvedUnlockCount), 1, "level 2 unlock count")
assertEqual(ownerPlayer:GetAttribute(GiantLevelConfig.StateAttributes.XpAwardMultiplier), 1.05, "level 2 xp multiplier")
assertEqual(ownerPlayer:GetAttribute(GiantLevelConfig.StateAttributes.LevelUpSignal), 1, "level up signal emitted")

local modifierSnapshot = levelApi.GetModifierSnapshot()
assertEqual(modifierSnapshot.xpAwardMultiplier, 1.05, "modifier snapshot xp multiplier")
assertEqual(modifierSnapshot.resolvedUnlockIds[1], "giant_level_2_steward", "modifier snapshot unlock id")

local persistence = levelApi.BuildPersistenceState()
assertEqual(persistence.xp, 120, "persistence includes xp")
assertEqual(#persistence.recentEvents, 4, "persistence includes recent events")
assertEqual(persistence.resolvedUnlockIds[1], "giant_level_2_steward", "persistence includes resolved unlock ids")

levelApi.ResetForTests()
local applied, applyReason = levelApi.ApplyPersistenceState(persistence)
assertTrue(applied, "apply persistence accepted")
assertEqual(applyReason, nil, "apply persistence reason")
assertEqual(levelApi.GetXp(), 120, "apply persistence restores xp")
assertEqual(levelApi.GetLevel(), 2, "apply persistence restores level")
assertEqual(levelApi.GetModifierSnapshot().xpAwardMultiplier, 1.05, "apply persistence restores modifiers")
assertEqual(
	ownerPlayer:GetAttribute(GiantLevelConfig.StateAttributes.LevelUpSignal),
	nil,
	"persistence restore skips level up signal"
)

print("giant_level_service_runtime_entrypoint.spec.luau: all checks passed")
