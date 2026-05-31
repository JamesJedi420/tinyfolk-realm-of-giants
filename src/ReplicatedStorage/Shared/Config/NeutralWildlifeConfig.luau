--!strict

local NeutralWildlifeConfig: any = {}

NeutralWildlifeConfig.TargetActiveWildlifeTotal = 6
NeutralWildlifeConfig.MaxActiveWildlifeTotal = 10
NeutralWildlifeConfig.WildlifeLifetimeSeconds = 90
NeutralWildlifeConfig.RespawnIntervalSeconds = 15
NeutralWildlifeConfig.DisturbanceMaxDistance = 80
NeutralWildlifeConfig.WildlifeAnchorBucketSize = 64
NeutralWildlifeConfig.MaxFeedGrantsPerWindow = 2
NeutralWildlifeConfig.FeedGrantWindowSeconds = 120
NeutralWildlifeConfig.FeedScoreEventId = "wildlife_feed"

NeutralWildlifeConfig.DefaultRealmTemplateId = "DefaultRealm"

NeutralWildlifeConfig.HabitatGroups = {
	{
		habitatGroupId = "forest_edge",
		realmTemplateIds = { "DefaultRealm" },
		targetActive = 2,
		speciesIds = { "deer", "boar" },
		clueTag = "disturbed_forest_edge",
	},
	{
		habitatGroupId = "waterline",
		realmTemplateIds = { "DefaultRealm" },
		targetActive = 2,
		speciesIds = { "waterfowl", "hare" },
		clueTag = "disturbed_waterline",
	},
	{
		habitatGroupId = "high_grass",
		realmTemplateIds = { "DefaultRealm" },
		targetActive = 2,
		speciesIds = { "hare", "pheasant" },
		clueTag = "disturbed_high_grass",
	},
}

NeutralWildlifeConfig.ClueCategory = "wildlife"
NeutralWildlifeConfig.ClueSeverity = "info"

return NeutralWildlifeConfig
