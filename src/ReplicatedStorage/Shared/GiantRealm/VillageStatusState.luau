--!strict

local PenRationingConfig = require("../Config/PenRationingConfig")
local VillageStatusHudConfig = require("../Config/VillageStatusHudConfig")

local VillageStatusState = {}

export type DangerLevel = "neutral" | "warning" | "critical"

export type VillageStatusSnapshot = {
	activeRaiderCount: number,
	workerCount: number,
	activeCaptiveCount: number,
	foodStored: number,
	foodInTransit: number,
	woodProduced: number,
	stoneProduced: number,
	morale: number,
	lastFoodShortfall: boolean,
	consecutiveShortfallTicks: number,
	activeJobCount: number,
	escapePressure: string,
	tone: string,
}

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function readNumber(input: any, fieldName: string, defaultValue: number): number
	if type(input) ~= "table" then
		return defaultValue
	end
	local value = finiteNumber(input[fieldName])
	if value == nil then
		return defaultValue
	end
	return math.max(0, math.floor(value + 0.5))
end

local function readBoolean(input: any, fieldName: string): boolean
	if type(input) ~= "table" then
		return false
	end
	return input[fieldName] == true
end

local function worseTone(current: DangerLevel, nextLevel: DangerLevel): DangerLevel
	if current == "critical" or nextLevel == "critical" then
		return "critical"
	end
	if current == "warning" or nextLevel == "warning" then
		return "warning"
	end
	return "neutral"
end

local function resolveFoodDanger(foodStored: number, thresholds: any): DangerLevel
	if foodStored <= thresholds.FoodStoredCritical then
		return "critical"
	end
	if foodStored < thresholds.FoodStoredWarning then
		return "warning"
	end
	return "neutral"
end

local function resolveMoraleDanger(morale: number, moraleCaptureSureThreshold: number): DangerLevel
	if morale <= 0 then
		return "critical"
	end
	if morale < moraleCaptureSureThreshold then
		return "warning"
	end
	return "neutral"
end

local function resolveShortfallDanger(
	lastFoodShortfall: boolean,
	consecutiveShortfallTicks: number,
	thresholds: any
): DangerLevel
	if consecutiveShortfallTicks >= thresholds.ShortfallStreakCritical then
		return "critical"
	end
	if lastFoodShortfall or consecutiveShortfallTicks > 0 then
		return "warning"
	end
	return "neutral"
end

local function resolveRaiderDanger(activeRaiderCount: number, thresholds: any): DangerLevel
	if activeRaiderCount >= thresholds.ActiveRaiderCritical then
		return "critical"
	end
	if activeRaiderCount >= thresholds.ActiveRaiderWarning then
		return "warning"
	end
	return "neutral"
end

function VillageStatusState.ResolveEscapePressure(input: {
	activeRaiderCount: number,
	activeCaptiveCount: number,
	morale: number,
	lastFoodShortfall: boolean,
	consecutiveShortfallTicks: number,
	moraleCaptureSureThreshold: number,
	thresholds: any,
}): string
	local escape = VillageStatusHudConfig.EscapePressure
	local thresholds = input.thresholds
	local raiderDanger = resolveRaiderDanger(input.activeRaiderCount, thresholds)
	local moraleDanger = resolveMoraleDanger(input.morale, input.moraleCaptureSureThreshold)
	local shortfallDanger = resolveShortfallDanger(input.lastFoodShortfall, input.consecutiveShortfallTicks, thresholds)

	if raiderDanger == "critical" then
		return escape.Critical
	end
	if moraleDanger == "critical" and input.activeRaiderCount > 0 then
		return escape.Critical
	end
	if shortfallDanger == "critical" and input.activeCaptiveCount > 0 then
		return escape.Critical
	end
	if raiderDanger == "warning" then
		return escape.Elevated
	end
	if input.activeCaptiveCount >= thresholds.ActiveCaptiveElevated and moraleDanger == "warning" then
		return escape.Elevated
	end
	if shortfallDanger == "warning" and input.activeCaptiveCount > 0 then
		return escape.Elevated
	end
	if input.activeRaiderCount > 0 and moraleDanger == "warning" then
		return escape.Elevated
	end
	return escape.Calm
end

function VillageStatusState.ResolveOverallTone(input: {
	activeRaiderCount: number,
	foodStored: number,
	morale: number,
	lastFoodShortfall: boolean,
	consecutiveShortfallTicks: number,
	moraleCaptureSureThreshold: number,
	escapePressure: string,
	thresholds: any,
}): string
	local tone: DangerLevel = "neutral"
	local thresholds = input.thresholds

	tone = worseTone(tone, resolveFoodDanger(input.foodStored, thresholds))
	tone = worseTone(tone, resolveMoraleDanger(input.morale, input.moraleCaptureSureThreshold))
	tone = worseTone(tone, resolveShortfallDanger(input.lastFoodShortfall, input.consecutiveShortfallTicks, thresholds))
	tone = worseTone(tone, resolveRaiderDanger(input.activeRaiderCount, thresholds))

	if input.escapePressure == VillageStatusHudConfig.EscapePressure.Critical then
		tone = worseTone(tone, "critical")
	elseif input.escapePressure == VillageStatusHudConfig.EscapePressure.Elevated then
		tone = worseTone(tone, "warning")
	end

	return tone
end

function VillageStatusState.BuildSnapshot(input: any): VillageStatusSnapshot
	local thresholds = VillageStatusHudConfig.Thresholds
	if type(input) == "table" and type(input.thresholds) == "table" then
		thresholds = input.thresholds
	end

	local moraleCaptureSureThreshold = PenRationingConfig.MoraleCaptureSureThreshold
	if type(input) == "table" and type(input.moraleCaptureSureThreshold) == "number" then
		moraleCaptureSureThreshold = input.moraleCaptureSureThreshold
	end

	local activeRaiderCount = readNumber(input, "activeRaiderCount", 0)
	local workerCount = readNumber(input, "workerCount", 0)
	local activeCaptiveCount = readNumber(input, "activeCaptiveCount", 0)
	local foodStored = readNumber(input, "foodStored", 0)
	local foodInTransit = readNumber(input, "foodInTransit", 0)
	local woodProduced = readNumber(input, "woodProduced", 0)
	local stoneProduced = readNumber(input, "stoneProduced", 0)
	local morale = readNumber(input, "morale", PenRationingConfig.MoraleDefault)
	local lastFoodShortfall = readBoolean(input, "lastFoodShortfall")
	local consecutiveShortfallTicks = readNumber(input, "consecutiveShortfallTicks", 0)
	local activeJobCount = readNumber(input, "activeJobCount", 0)

	local escapePressure = VillageStatusState.ResolveEscapePressure({
		activeRaiderCount = activeRaiderCount,
		activeCaptiveCount = activeCaptiveCount,
		morale = morale,
		lastFoodShortfall = lastFoodShortfall,
		consecutiveShortfallTicks = consecutiveShortfallTicks,
		moraleCaptureSureThreshold = moraleCaptureSureThreshold,
		thresholds = thresholds,
	})

	local tone = VillageStatusState.ResolveOverallTone({
		activeRaiderCount = activeRaiderCount,
		foodStored = foodStored,
		morale = morale,
		lastFoodShortfall = lastFoodShortfall,
		consecutiveShortfallTicks = consecutiveShortfallTicks,
		moraleCaptureSureThreshold = moraleCaptureSureThreshold,
		escapePressure = escapePressure,
		thresholds = thresholds,
	})

	return {
		activeRaiderCount = activeRaiderCount,
		workerCount = workerCount,
		activeCaptiveCount = activeCaptiveCount,
		foodStored = foodStored,
		foodInTransit = foodInTransit,
		woodProduced = woodProduced,
		stoneProduced = stoneProduced,
		morale = morale,
		lastFoodShortfall = lastFoodShortfall,
		consecutiveShortfallTicks = consecutiveShortfallTicks,
		activeJobCount = activeJobCount,
		escapePressure = escapePressure,
		tone = tone,
	}
end

return VillageStatusState
