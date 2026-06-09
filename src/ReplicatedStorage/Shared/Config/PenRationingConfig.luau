--!strict

local PenRationingConfig: any = {}

PenRationingConfig.DefaultPenId = "Pen_A"
PenRationingConfig.IntervalSeconds = 1
PenRationingConfig.FoodPerCaptivePerInterval = 1

PenRationingConfig.StateAttributes = {
	ActiveCaptiveCount = "PenRationingActiveCaptiveCount",
	FoodConsumedTotal = "PenRationingFoodConsumedTotal",
	LastTickAt = "PenRationingLastTickAt",
	LastFoodShortfall = "PenRationingLastFoodShortfall",
}

return PenRationingConfig
