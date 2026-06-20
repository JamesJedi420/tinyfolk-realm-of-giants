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

print("tinyfolk_inspect_state.spec.luau: all checks passed")
