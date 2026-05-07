--!strict

local UpgradeBoardConfig = {}

UpgradeBoardConfig.BoardNamePrefix = "GiantUpgradeBoard_"
UpgradeBoardConfig.DefaultBoardId = "GiantUpgradeBoard_A"

UpgradeBoardConfig.InteractionRangeStuds = 16
UpgradeBoardConfig.RequestCooldownSeconds = 0.2

UpgradeBoardConfig.BaseHumanoidMaxHealth = 100
UpgradeBoardConfig.BaseHumanoidWalkSpeed = 16
UpgradeBoardConfig.BasePowerBudget = 100
UpgradeBoardConfig.BaseMovementControl = 1

UpgradeBoardConfig.UpgradeOptions = {
	{
		id = "PowerCore",
		label = "Power Core",
		costEssence = 24,
	},
	{
		id = "IronStride",
		label = "Iron Stride",
		costEssence = 18,
	},
}

UpgradeBoardConfig.EffectByUpgradeId = {
	PowerCore = {
		maxHealthBonus = 50,
		walkSpeedBonus = 0,
		powerBudgetBonus = 25,
		movementControlBonus = 0,
	},
	IronStride = {
		maxHealthBonus = 0,
		walkSpeedBonus = 6,
		powerBudgetBonus = 0,
		movementControlBonus = 0.25,
	},
}

return UpgradeBoardConfig