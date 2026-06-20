--!strict

local TinyfolkInspectConfig: any = {}

TinyfolkInspectConfig.GuiName = "TinyfolkInspectGui"
TinyfolkInspectConfig.PanelName = "Panel"
TinyfolkInspectConfig.MaxSelectRangeStuds = 80

TinyfolkInspectConfig.UnavailableLabel = "Unavailable"
TinyfolkInspectConfig.NoneLabel = "None"
TinyfolkInspectConfig.UnassignedLabel = "Unassigned"
TinyfolkInspectConfig.MissingLabel = "—"

TinyfolkInspectConfig.Tones = {
	Neutral = "neutral",
	Warning = "warning",
	Critical = "critical",
}

TinyfolkInspectConfig.Attributes = {
	Role = "Role",
	SpecialistRole = "SpecialistRole",
	CarriedState = "CarriedState",
	CaptureActive = "CaptureActive",
	CaptureContainmentPhase = "CaptureContainmentPhase",
	DownedIsDowned = "DownedIsDowned",
	CaptiveStarving = "PenRationingCaptiveStarving",
	CaptiveShortfallStreak = "PenRationingCaptiveShortfallStreak",
	FearExposureRatio = "TinyfolkFearExposureRatio",
	RaidHudThreatStage = "TinyfolkRaidHudThreatStage",
	MovementTraitEnabled = "TinyfolkTrait_PostCrossingBurst",
	SprintStaminaRatio = "TinyfolkSprintStaminaRatio",
	SprintExhausted = "TinyfolkSprintExhausted",
	ScheduledJobKind = "TinyfolkScheduledJobKind",
	ScheduledJobStationId = "TinyfolkScheduledJobStationId",
	ScheduledJobMaterial = "TinyfolkScheduledJobMaterial",
	HaulPhase = "TinyfolkHaulPhase",
	HaulRouteSourceId = "TinyfolkHaulRouteSourceId",
	HaulRouteDeliveryId = "TinyfolkHaulRouteDeliveryId",
	HaulMaterial = "TinyfolkHaulMaterial",
	ScoreTotal = "ScoreTotal",
	LaborTokens = "TinyfolkLaborTokens",
}

return TinyfolkInspectConfig
