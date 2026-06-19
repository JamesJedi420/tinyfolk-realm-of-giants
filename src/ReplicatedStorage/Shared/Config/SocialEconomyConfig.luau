--!strict

local SocialEconomyConfig: any = {}

SocialEconomyConfig.AxisMin = 0
SocialEconomyConfig.AxisMax = 100
SocialEconomyConfig.DefaultFavor = 50
SocialEconomyConfig.DefaultControl = 50
SocialEconomyConfig.DominantAxisBalanceThreshold = 5
SocialEconomyConfig.MaxRetainedRecentEvents = 50

SocialEconomyConfig.EventKinds = {
	FavorGrant = "favor_grant",
	LoyaltyGrant = "loyalty_grant",
	ControlGrant = "control_grant",
	FearGrant = "fear_grant",
}

SocialEconomyConfig.DeltasByTrophyKind = {
	capture_success = { favor = 0, control = 5 },
	negotiated_release = { favor = 5, control = 0 },
	containment_escape_failure = { favor = 0, control = 3 },
}

SocialEconomyConfig.DeltasByEventKind = {
	[SocialEconomyConfig.EventKinds.FavorGrant] = { favor = 5, control = 0 },
	[SocialEconomyConfig.EventKinds.LoyaltyGrant] = { favor = 5, control = 0 },
	[SocialEconomyConfig.EventKinds.ControlGrant] = { favor = 0, control = 5 },
	[SocialEconomyConfig.EventKinds.FearGrant] = { favor = 0, control = 5 },
}

SocialEconomyConfig.DominantAxes = {
	Favor = "favor",
	Control = "control",
	Balanced = "balanced",
}

SocialEconomyConfig.StateAttributes = {
	Favor = "SocialEconomyFavor",
	Control = "SocialEconomyControl",
	DominantAxis = "SocialEconomyDominantAxis",
	FavorComplianceBonus = "SocialEconomyFavorComplianceBonus",
	ControlIntimidationBonus = "SocialEconomyControlIntimidationBonus",
	LastEventKind = "SocialEconomyLastEventKind",
}

return SocialEconomyConfig
