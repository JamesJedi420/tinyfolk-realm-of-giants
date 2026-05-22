--!strict

local TinyfolkStatusConfig: any = {}

TinyfolkStatusConfig.FearRadiusStuds = 60
TinyfolkStatusConfig.FearPanicThreshold = 0.75
TinyfolkStatusConfig.FearPanicRecoveryThreshold = 0.4
TinyfolkStatusConfig.FearPanicDurationSeconds = 4
TinyfolkStatusConfig.FearRampSeconds = 0.75
TinyfolkStatusConfig.FearRecoverySeconds = 1.5

TinyfolkStatusConfig.GiantProximityWarning = {
	Levels = {
		None = "none",
		Watch = "watch",
		Near = "near",
		Danger = "danger",
	},
	ExposureThresholds = {
		Watch = 0.1,
		Near = 0.45,
		Danger = 0.75,
	},
}

TinyfolkStatusConfig.GiantThreatStage = {
	Levels = {
		Calm = "calm",
		Watch = "watch",
		Pressure = "pressure",
		Critical = "critical",
	},
	WarningLevelToStage = {
		none = "calm",
		watch = "watch",
		near = "pressure",
		danger = "critical",
	},
	DecaySeconds = 10,
}

TinyfolkStatusConfig.BleedDurationSeconds = 5
TinyfolkStatusConfig.StunDurationSeconds = 2
TinyfolkStatusConfig.FluxDurationSeconds = 6

TinyfolkStatusConfig.MaxTimedConditionDurationSeconds = 30
TinyfolkStatusConfig.TrailLifetimeSeconds = 6
TinyfolkStatusConfig.TrailMaxPoints = 6
TinyfolkStatusConfig.TrailSampleMinDistanceStuds = 4
TinyfolkStatusConfig.TrailSampleMinIntervalSeconds = 0.25

TinyfolkStatusConfig.Attributes = {
	FearExposure = "TinyfolkFearExposure",
	FearExposureRatio = "TinyfolkFearExposureRatio",
	FearActive = "TinyfolkFearActive",
	FearPanic = "TinyfolkFearPanic",
	FearPanicUntil = "TinyfolkFearPanicUntil",
	FearNearestGiantUserId = "TinyfolkFearNearestGiantUserId",
	FearNearestGiantDistance = "TinyfolkFearNearestGiantDistance",
	GiantProximityWarningLevel = "TinyfolkGiantProximityWarningLevel",
	RaidHudThreatStage = "TinyfolkRaidHudThreatStage",
	ConditionSummary = "TinyfolkConditionSummary",
	BleedActive = "TinyfolkBleedActive",
	BleedUntil = "TinyfolkBleedUntil",
	StunActive = "TinyfolkStunActive",
	StunUntil = "TinyfolkStunUntil",
	FluxActive = "TinyfolkFluxActive",
	FluxUntil = "TinyfolkFluxUntil",
	RaidHudSummary = "TinyfolkRaidHudSummary",
	RaidHudThreatLevel = "TinyfolkRaidHudThreatLevel",
	RaidHudCustodyState = "TinyfolkRaidHudCustodyState",
	RaidHudPersonalEffects = "TinyfolkRaidHudPersonalEffects",
	RaidHudTeammateActivity = "TinyfolkRaidHudTeammateActivity",
	RaidHudScoreFeedback = "TinyfolkRaidHudScoreFeedback",
	RaidHudUpdatedAt = "TinyfolkRaidHudUpdatedAt",
}

TinyfolkStatusConfig.RaidHud = {
	ThreatLevels = {
		None = "none",
		Low = "low",
		Medium = "medium",
		High = "high",
	},
	ThreatExposureThresholds = {
		Low = 0.1,
		Medium = 0.45,
		High = 0.75,
	},
	Categories = {
		PersonalEffect = "personal_effect",
		TeammateActivity = "teammate_activity",
		Custody = "custody",
		Threat = "threat",
		ScoreFeedback = "score_feedback",
		Escape = "escape",
	},
	Severity = {
		Info = "info",
		Positive = "positive",
		Warning = "warning",
		Critical = "critical",
	},
}

return TinyfolkStatusConfig
