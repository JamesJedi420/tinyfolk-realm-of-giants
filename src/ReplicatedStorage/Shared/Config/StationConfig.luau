--!strict

local StationConfig: any = {}

StationConfig.StationNamePrefix = "WorkStation_"
StationConfig.MiningStationNamePrefix = "MiningStation_"
StationConfig.WarehouseNamePrefix = "Warehouse_"
StationConfig.GranaryNamePrefix = "Granary_"
StationConfig.FarmNamePrefix = "Farm_"
StationConfig.PenNamePrefix = "Pen_"
StationConfig.GuardTowerNamePrefix = "GuardTower_"
StationConfig.DefaultStationId = "WorkStation_A"
StationConfig.DefaultMiningStationId = "MiningStation_A"
StationConfig.DefaultWarehouseId = "Warehouse_A"
StationConfig.DefaultGranaryId = "Granary_A"
StationConfig.DefaultFarmId = "Farm_A"
StationConfig.DefaultPenId = "Pen_A"
StationConfig.DefaultGuardTowerId = "GuardTower_A"

StationConfig.ActivationRangeStuds = 16
StationConfig.RequestCooldownSeconds = 0.2
StationConfig.TaskDurationSeconds = 1.5
StationConfig.TaskRegressionPerSecond = 0.35
StationConfig.TaskStabilizationThresholdSeconds = 0.4
StationConfig.TaskMajorRegressionStepSeconds = 0.8
StationConfig.TaskMajorRegressionMaxEvents = 2
StationConfig.TaskRegressionWindowSeconds = 3.0
StationConfig.TaskQteEnabled = false
StationConfig.TaskQteWindowSeconds = 0.2
StationConfig.TaskQteBonusSeconds = 0.35
StationConfig.TaskQteFailureDisrupts = true

StationConfig.TaskActiveStationIdAttribute = "StationTaskActiveStationId"
StationConfig.TaskProgressRatioAttribute = "StationTaskProgressRatio"
StationConfig.TaskStartedAtAttribute = "StationTaskStartedAt"
StationConfig.TaskEndsAtAttribute = "StationTaskEndsAt"
StationConfig.TaskLastReasonAttribute = "StationTaskLastReason"
StationConfig.TaskObjectiveStateAttribute = "StationTaskObjectiveState"
StationConfig.TaskProgressSecondsAttribute = "StationTaskProgressSeconds"
StationConfig.TaskRegressionCountAttribute = "StationTaskRegressionCount"
StationConfig.TaskRegressingUntilAttribute = "StationTaskRegressingUntil"
StationConfig.TaskQteResultAttribute = "StationTaskQteResult"

StationConfig.GenerationIntervalSeconds = 1
StationConfig.EssencePerTick = 2
StationConfig.MaxEssenceTotal = 200

StationConfig.WoodPerTick = 2
StationConfig.MaxWoodTotal = 200
StationConfig.StonePerTick = 2
StationConfig.MaxStoneTotal = 200

StationConfig.FoodPerTick = 2
StationConfig.MaxFoodTotal = 200

StationConfig.HaulIntervalSeconds = 1
StationConfig.HaulTransferPerStepByMaterial = {
	Wood = 2,
	Stone = 2,
	Food = 2,
}
StationConfig.MaxInTransitByMaterial = {
	Wood = 200,
	Stone = 200,
	Food = 200,
}

-- Wood and Stone route to Warehouse; Food routes to Granary.
StationConfig.DeliveryPointIdByMaterial = {
	Wood = StationConfig.DefaultWarehouseId,
	Stone = StationConfig.DefaultWarehouseId,
	Food = StationConfig.DefaultGranaryId,
}

StationConfig.RequiredSpecialistRoleByStationId = {
	WorkStation_A = "Woodcutter",
	MiningStation_A = "Miner",
	Farm_A = "Farmer",
}

StationConfig.DebugLogEveryTicks = 1

return StationConfig
