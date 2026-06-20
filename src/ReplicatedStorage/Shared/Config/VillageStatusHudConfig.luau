--!strict

local VillageStatusHudConfig: any = {}

VillageStatusHudConfig.RefreshIntervalSeconds = 1

VillageStatusHudConfig.GuiName = "VillageStatusHudGui"
VillageStatusHudConfig.PanelName = "Panel"

VillageStatusHudConfig.Tones = {
	Neutral = "neutral",
	Warning = "warning",
	Critical = "critical",
}

VillageStatusHudConfig.EscapePressure = {
	Calm = "calm",
	Elevated = "elevated",
	Critical = "critical",
}

VillageStatusHudConfig.Thresholds = {
	FoodStoredWarning = 30,
	FoodStoredCritical = 10,
	ShortfallStreakCritical = 3,
	ActiveRaiderWarning = 2,
	ActiveRaiderCritical = 4,
	ActiveCaptiveElevated = 2,
}

VillageStatusHudConfig.Attributes = {
	ActiveRaiderCount = "VillageStatusActiveRaiderCount",
	WorkerCount = "VillageStatusWorkerCount",
	ActiveCaptiveCount = "VillageStatusActiveCaptiveCount",
	FoodStored = "VillageStatusFoodStored",
	FoodInTransit = "VillageStatusFoodInTransit",
	Morale = "VillageStatusMorale",
	LastFoodShortfall = "VillageStatusLastFoodShortfall",
	ConsecutiveShortfallTicks = "VillageStatusConsecutiveShortfallTicks",
	WoodProduced = "VillageStatusWoodProduced",
	StoneProduced = "VillageStatusStoneProduced",
	ActiveJobCount = "VillageStatusActiveJobCount",
	EscapePressure = "VillageStatusEscapePressure",
	Tone = "VillageStatusTone",
	Summary = "VillageStatusSummary",
	UpdatedAt = "VillageStatusUpdatedAt",
}

return VillageStatusHudConfig
