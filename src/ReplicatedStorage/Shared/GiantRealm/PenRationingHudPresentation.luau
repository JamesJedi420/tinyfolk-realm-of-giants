--!strict

local PenRationingHudPresentation: any = {}

export type PenRationingHudModel = {
	visible: boolean,
	title: string,
	summary: string,
	tone: string,
}

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function readNumber(snapshot: any, fieldName: string, defaultValue: number): number
	if type(snapshot) ~= "table" then
		return defaultValue
	end
	local value = finiteNumber(snapshot[fieldName])
	if value == nil then
		return defaultValue
	end
	return value
end

local function readBoolean(snapshot: any, fieldName: string): boolean
	if type(snapshot) ~= "table" then
		return false
	end
	return snapshot[fieldName] == true
end

local function readString(snapshot: any, fieldName: string, defaultValue: string): string
	if type(snapshot) ~= "table" then
		return defaultValue
	end
	local value = snapshot[fieldName]
	if type(value) ~= "string" then
		return defaultValue
	end
	return value
end

function PenRationingHudPresentation.BuildHudModel(snapshot: any): PenRationingHudModel
	local role = readString(snapshot, "role", "")
	local captureActive = readBoolean(snapshot, "captureActive")

	if role == "Giant" then
		local moraleDefault = readNumber(snapshot, "moraleDefault", 100)
		local moraleCaptureSureThreshold = readNumber(snapshot, "moraleCaptureSureThreshold", 50)
		local morale = readNumber(snapshot, "custodianMorale", moraleDefault)
		local readiness = readNumber(
			snapshot,
			"captureReadinessPercent",
			if morale >= moraleCaptureSureThreshold
				then 100
				else math.clamp(math.floor((morale / moraleCaptureSureThreshold) * 100 + 0.5), 0, 100)
		)
		local lastFoodShortfall = readBoolean(snapshot, "lastFoodShortfall")
		local consecutiveShortfallTicks = readNumber(snapshot, "consecutiveShortfallTicks", 0)
		local activeCaptiveCount = readNumber(snapshot, "activeCaptiveCount", 0)
		local foodCostMultiplier = readNumber(snapshot, "foodCostMultiplier", 1)

		local tone = "neutral"
		if lastFoodShortfall or consecutiveShortfallTicks > 0 then
			tone = "warning"
		elseif morale < moraleCaptureSureThreshold then
			tone = "warning"
		end

		local shortfallLine = if lastFoodShortfall
			then string.format("Shortfall x%d", math.max(1, math.floor(consecutiveShortfallTicks)))
			else "Rations OK"

		local intimidationBonus = readNumber(snapshot, "controlIntimidationBonus", 1)
		local intimidationLine = if intimidationBonus > 1
			then string.format(" | Intimidation x%.2f", intimidationBonus)
			else ""

		return {
			visible = true,
			title = "Pen Rationing",
			summary = string.format(
				"Morale %d | Capture %d%% | %s | Captives %d | Food x%.2f%s",
				math.floor(morale),
				readiness,
				shortfallLine,
				math.floor(activeCaptiveCount),
				foodCostMultiplier,
				intimidationLine
			),
			tone = tone,
		}
	end

	if role == "Tinyfolk" and captureActive then
		local shortfallStreak = readNumber(snapshot, "captiveShortfallStreak", 0)
		local captiveStarving = readBoolean(snapshot, "captiveStarving")
		local tone = if captiveStarving then "warning" else "neutral"
		local statusLine = if captiveStarving
			then string.format("Starving (%d ration shortfalls)", math.floor(shortfallStreak))
			elseif shortfallStreak > 0 then string.format(
				"Ration stress (%d shortfalls)",
				math.floor(shortfallStreak)
			)
			else "Pen rations holding"

		return {
			visible = true,
			title = "Captivity Rations",
			summary = statusLine,
			tone = tone,
		}
	end

	return {
		visible = false,
		title = "Pen Rationing",
		summary = "",
		tone = "neutral",
	}
end

return PenRationingHudPresentation
