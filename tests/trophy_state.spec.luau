--!strict

local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")
local TrophyState = require("../src/ReplicatedStorage/Shared/GiantRealm/TrophyState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local state = TrophyState.CreateEmptyState()

local capture = TrophyState.ApplyEvent(state, {
	operationId = "trophy-capture-101-202-1000",
	trophyKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 10,
	custodianUserId = 101,
	targetUserId = 202,
})
assertTrue(capture.accepted, "capture trophy accepted")
assertEqual(#capture.state.trophies, 1, "capture trophy count")
assertEqual(capture.record.targetDisplayToken, TrophyState.ComputeTargetDisplayToken(202), "display token")

local duplicate = TrophyState.ApplyEvent(capture.state, {
	operationId = "trophy-capture-101-202-1000",
	trophyKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 10,
	custodianUserId = 101,
	targetUserId = 202,
})
assertEqual(duplicate.reason, "duplicate", "duplicate operation rejected")

assertEqual(
	TrophyState.ResolveKindFromContainmentEnd("starvation"),
	TrophyConfig.Kinds.ContainmentStarvation,
	"starvation kind"
)
assertEqual(
	TrophyState.ResolveKindFromContainmentEnd("escaped"),
	TrophyConfig.Kinds.ContainmentEscapeFailure,
	"escaped kind"
)
assertEqual(TrophyState.ResolveKindFromContainmentEnd("released"), TrophyConfig.Kinds.ContainmentHeld, "released kind")
assertEqual(TrophyState.ResolveKindFromContainmentEnd("rescued"), nil, "rescued not trophy eligible")

local serialized = TrophyState.SerializePersistenceState(capture.state)
local restored = TrophyState.ApplyPersistenceState(serialized)
assertTrue(restored.accepted, "persistence round trip accepted")
assertEqual(#restored.state.trophies, 1, "persistence round trip count")

print("trophy_state.spec.luau: all checks passed")
