--!strict

local GiantReputationConfig = require("../src/ReplicatedStorage/Shared/Config/GiantReputationConfig")
local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")
local GiantReputationState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantReputationState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local state = GiantReputationState.CreateEmptyState()
assertEqual(state.score, 0, "empty score")
assertEqual(state.rank, 1, "empty rank")

local capture = GiantReputationState.ApplyScoreEvent(state, {
	operationId = "trophy-capture-101-202-1000",
	trophyKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 10,
})
assertTrue(capture.accepted, "capture score accepted")
assertEqual(capture.state.score, 15, "capture score total")
assertEqual(capture.state.rank, 1, "capture stays rank 1")

local duplicate = GiantReputationState.ApplyScoreEvent(capture.state, {
	operationId = "trophy-capture-101-202-1000",
	trophyKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 10,
})
assertEqual(duplicate.reason, "duplicate", "duplicate operation rejected")

local escapeFailure = GiantReputationState.ApplyScoreEvent(capture.state, {
	operationId = "containment-escaped-101-202-5000",
	trophyKind = TrophyConfig.Kinds.ContainmentEscapeFailure,
	awardedAt = 20,
})
assertTrue(escapeFailure.accepted, "escape failure score accepted")
assertEqual(escapeFailure.state.score, 40, "escape failure score total")

local rankUp = GiantReputationState.ApplyScoreEvent(escapeFailure.state, {
	operationId = "containment-released-101-303-6000",
	trophyKind = TrophyConfig.Kinds.ContainmentHeld,
	awardedAt = 30,
})
assertTrue(rankUp.accepted, "rank up score accepted")
assertEqual(rankUp.state.score, 60, "rank up score total")
assertEqual(rankUp.state.rank, 2, "rank up to 2")
assertTrue(rankUp.rankedUp, "ranked up flag")

assertEqual(GiantReputationState.ResolveRankFromScore(49), 1, "rank 1 threshold")
assertEqual(GiantReputationState.ResolveRankFromScore(50), 2, "rank 2 threshold")
assertEqual(
	GiantReputationState.ResolveScoreToNextRank(60, 2),
	GiantReputationConfig.RankThresholds[3] - 60,
	"score to next rank"
)
assertEqual(
	GiantReputationState.ResolveScoreToNextRank(
		GiantReputationConfig.RankThresholds[#GiantReputationConfig.RankThresholds],
		GiantReputationState.GetMaxRank()
	),
	0,
	"max rank score to next"
)
assertEqual(GiantReputationState.ResolveRankTitle(2), "Collector", "rank 2 title")

local serialized = GiantReputationState.SerializePersistenceState(rankUp.state)
local restored = GiantReputationState.ApplyPersistenceState(serialized)
assertTrue(restored.accepted, "persistence round trip accepted")
assertEqual(restored.state.score, 60, "persistence score")
assertEqual(restored.state.rank, 2, "persistence rank")
assertEqual(#restored.state.recentEvents, 3, "persistence recent events")

print("giant_reputation_state.spec.luau: all checks passed")
