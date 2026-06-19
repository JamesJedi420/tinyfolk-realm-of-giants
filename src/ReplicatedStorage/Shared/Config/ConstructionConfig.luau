--!strict

local ConstructionConfig: any = {}

ConstructionConfig.ConstructionSiteNamePrefix = "ConstructionSite_"
ConstructionConfig.DefaultConstructionSiteId = "ConstructionSite_A"

ConstructionConfig.InteractionRangeStuds = 16
ConstructionConfig.RequestCooldownSeconds = 0.2
ConstructionConfig.TaskDurationSeconds = 1.5
ConstructionConfig.TaskRegressionPerSecond = 0.35
ConstructionConfig.TaskStabilizationThresholdSeconds = 0.4
ConstructionConfig.TaskMajorRegressionStepSeconds = 0.8
ConstructionConfig.TaskMajorRegressionMaxEvents = 2
ConstructionConfig.TaskRegressionWindowSeconds = 3.0
ConstructionConfig.TaskQteEnabled = false
ConstructionConfig.TaskQteWindowSeconds = 0.2
ConstructionConfig.TaskQteBonusSeconds = 0.35
ConstructionConfig.TaskQteFailureDisrupts = true

ConstructionConfig.TaskActiveSiteIdAttribute = "ConstructionTaskActiveSiteId"
ConstructionConfig.TaskProgressRatioAttribute = "ConstructionTaskProgressRatio"
ConstructionConfig.TaskStartedAtAttribute = "ConstructionTaskStartedAt"
ConstructionConfig.TaskEndsAtAttribute = "ConstructionTaskEndsAt"
ConstructionConfig.TaskLastReasonAttribute = "ConstructionTaskLastReason"
ConstructionConfig.TaskObjectiveStateAttribute = "ConstructionTaskObjectiveState"
ConstructionConfig.TaskProgressSecondsAttribute = "ConstructionTaskProgressSeconds"
ConstructionConfig.TaskRegressionCountAttribute = "ConstructionTaskRegressionCount"
ConstructionConfig.TaskRegressingUntilAttribute = "ConstructionTaskRegressingUntil"
ConstructionConfig.TaskQteResultAttribute = "ConstructionTaskQteResult"

ConstructionConfig.CostBySiteId = {
	ConstructionSite_A = {
		wood = 8,
		stone = 6,
		food = 4,
	},
	ConstructionSite_B = {
		wood = 8,
		stone = 6,
		food = 4,
	},
	ConstructionSite_C = {
		wood = 6,
		stone = 8,
		food = 0,
		metal = 3,
	},
}

ConstructionConfig.DistrictDefaultCost = {
	wood = 10,
	stone = 8,
	food = 0,
	metal = 0,
}

return ConstructionConfig
