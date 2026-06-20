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
	Positive = "positive",
	Warning = "warning",
	Critical = "critical",
}

-- RGB triplets for client highlight fill/outline (panel accent uses custody tone only).
TinyfolkInspectConfig.HighlightAccentRgbByTone = {
	[TinyfolkInspectConfig.Tones.Neutral] = { 151, 159, 174 },
	[TinyfolkInspectConfig.Tones.Positive] = { 88, 180, 120 },
	[TinyfolkInspectConfig.Tones.Warning] = { 224, 166, 68 },
	[TinyfolkInspectConfig.Tones.Critical] = { 214, 88, 88 },
}

TinyfolkInspectConfig.HighlightName = "TinyfolkInspectSelectionHighlight"
TinyfolkInspectConfig.HighlightFillTransparency = 0.65
TinyfolkInspectConfig.HighlightOutlineTransparency = 0
TinyfolkInspectConfig.HighlightDepthMode = Enum.HighlightDepthMode.AlwaysOnTop

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
	SocialDyadicFavor = "SocialDyadicFavor",
	SocialDyadicControl = "SocialDyadicControl",
}

return TinyfolkInspectConfig
