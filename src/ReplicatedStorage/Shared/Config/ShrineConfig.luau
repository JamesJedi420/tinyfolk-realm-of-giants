--!strict

local ShrineConfig: any = {}

ShrineConfig.ShrineNamePrefix = "Shrine_"
ShrineConfig.DefaultShrineId = "Shrine_A"

ShrineConfig.ActivationRangeStuds = 16
ShrineConfig.RequestCooldownSeconds = 0.2
ShrineConfig.TaskDurationSeconds = 1.5
ShrineConfig.TaskRegressionPerSecond = 0.35
ShrineConfig.TaskStabilizationThresholdSeconds = 0.4
ShrineConfig.TaskMajorRegressionStepSeconds = 0.8
ShrineConfig.TaskMajorRegressionMaxEvents = 2
ShrineConfig.TaskRegressionWindowSeconds = 3.0

ShrineConfig.TaskActiveShrineIdAttribute = "ShrineTaskActiveShrineId"
ShrineConfig.TaskProgressRatioAttribute = "ShrineTaskProgressRatio"
ShrineConfig.TaskStartedAtAttribute = "ShrineTaskStartedAt"
ShrineConfig.TaskEndsAtAttribute = "ShrineTaskEndsAt"
ShrineConfig.TaskLastReasonAttribute = "ShrineTaskLastReason"
ShrineConfig.TaskObjectiveStateAttribute = "ShrineTaskObjectiveState"
ShrineConfig.TaskProgressSecondsAttribute = "ShrineTaskProgressSeconds"
ShrineConfig.TaskRegressionCountAttribute = "ShrineTaskRegressionCount"
ShrineConfig.TaskRegressingUntilAttribute = "ShrineTaskRegressingUntil"

ShrineConfig.GenerationIntervalSeconds = 2
ShrineConfig.EssencePerTick = 3
ShrineConfig.MaxEssenceTotal = 180

ShrineConfig.DebugLogEveryTicks = 1

return ShrineConfig
