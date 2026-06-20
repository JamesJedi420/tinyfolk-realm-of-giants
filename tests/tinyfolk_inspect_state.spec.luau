--!strict

local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local TinyfolkHaulLogisticsConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkHaulLogisticsConfig")
local TinyfolkInspectConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkInspectConfig")
local TinyfolkJobSchedulingConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig")
local TinyfolkInspectState = require("../src/ReplicatedStorage/Shared/GiantRealm/TinyfolkInspectState")

local function assertTrue(value: boolean, label: string)
	if value ~= true then
		error(string.format("FAIL [%s]", label))
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s] expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local workerSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "WorkerOne",
	role = "Tinyfolk",
	specialistRole = SpecialistConfig.SpecialistRoles.Miner,
	scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
	scheduledJobStationId = "MiningStation_A",
	scoreTotal = 40,
	laborTokens = 2,
})
assertEqual(workerSnapshot.displayName, "WorkerOne", "display name")
assertEqual(workerSnapshot.roleLine, "Tinyfolk · Miner", "role line")
assertEqual(workerSnapshot.custodyLine, "Custody: Free", "free custody")
assertTrue(string.find(workerSnapshot.assignmentLine, "Mining Station", 1, true) ~= nil, "assignment station")
assertEqual(workerSnapshot.tone, TinyfolkInspectConfig.Tones.Neutral, "neutral tone")

local carriedSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "CapturedOne",
	role = "Tinyfolk",
	carriedState = "Carried",
})
assertEqual(carriedSnapshot.custodyLine, "Custody: Carried", "carried custody")
assertEqual(carriedSnapshot.tone, TinyfolkInspectConfig.Tones.Warning, "carried warning tone")

local captiveSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "CaptiveOne",
	role = "Tinyfolk",
	captureActive = true,
	captureContainmentPhase = "contained",
})
assertTrue(string.find(captiveSnapshot.custodyLine, "Captured", 1, true) ~= nil, "captured custody")
assertTrue(string.find(captiveSnapshot.moraleLine, "Captive", 1, true) ~= nil, "captive morale")

local starvingSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "StarvingOne",
	role = "Tinyfolk",
	captiveStarving = true,
})
assertTrue(string.find(starvingSnapshot.moraleLine, "starving", 1, true) ~= nil, "starving morale")
assertEqual(starvingSnapshot.tone, TinyfolkInspectConfig.Tones.Critical, "starving critical tone")

local shortfallSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "ShortfallOne",
	role = "Tinyfolk",
	captiveShortfallStreak = 3,
})
assertEqual(shortfallSnapshot.tone, TinyfolkInspectConfig.Tones.Critical, "shortfall critical tone")

local raiderSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "RaiderOne",
	role = "Tinyfolk",
	fearExposureRatio = 0.62,
	sprintStaminaRatio = 0.42,
})
assertTrue(string.find(raiderSnapshot.moraleLine, "62%", 1, true) ~= nil, "fear morale percent")
assertTrue(string.find(raiderSnapshot.fatigueLine, "42%", 1, true) ~= nil, "fatigue percent")

local haulSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "HaulerOne",
	role = "Tinyfolk",
	scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
	scheduledJobMaterial = "Wood",
	haulPhase = TinyfolkHaulLogisticsConfig.Phases.Pickup,
	haulRouteSourceId = "WorkStation_A",
})
assertTrue(string.find(haulSnapshot.assignmentLine, "Pick up Wood", 1, true) ~= nil, "haul pickup assignment")

local loyaltySnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "AnyOne",
	role = "Tinyfolk",
})
assertTrue(
	string.find(loyaltySnapshot.loyaltyLine, TinyfolkInspectConfig.UnavailableLabel, 1, true) ~= nil,
	"loyalty unavailable"
)

local dyadicLoyaltySnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "DyadicOne",
	role = "Tinyfolk",
	socialDyadicFavor = 55,
	socialDyadicControl = 60,
})
assertEqual(dyadicLoyaltySnapshot.loyaltyLine, "Loyalty: Favor 55 / Control 60", "dyadic loyalty line")

local partialDyadicSnapshot = TinyfolkInspectState.BuildSnapshot({
	displayName = "PartialOne",
	role = "Tinyfolk",
	socialDyadicFavor = 55,
})
assertTrue(
	string.find(partialDyadicSnapshot.loyaltyLine, TinyfolkInspectConfig.UnavailableLabel, 1, true) ~= nil,
	"partial dyadic loyalty unavailable"
)

local favorDominantInput = {
	role = "Tinyfolk",
	socialDyadicFavor = 60,
	socialDyadicControl = 40,
}
assertEqual(
	TinyfolkInspectState.ResolveHighlightTone(favorDominantInput),
	TinyfolkInspectConfig.Tones.Positive,
	"favor dominant highlight positive"
)
assertEqual(
	TinyfolkInspectState.ResolveTone(favorDominantInput),
	TinyfolkInspectConfig.Tones.Neutral,
	"favor dominant panel tone still neutral"
)

local controlDominantInput = {
	role = "Tinyfolk",
	socialDyadicFavor = 40,
	socialDyadicControl = 60,
}
assertEqual(
	TinyfolkInspectState.ResolveHighlightTone(controlDominantInput),
	TinyfolkInspectConfig.Tones.Warning,
	"control dominant highlight warning"
)

local balancedDyadicInput = {
	role = "Tinyfolk",
	socialDyadicFavor = 50,
	socialDyadicControl = 52,
}
assertEqual(
	TinyfolkInspectState.ResolveHighlightTone(balancedDyadicInput),
	TinyfolkInspectConfig.Tones.Neutral,
	"balanced dyadic highlight neutral"
)

local custodyOverridesDyadicInput = {
	role = "Tinyfolk",
	captureActive = true,
	socialDyadicFavor = 80,
	socialDyadicControl = 20,
}
assertEqual(
	TinyfolkInspectState.ResolveHighlightTone(custodyOverridesDyadicInput),
	TinyfolkInspectConfig.Tones.Warning,
	"captured custody overrides favor highlight"
)

local starvingOverridesDyadicInput = {
	role = "Tinyfolk",
	captiveStarving = true,
	socialDyadicFavor = 80,
	socialDyadicControl = 20,
}
assertEqual(
	TinyfolkInspectState.ResolveHighlightTone(starvingOverridesDyadicInput),
	TinyfolkInspectConfig.Tones.Critical,
	"starving custody overrides favor highlight"
)

local missingDyadicInput = {
	role = "Tinyfolk",
}
assertEqual(
	TinyfolkInspectState.ResolveHighlightTone(missingDyadicInput),
	TinyfolkInspectConfig.Tones.Neutral,
	"missing dyadic highlight falls back to custody tone"
)

print("tinyfolk_inspect_state.spec.luau: all checks passed")
