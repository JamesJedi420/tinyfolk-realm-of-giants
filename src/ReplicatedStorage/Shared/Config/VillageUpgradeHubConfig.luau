--!strict

local StationConfig = require("./StationConfig")
local ShrineConfig = require("./ShrineConfig")

local VillageUpgradeHubConfig: any = {}

VillageUpgradeHubConfig.RequestCooldownSeconds = 0.25
VillageUpgradeHubConfig.BoardTrackTitle = "Session Board Track"
VillageUpgradeHubConfig.BoardTrackSubtitle = "Legacy session board effects (migration planned)"
VillageUpgradeHubConfig.WorksiteSectionTitle = "Realm Worksite Upgrades"

VillageUpgradeHubConfig.LegacyMigrationTargetByUpgradeId = {
	PowerCore = "shrine_levels",
	IronStride = "giant_dwelling_levels",
}

VillageUpgradeHubConfig.HubWorksiteCatalog = {
	{
		worksiteId = StationConfig.DefaultStationId,
		displayLabel = "Work Station",
	},
	{
		worksiteId = StationConfig.DefaultMiningStationId,
		displayLabel = "Mining Station",
	},
	{
		worksiteId = StationConfig.DefaultWarehouseId,
		displayLabel = "Warehouse",
	},
	{
		worksiteId = StationConfig.DefaultGranaryId,
		displayLabel = "Granary",
	},
	{
		worksiteId = ShrineConfig.DefaultShrineId,
		displayLabel = "Shrine",
	},
	{
		worksiteId = StationConfig.DefaultFarmId,
		displayLabel = "Farm",
	},
	{
		worksiteId = StationConfig.DefaultPenId,
		displayLabel = "Pen",
	},
	{
		worksiteId = StationConfig.DefaultGuardTowerId,
		displayLabel = "Guard Tower",
	},
	{
		worksiteId = StationConfig.DefaultGiantDwellingId,
		displayLabel = "Giant Dwelling",
	},
}

return VillageUpgradeHubConfig
