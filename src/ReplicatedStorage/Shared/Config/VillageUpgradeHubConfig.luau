--!strict

local StationConfig = require("./StationConfig")
local ShrineConfig = require("./ShrineConfig")

local VillageUpgradeHubConfig: any = {}

VillageUpgradeHubConfig.RequestCooldownSeconds = 0.25
VillageUpgradeHubConfig.BoardTrackTitle = "Giant Effect Sources"
VillageUpgradeHubConfig.BoardTrackSubtitle =
	"Board purchases deprecated — effects from Shrine & Giant Dwelling levels"
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
