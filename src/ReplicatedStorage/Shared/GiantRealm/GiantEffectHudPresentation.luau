--!strict

local GiantEffectHudPresentation: any = {}

export type GiantEffectHudModel = {
	visible: boolean,
	title: string,
	summary: string,
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

function GiantEffectHudPresentation.BuildHudModel(snapshot: any): GiantEffectHudModel
	local maxHealth = readNumber(snapshot, "maxHealth", 0)
	local walkSpeed = readNumber(snapshot, "walkSpeed", 0)
	local powerBudget = readNumber(snapshot, "powerBudget", 0)
	local movementControl = readNumber(snapshot, "movementControl", 0)
	local maxHealthBonus = readNumber(snapshot, "maxHealthBonus", 0)
	local walkSpeedBonus = readNumber(snapshot, "walkSpeedBonus", 0)
	local powerBudgetBonus = readNumber(snapshot, "powerBudgetBonus", 0)
	local movementControlBonus = readNumber(snapshot, "movementControlBonus", 0)

	local summary = string.format(
		"HP %.0f (+%.0f) | Speed %.0f (+%.0f) | Power %.0f (+%.0f) | Control %.2f (+%.2f)",
		maxHealth,
		maxHealthBonus,
		walkSpeed,
		walkSpeedBonus,
		powerBudget,
		powerBudgetBonus,
		movementControl,
		movementControlBonus
	)

	return {
		visible = true,
		title = "Giant Effects",
		summary = summary,
	}
end

return GiantEffectHudPresentation
