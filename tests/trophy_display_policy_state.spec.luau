--!strict

local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")
local TrophyDisplayPolicyProfileState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/TrophyDisplayPolicyProfileState")
local TrophyState = require("../src/ReplicatedStorage/Shared/GiantRealm/TrophyState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local defaultPreference = TrophyDisplayPolicyProfileState.CreateDefaultPreference()
assertTrue(defaultPreference.optOutOfNameDisplay == false, "default preference allows visitor reference")

local readDefault = TrophyDisplayPolicyProfileState.GetPreference({})
assertTrue(readDefault.optOutOfNameDisplay == false, "missing profile preference defaults to allow reference")

local readStored = TrophyDisplayPolicyProfileState.GetPreference({
	trophyDisplayPreference = {
		optOutOfNameDisplay = true,
	},
})
assertTrue(readStored.optOutOfNameDisplay == true, "stored opt-out preference is read")

local update = TrophyDisplayPolicyProfileState.ApplyOptOut({}, true)
assertTrue(update.accepted, "apply update accepted")
assertTrue(update.preference.optOutOfNameDisplay == true, "apply update stores opt-out")
assertTrue(
	update.profileData[TrophyDisplayPolicyProfileState.PROFILE_KEY][TrophyDisplayPolicyProfileState.OPT_OUT_KEY] == true,
	"apply update writes profile key"
)

local revert = TrophyDisplayPolicyProfileState.ApplyOptOut(update.profileData, false)
assertTrue(revert.accepted, "revert update accepted")
assertTrue(revert.preference.optOutOfNameDisplay == false, "revert update clears opt-out")

assertEqual(
	TrophyState.ComputeTargetDisplayToken(202, true),
	TrophyConfig.AnonymousTargetDisplayToken,
	"opt-out uses anonymous display token"
)
assertEqual(
	TrophyState.ComputeTargetDisplayToken(202, false),
	TrophyState.ComputeTargetDisplayToken(202),
	"default policy keeps visitor reference token"
)

local state = TrophyState.CreateEmptyState()
local optedOutEvent = TrophyState.ApplyEvent(state, {
	operationId = "trophy-capture-opt-out-101-202-1000",
	trophyKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 10,
	custodianUserId = 101,
	targetUserId = 202,
	optOutOfNameDisplay = true,
})
assertTrue(optedOutEvent.accepted, "opt-out trophy accepted")
assertEqual(
	optedOutEvent.record.targetDisplayToken,
	TrophyConfig.AnonymousTargetDisplayToken,
	"opt-out trophy stores anonymous token"
)
assertTrue(
	string.find(optedOutEvent.record.summary, TrophyConfig.AnonymousTargetDisplayToken) ~= nil,
	"opt-out trophy summary uses anonymous token"
)
assertTrue(
	string.find(optedOutEvent.record.summary, "ref%-") == nil,
	"opt-out trophy summary omits visitor reference token"
)

print("trophy_display_policy_state.spec.luau: all checks passed")
