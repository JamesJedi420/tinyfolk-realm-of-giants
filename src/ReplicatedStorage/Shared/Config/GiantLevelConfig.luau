--!strict

local GiantLevelConfig: any = {}

GiantLevelConfig.MaxRetainedRecentEvents = 50

GiantLevelConfig.LevelThresholds = { 0, 100, 250, 500, 1000, 2000, 4000 }

GiantLevelConfig.EventKinds = {
	CaptureSuccess = "capture_success",
	ContainmentHeld = "containment_held",
	WorksiteUpgrade = "worksite_upgrade",
	TradeSuccess = "trade_success",
}

GiantLevelConfig.XpAwardsByEventKind = {
	capture_success = 25,
	containment_held = 40,
	worksite_upgrade = 15,
	trade_success = 30,
}

GiantLevelConfig.ValidModifierFields = {
	xpAwardMultiplier = true,
	containmentRewardMultiplier = true,
}

-- Level unlock catalog: modifiers apply only after explicit unlock resolution.
GiantLevelConfig.LevelUnlockCatalog = {
	[2] = {
		{
			unlockId = "giant_level_2_steward",
			displayName = "Steward",
			modifiers = { xpAwardMultiplier = 1.05, containmentRewardMultiplier = 1 },
		},
	},
	[3] = {
		{
			unlockId = "giant_level_3_overseer",
			displayName = "Overseer",
			modifiers = { xpAwardMultiplier = 1, containmentRewardMultiplier = 1.05 },
		},
	},
	[4] = {
		{
			unlockId = "giant_level_4_warden",
			displayName = "Warden",
			modifiers = { xpAwardMultiplier = 1.05, containmentRewardMultiplier = 1 },
		},
	},
	[5] = {
		{
			unlockId = "giant_level_5_tyrant",
			displayName = "Tyrant",
			modifiers = { xpAwardMultiplier = 1, containmentRewardMultiplier = 1.05 },
		},
	},
	[6] = {
		{
			unlockId = "giant_level_6_sovereign",
			displayName = "Sovereign",
			modifiers = { xpAwardMultiplier = 1.05, containmentRewardMultiplier = 1 },
		},
	},
	[7] = {
		{
			unlockId = "giant_level_7_colossus",
			displayName = "Colossus",
			modifiers = { xpAwardMultiplier = 1, containmentRewardMultiplier = 1.1 },
		},
	},
}

GiantLevelConfig.StateAttributes = {
	Xp = "GiantXp",
	Level = "GiantLevel",
	XpToNextLevel = "GiantXpToNextLevel",
	ResolvedUnlockCount = "GiantLevelResolvedUnlockCount",
	XpAwardMultiplier = "GiantLevelXpAwardMultiplier",
	ContainmentRewardMultiplier = "GiantLevelContainmentRewardMultiplier",
	LevelUpSignal = "GiantLevelUpSignal",
	LastLevelUpLevel = "GiantLevelLastLevelUpLevel",
}

return GiantLevelConfig
