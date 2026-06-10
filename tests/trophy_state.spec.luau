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
assertEqual(
	TrophyState.ResolveKindFromContainmentEnd("released"),
	TrophyConfig.Kinds.NegotiatedRelease,
	"released kind"
)
assertEqual(TrophyState.ResolveKindFromContainmentEnd("timeout"), TrophyConfig.Kinds.ContainmentHeld, "timeout kind")
assertEqual(TrophyState.ResolveKindFromContainmentEnd("rescued"), nil, "rescued not trophy eligible")

local escapeFailure = TrophyState.ApplyEvent(capture.state, {
	operationId = "containment-escaped-101-202-5000",
	trophyKind = TrophyConfig.Kinds.ContainmentEscapeFailure,
	awardedAt = 20,
	custodianUserId = 101,
	targetUserId = 202,
	endReason = "escaped",
	heldSeconds = 6,
})
assertTrue(escapeFailure.accepted, "escape failure trophy accepted")
assertEqual(escapeFailure.record.trophyKind, TrophyConfig.Kinds.ContainmentEscapeFailure, "escape failure kind")
assertTrue(
	string.find(escapeFailure.record.summary, "Escape Denied") ~= nil,
	"escape failure summary includes display title"
)

local raidDefense = TrophyState.ApplyEvent(escapeFailure.state, {
	operationId = "trophy-raid-defense-trap-a-202-9000",
	trophyKind = TrophyConfig.Kinds.RaidDefenseWin,
	awardedAt = 25,
	custodianUserId = 101,
	targetUserId = 202,
})
assertTrue(raidDefense.accepted, "raid defense trophy accepted")
assertTrue(string.find(raidDefense.record.summary, "Intruder Snared") ~= nil, "raid defense summary title")

local negotiatedRelease = TrophyState.ApplyEvent(raidDefense.state, {
	operationId = "containment-released-101-303-10000",
	trophyKind = TrophyConfig.Kinds.NegotiatedRelease,
	awardedAt = 30,
	custodianUserId = 101,
	targetUserId = 303,
	endReason = "released",
	heldSeconds = 3,
})
assertTrue(negotiatedRelease.accepted, "negotiated release trophy accepted")
assertTrue(
	string.find(negotiatedRelease.record.summary, "Negotiated Release") ~= nil,
	"negotiated release summary title"
)

local serialized = TrophyState.SerializePersistenceState(negotiatedRelease.state)
local restored = TrophyState.ApplyPersistenceState(serialized)
assertTrue(restored.accepted, "persistence round trip accepted")
assertEqual(#restored.state.trophies, 4, "persistence round trip count")

print("trophy_state.spec.luau: all checks passed")
