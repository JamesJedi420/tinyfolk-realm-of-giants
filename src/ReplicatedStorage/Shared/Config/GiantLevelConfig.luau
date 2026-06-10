--!strict

local GiantLevelConfig: any = {}

GiantLevelConfig.MaxRetainedRecentEvents = 50

GiantLevelConfig.LevelThresholds = { 0, 100, 250, 500, 1000, 2000, 4000 }

GiantLevelConfig.EventKinds = {
	CaptureSuccess = "capture_success",
	ContainmentHeld = "containment_held",
	WorksiteUpgrade = "worksite_upgrade",
}

GiantLevelConfig.XpAwardsByEventKind = {
	capture_success = 25,
	containment_held = 40,
	worksite_upgrade = 15,
}

GiantLevelConfig.StateAttributes = {
	Xp = "GiantXp",
	Level = "GiantLevel",
	XpToNextLevel = "GiantXpToNextLevel",
}

return GiantLevelConfig
