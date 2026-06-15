--!strict

local RealmTradeConversionConfig: any = {}

RealmTradeConversionConfig.Roles = {
	Source = "source",
	Destination = "dest",
}

RealmTradeConversionConfig.AwardByRole = {
	source = {
		essence = 5,
		wood = 10,
		stone = 5,
	},
	dest = {
		essence = 8,
		wood = 12,
		stone = 8,
	},
}

RealmTradeConversionConfig.DebugAttributes = {
	LastOperationId = "RealmTradeConversionLastOperationId",
	LastRole = "RealmTradeConversionLastRole",
	LastEssence = "RealmTradeConversionLastEssence",
	LastWood = "RealmTradeConversionLastWood",
	LastStone = "RealmTradeConversionLastStone",
	SessionEssence = "RealmTradeConversionSessionEssence",
	SessionWood = "RealmTradeConversionSessionWood",
	SessionStone = "RealmTradeConversionSessionStone",
	UpdatedAt = "RealmTradeConversionUpdatedAt",
}

RealmTradeConversionConfig.MaxRetainedRecentConversions = 50

return RealmTradeConversionConfig
