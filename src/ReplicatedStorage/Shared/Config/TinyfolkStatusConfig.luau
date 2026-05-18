--!strict

local TinyfolkStatusConfig: any = {}

TinyfolkStatusConfig.FearRadiusStuds = 60
TinyfolkStatusConfig.FearPanicThreshold = 0.75
TinyfolkStatusConfig.FearPanicRecoveryThreshold = 0.4
TinyfolkStatusConfig.FearPanicDurationSeconds = 4
TinyfolkStatusConfig.FearRampSeconds = 0.75
TinyfolkStatusConfig.FearRecoverySeconds = 1.5

TinyfolkStatusConfig.BleedDurationSeconds = 5
TinyfolkStatusConfig.StunDurationSeconds = 2
TinyfolkStatusConfig.FluxDurationSeconds = 6

TinyfolkStatusConfig.MaxTimedConditionDurationSeconds = 30

TinyfolkStatusConfig.Attributes = {
	FearExposure = "TinyfolkFearExposure",
	FearExposureRatio = "TinyfolkFearExposureRatio",
	FearActive = "TinyfolkFearActive",
	FearPanic = "TinyfolkFearPanic",
	FearPanicUntil = "TinyfolkFearPanicUntil",
	FearNearestGiantUserId = "TinyfolkFearNearestGiantUserId",
	FearNearestGiantDistance = "TinyfolkFearNearestGiantDistance",
	ConditionSummary = "TinyfolkConditionSummary",
	BleedActive = "TinyfolkBleedActive",
	BleedUntil = "TinyfolkBleedUntil",
	StunActive = "TinyfolkStunActive",
	StunUntil = "TinyfolkStunUntil",
	FluxActive = "TinyfolkFluxActive",
	FluxUntil = "TinyfolkFluxUntil",
}

return TinyfolkStatusConfig