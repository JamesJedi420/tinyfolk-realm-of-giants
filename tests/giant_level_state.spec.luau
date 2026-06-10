--!strict

local GiantLevelConfig = require("../src/ReplicatedStorage/Shared/Config/GiantLevelConfig")
local GiantLevelState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantLevelState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local state = GiantLevelState.CreateEmptyState()
assertEqual(state.xp, 0, "empty xp")
assertEqual(state.level, 1, "empty level")

local capture = GiantLevelState.ApplyXpEvent(state, {
	operationId = "trophy-capture-101-202-1000",
	eventKind = GiantLevelConfig.EventKinds.CaptureSuccess,
	awardedAt = 10,
})
assertTrue(capture.accepted, "capture xp accepted")
assertEqual(capture.state.xp, 25, "capture xp total")
assertEqual(capture.state.level, 1, "capture stays level 1")
assertEqual(capture.leveledUp, false, "capture no level up")

local duplicate = GiantLevelState.ApplyXpEvent(capture.state, {
	operationId = "trophy-capture-101-202-1000",
	eventKind = GiantLevelConfig.EventKinds.CaptureSuccess,
	awardedAt = 10,
})
assertEqual(duplicate.reason, "duplicate", "duplicate operation rejected")

local containment = GiantLevelState.ApplyXpEvent(capture.state, {
	operationId = "containment-released-101-202-5000",
	eventKind = GiantLevelConfig.EventKinds.ContainmentHeld,
	awardedAt = 20,
})
assertTrue(containment.accepted, "containment xp accepted")
assertEqual(containment.state.xp, 65, "containment xp total")

local upgrade = GiantLevelState.ApplyXpEvent(containment.state, {
	operationId = "worksite-upgrade:MiningStation_A:2:30.000000",
	eventKind = GiantLevelConfig.EventKinds.WorksiteUpgrade,
	awardedAt = 30,
})
assertTrue(upgrade.accepted, "worksite upgrade xp accepted")
assertEqual(upgrade.state.xp, 80, "worksite upgrade xp total")

local levelUp = GiantLevelState.ApplyXpEvent(upgrade.state, {
	operationId = "containment-timeout-101-303-6000",
	eventKind = GiantLevelConfig.EventKinds.ContainmentHeld,
	awardedAt = 40,
})
assertTrue(levelUp.accepted, "level up xp accepted")
assertEqual(levelUp.state.xp, 120, "level up xp total")
assertEqual(levelUp.state.level, 2, "level up to 2")
assertTrue(levelUp.leveledUp, "leveled up flag")

assertEqual(GiantLevelState.ResolveLevelFromXp(99), 1, "level 1 threshold")
assertEqual(GiantLevelState.ResolveLevelFromXp(100), 2, "level 2 threshold")
assertEqual(GiantLevelState.ResolveXpToNextLevel(120, 2), 130, "xp to next level")
assertEqual(
	GiantLevelState.ResolveXpToNextLevel(
		GiantLevelConfig.LevelThresholds[#GiantLevelConfig.LevelThresholds],
		GiantLevelState.GetMaxLevel()
	),
	0,
	"max level xp to next"
)

assertEqual(
	GiantLevelState.ResolveEventKindFromContainmentEnd("released"),
	GiantLevelConfig.EventKinds.ContainmentHeld,
	"released maps to containment held"
)
assertEqual(GiantLevelState.ResolveEventKindFromContainmentEnd("starvation"), nil, "starvation not xp eligible")

local serialized = GiantLevelState.SerializePersistenceState(levelUp.state)
local restored = GiantLevelState.ApplyPersistenceState(serialized)
assertTrue(restored.accepted, "persistence round trip accepted")
assertEqual(restored.state.xp, 120, "persistence xp")
assertEqual(restored.state.level, 2, "persistence level")
assertEqual(#restored.state.recentEvents, 4, "persistence recent events")
assertEqual(restored.needsEntitlementReconcile, false, "resolved unlock ids persisted")

local unlockResult = GiantLevelState.ResolveLevelUnlocks(levelUp.state, 2, 2)
assertTrue(unlockResult.accepted, "level 2 unlock accepted")
assertEqual(#unlockResult.newlyResolved, 1, "level 2 unlock count")
assertEqual(unlockResult.newlyResolved[1].unlockId, "giant_level_2_steward", "level 2 unlock id")

local duplicateUnlock = GiantLevelState.ResolveLevelUnlocks(unlockResult.state, 2, 2)
assertEqual(duplicateUnlock.reason, "no_new_unlocks", "duplicate unlock resolution skipped")
assertEqual(#duplicateUnlock.newlyResolved, 0, "duplicate unlock resolution empty")

local modifiers = GiantLevelState.ResolveModifierSnapshot(unlockResult.state)
assertEqual(modifiers.xpAwardMultiplier, 1.05, "level 2 xp award multiplier")
assertEqual(modifiers.containmentRewardMultiplier, 1, "level 2 containment multiplier baseline")

local boostedCapture = GiantLevelState.ApplyXpEvent(unlockResult.state, {
	operationId = "trophy-capture-101-303-7000",
	eventKind = GiantLevelConfig.EventKinds.CaptureSuccess,
	awardedAt = 50,
})
assertTrue(boostedCapture.accepted, "boosted capture accepted")
assertEqual(boostedCapture.state.xp, 146, "boosted capture xp award")

local legacyRestore = GiantLevelState.ApplyPersistenceState({
	xp = 120,
	level = 2,
	recentEvents = serialized.recentEvents,
})
assertTrue(legacyRestore.accepted, "legacy persistence accepted")
assertTrue(legacyRestore.needsEntitlementReconcile, "legacy persistence needs reconcile")
local reconciled = GiantLevelState.ReconcileEntitledUnlocks(legacyRestore.state)
assertEqual(#reconciled.newlyResolved, 1, "legacy reconcile grants level 2 unlock")

print("giant_level_state.spec.luau: all checks passed")
