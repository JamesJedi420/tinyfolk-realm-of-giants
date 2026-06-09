--!strict

local UpgradeBoardConfig = require("../Config/UpgradeBoardConfig")
local VillageWorksiteUpgradeConfig = require("../Config/VillageWorksiteUpgradeConfig")

local GiantWorksiteEffectResolution: any = {}

local function normalizeLevel(level: any): number
	if type(level) ~= "number" or level ~= level then
		return 0
	end
	return math.clamp(math.floor(level), 0, VillageWorksiteUpgradeConfig.MaxLevel)
end

local function resolveBonusesByLevel(tableByLevel: any, level: number): any
	local normalizedLevel = normalizeLevel(level)
	local bonuses = if type(tableByLevel) == "table" then tableByLevel[normalizedLevel] else nil
	if type(bonuses) ~= "table" then
		bonuses = if type(tableByLevel) == "table" then tableByLevel[0] else nil
	end
	if type(bonuses) ~= "table" then
		return {
			maxHealthBonus = 0,
			powerBudgetBonus = 0,
			walkSpeedBonus = 0,
			movementControlBonus = 0,
		}
	end

	return {
		maxHealthBonus = if type(bonuses.maxHealthBonus) == "number" then bonuses.maxHealthBonus else 0,
		powerBudgetBonus = if type(bonuses.powerBudgetBonus) == "number" then bonuses.powerBudgetBonus else 0,
		walkSpeedBonus = if type(bonuses.walkSpeedBonus) == "number" then bonuses.walkSpeedBonus else 0,
		movementControlBonus = if type(bonuses.movementControlBonus) == "number"
			then bonuses.movementControlBonus
			else 0,
	}
end

function GiantWorksiteEffectResolution.ResolveShrineBonuses(shrineLevel: number): any
	return resolveBonusesByLevel(VillageWorksiteUpgradeConfig.ShrineGiantVitalityBonusesByLevel, shrineLevel)
end

function GiantWorksiteEffectResolution.ResolveDwellingBonuses(dwellingLevel: number): any
	return resolveBonusesByLevel(VillageWorksiteUpgradeConfig.DwellingGiantLocomotionBonusesByLevel, dwellingLevel)
end

function GiantWorksiteEffectResolution.ResolveEffects(input: any): any
	local shrineLevel = if type(input) == "table" then normalizeLevel(input.shrineLevel) else 0
	local dwellingLevel = if type(input) == "table" then normalizeLevel(input.dwellingLevel) else 0

	local shrineBonuses = GiantWorksiteEffectResolution.ResolveShrineBonuses(shrineLevel)
	local dwellingBonuses = GiantWorksiteEffectResolution.ResolveDwellingBonuses(dwellingLevel)

	local maxHealthBonus = shrineBonuses.maxHealthBonus
	local powerBudgetBonus = shrineBonuses.powerBudgetBonus
	local walkSpeedBonus = dwellingBonuses.walkSpeedBonus
	local movementControlBonus = dwellingBonuses.movementControlBonus

	return {
		maxHealth = UpgradeBoardConfig.BaseHumanoidMaxHealth + maxHealthBonus,
		walkSpeed = UpgradeBoardConfig.BaseHumanoidWalkSpeed + walkSpeedBonus,
		maxHealthBonus = maxHealthBonus,
		walkSpeedBonus = walkSpeedBonus,
		powerBudget = UpgradeBoardConfig.BasePowerBudget + powerBudgetBonus,
		movementControl = UpgradeBoardConfig.BaseMovementControl + movementControlBonus,
		powerBudgetBonus = powerBudgetBonus,
		movementControlBonus = movementControlBonus,
		shrineLevel = shrineLevel,
		dwellingLevel = dwellingLevel,
	}
end

return GiantWorksiteEffectResolution
