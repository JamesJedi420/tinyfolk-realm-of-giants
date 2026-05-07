--!strict

local StationConfig = {}

StationConfig.StationNamePrefix = "WorkStation_"
StationConfig.MiningStationNamePrefix = "MiningStation_"
StationConfig.WarehouseNamePrefix = "Warehouse_"
StationConfig.GranaryNamePrefix = "Granary_"
StationConfig.DefaultStationId = "WorkStation_A"
StationConfig.DefaultMiningStationId = "MiningStation_A"
StationConfig.DefaultWarehouseId = "Warehouse_A"
StationConfig.DefaultGranaryId = "Granary_A"

StationConfig.ActivationRangeStuds = 16
StationConfig.RequestCooldownSeconds = 0.2

StationConfig.GenerationIntervalSeconds = 1
StationConfig.EssencePerTick = 2
StationConfig.MaxEssenceTotal = 200

StationConfig.WoodPerTick = 2
StationConfig.MaxWoodTotal = 200
StationConfig.StonePerTick = 2
StationConfig.MaxStoneTotal = 200

StationConfig.HaulIntervalSeconds = 1
StationConfig.HaulTransferPerStepByMaterial = {
	Wood = 2,
	Stone = 2,
}
StationConfig.MaxInTransitByMaterial = {
	Wood = 200,
	Stone = 200,
}

-- Material goods (Wood, Stone) both route to Warehouse.
-- Granary_A is reserved for future food/crop resources.
StationConfig.DeliveryPointIdByMaterial = {
	Wood = StationConfig.DefaultWarehouseId,
	Stone = StationConfig.DefaultWarehouseId,
}

StationConfig.RequiredSpecialistRoleByStationId = {
	WorkStation_A = "Woodcutter",
	MiningStation_A = "Miner",
}

StationConfig.DebugLogEveryTicks = 1

return StationConfig
