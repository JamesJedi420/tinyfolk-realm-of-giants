--!strict

local TinyfolkHubConfig: any = {}

TinyfolkHubConfig.SpawnFolderPath = { "Map", "Spawns" }
TinyfolkHubConfig.HubSpawnName = "TinyfolkHubSpawn"
TinyfolkHubConfig.LegacyTinyfolkSpawnName = "TinyfolkSpawn"

TinyfolkHubConfig.WorldFolderPath = { "Map", "TinyfolkWorld" }
TinyfolkHubConfig.ReturnPointName = "TinyfolkReturnPoint"

TinyfolkHubConfig.SafeZonePartPrefix = "SharedHubSafeZone_"
TinyfolkHubConfig.PartyAnchorPrefix = "PartyHub_"
TinyfolkHubConfig.RealmPortalPrefix = "RealmPortalHub_"

TinyfolkHubConfig.LocationCategoryAttribute = "LocationCategory"
TinyfolkHubConfig.InHubAttribute = "InTinyfolkHub"

TinyfolkHubConfig.PartyInteractionRangeStuds = 16
TinyfolkHubConfig.PartyOpenRequestAttribute = "TinyfolkPartyOpenRequested"
TinyfolkHubConfig.DefaultPartyAnchorId = "PartyHub_A"

TinyfolkHubConfig.Activities = {
	RaidBoard = "raid_board",
	RescueContractBoard = "rescue_contract_board",
	Party = "party",
	RealmPortal = "realm_portal",
}

return TinyfolkHubConfig
