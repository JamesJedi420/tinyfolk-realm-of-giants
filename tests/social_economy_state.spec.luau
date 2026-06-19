--!strict

local SocialEconomyConfig = require("../src/ReplicatedStorage/Shared/Config/SocialEconomyConfig")
local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")
local SocialEconomyState = require("../src/ReplicatedStorage/Shared/GiantRealm/SocialEconomyState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local state = SocialEconomyState.CreateEmptyState()
assertEqual(state.favor, SocialEconomyConfig.DefaultFavor, "empty favor")
assertEqual(state.control, SocialEconomyConfig.DefaultControl, "empty control")

local capture = SocialEconomyState.ApplySocialEvent(state, {
	operationId = "trophy-capture-101-202-1000",
	eventKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 10,
})
assertTrue(capture.accepted, "capture social event accepted")
assertEqual(capture.state.favor, 50, "capture leaves favor unchanged")
assertEqual(capture.state.control, 55, "capture increases control")

local duplicate = SocialEconomyState.ApplySocialEvent(capture.state, {
	operationId = "trophy-capture-101-202-1000",
	eventKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 10,
})
assertEqual(duplicate.reason, "duplicate", "duplicate operation rejected")

local release = SocialEconomyState.ApplySocialEvent(capture.state, {
	operationId = "containment-released-101-202-5000",
	eventKind = TrophyConfig.Kinds.NegotiatedRelease,
	awardedAt = 20,
})
assertTrue(release.accepted, "negotiated release accepted")
assertEqual(release.state.favor, 55, "negotiated release increases favor")
assertEqual(release.state.control, 55, "negotiated release leaves control unchanged")

local escapeFailure = SocialEconomyState.ApplySocialEvent(release.state, {
	operationId = "containment-escaped-101-202-6000",
	eventKind = TrophyConfig.Kinds.ContainmentEscapeFailure,
	awardedAt = 30,
})
assertTrue(escapeFailure.accepted, "escape failure accepted")
assertEqual(escapeFailure.state.control, 58, "escape failure increases control")

local loyaltyAlias = SocialEconomyState.ApplySocialEvent(SocialEconomyState.CreateEmptyState(), {
	operationId = "loyalty-grant-1",
	eventKind = SocialEconomyConfig.EventKinds.LoyaltyGrant,
	awardedAt = 5,
})
assertTrue(loyaltyAlias.accepted, "loyalty alias accepted")
assertEqual(loyaltyAlias.state.favor, 55, "loyalty alias increases favor")

local fearAlias = SocialEconomyState.ApplySocialEvent(SocialEconomyState.CreateEmptyState(), {
	operationId = "fear-grant-1",
	eventKind = SocialEconomyConfig.EventKinds.FearGrant,
	awardedAt = 5,
})
assertTrue(fearAlias.accepted, "fear alias accepted")
assertEqual(fearAlias.state.control, 55, "fear alias increases control")

local clamped = SocialEconomyState.ApplySocialEvent({
	favor = 98,
	control = 98,
	operationIds = {},
	recentEvents = {},
}, {
	operationId = "clamp-1",
	eventKind = TrophyConfig.Kinds.CaptureSuccess,
	awardedAt = 1,
})
assertTrue(clamped.accepted, "clamp accepted")
assertEqual(clamped.state.control, 100, "control clamps at max")

local effect = SocialEconomyState.ResolveEffectSnapshot({
	favor = 80,
	control = 40,
	operationIds = {},
	recentEvents = {},
})
assertEqual(effect.dominantAxis, SocialEconomyConfig.DominantAxes.Favor, "favor dominant axis")
assertTrue(effect.favorComplianceBonus > 1, "favor compliance bonus above baseline")
assertTrue(effect.controlIntimidationBonus > 1, "control intimidation bonus above baseline")

local balancedEffect = SocialEconomyState.ResolveEffectSnapshot({
	favor = 50,
	control = 52,
	operationIds = {},
	recentEvents = {},
})
assertEqual(balancedEffect.dominantAxis, SocialEconomyConfig.DominantAxes.Balanced, "balanced dominant axis")

local persisted = SocialEconomyState.SerializePersistenceState(escapeFailure.state)
assertEqual(persisted.favor, 55, "serialized favor")
assertEqual(persisted.control, 58, "serialized control")
assertEqual(#persisted.recentEvents, 3, "serialized recent event count")
assertEqual(persisted.recentEvents[1].operationId, "trophy-capture-101-202-1000", "serialized events sorted by awardedAt")

local applied = SocialEconomyState.ApplyPersistenceState(persisted)
assertTrue(applied.accepted, "apply persistence accepted")
assertEqual(applied.state.favor, 55, "applied favor")
assertEqual(applied.state.control, 58, "applied control")
assertTrue(applied.state.operationIds["trophy-capture-101-202-1000"] == true, "applied operation id rebuilt")

local duplicatePersisted = {
	favor = 55,
	control = 58,
	recentEvents = {
		persisted.recentEvents[1],
		persisted.recentEvents[1],
	},
}
local duplicateApplied = SocialEconomyState.ApplyPersistenceState(duplicatePersisted)
assertEqual(duplicateApplied.reason, "social_economy_operation_id_duplicate index=2", "duplicate persisted operation rejected")

local cleared = SocialEconomyState.ApplyPersistenceState(nil)
assertTrue(cleared.accepted, "clear persistence accepted")
assertEqual(cleared.state.favor, SocialEconomyConfig.DefaultFavor, "cleared favor default")

print("social_economy_state.spec.luau: all checks passed")
