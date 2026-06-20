--!strict

local PenRationingConfig = require("../src/ReplicatedStorage/Shared/Config/PenRationingConfig")
local VillageStatusHudConfig = require("../src/ReplicatedStorage/Shared/Config/VillageStatusHudConfig")
local VillageStatusState = require("../src/ReplicatedStorage/Shared/GiantRealm/VillageStatusState")

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

local calmSnapshot = VillageStatusState.BuildSnapshot({
	activeRaiderCount = 0,
	workerCount = 4,
	activeCaptiveCount = 1,
	foodStored = 120,
	foodInTransit = 8,
	morale = 80,
	lastFoodShortfall = false,
	consecutiveShortfallTicks = 0,
	activeJobCount = 2,
})
assertEqual(calmSnapshot.escapePressure, VillageStatusHudConfig.EscapePressure.Calm, "calm escape pressure")
assertEqual(calmSnapshot.tone, VillageStatusHudConfig.Tones.Neutral, "calm overall tone")

local elevatedSnapshot = VillageStatusState.BuildSnapshot({
	activeRaiderCount = 2,
	workerCount = 3,
	activeCaptiveCount = 1,
	foodStored = 120,
	morale = 80,
	lastFoodShortfall = false,
	consecutiveShortfallTicks = 0,
})
assertEqual(elevatedSnapshot.escapePressure, VillageStatusHudConfig.EscapePressure.Elevated, "raider warning elevated")
assertTrue(elevatedSnapshot.tone == VillageStatusHudConfig.Tones.Warning, "raider warning tone")

local criticalSnapshot = VillageStatusState.BuildSnapshot({
	activeRaiderCount = 4,
	workerCount = 2,
	activeCaptiveCount = 0,
	foodStored = 120,
	morale = PenRationingConfig.MoraleDefault,
})
assertEqual(criticalSnapshot.escapePressure, VillageStatusHudConfig.EscapePressure.Critical, "raider critical")
assertEqual(criticalSnapshot.tone, VillageStatusHudConfig.Tones.Critical, "raider critical tone")

local foodWarningSnapshot = VillageStatusState.BuildSnapshot({
	foodStored = 25,
	morale = PenRationingConfig.MoraleDefault,
})
assertTrue(foodWarningSnapshot.tone == VillageStatusHudConfig.Tones.Warning, "low food warning tone")

local moraleCriticalSnapshot = VillageStatusState.BuildSnapshot({
	activeRaiderCount = 1,
	foodStored = 120,
	morale = 0,
})
assertEqual(
	moraleCriticalSnapshot.escapePressure,
	VillageStatusHudConfig.EscapePressure.Critical,
	"depleted morale with raider critical escape"
)

local shortfallSnapshot = VillageStatusState.BuildSnapshot({
	activeCaptiveCount = 2,
	foodStored = 120,
	morale = 40,
	lastFoodShortfall = true,
	consecutiveShortfallTicks = 3,
})
assertEqual(shortfallSnapshot.escapePressure, VillageStatusHudConfig.EscapePressure.Critical, "shortfall critical")
assertEqual(shortfallSnapshot.tone, VillageStatusHudConfig.Tones.Critical, "shortfall critical tone")

print("village_status_state.spec.luau: all checks passed")
