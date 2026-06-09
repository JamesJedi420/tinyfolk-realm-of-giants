--!strict

local PenRationingConfig: any = {}

PenRationingConfig.DefaultPenId = "Pen_A"
PenRationingConfig.IntervalSeconds = 1
PenRationingConfig.FoodPerCaptivePerInterval = 1

PenRationingConfig.MoraleDefault = 100
PenRationingConfig.MoraleMin = 0
PenRationingConfig.MoraleMax = 100
PenRationingConfig.MoraleLossPerShortfallTick = 12
PenRationingConfig.MoraleRecoveryPerSuccessfulTick = 3

PenRationingConfig.StateAttributes = {
	ActiveCaptiveCount = "PenRationingActiveCaptiveCount",
	FoodConsumedTotal = "PenRationingFoodConsumedTotal",
	LastTickAt = "PenRationingLastTickAt",
	LastFoodShortfall = "PenRationingLastFoodShortfall",
	ConsecutiveShortfallTicks = "PenRationingConsecutiveShortfallTicks",
	StarvationReleasesTotal = "PenRationingStarvationReleasesTotal",
	PenUpgradeLevel = "PenRationingPenUpgradeLevel",
	FoodCostMultiplier = "PenRationingFoodCostMultiplier",
	CustodianMorale = "PenRationingCustodianMorale",
}

return PenRationingConfig
