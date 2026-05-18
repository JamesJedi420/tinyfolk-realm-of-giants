--!strict

local ScoreConfig: any = {}

ScoreConfig.MaxRecentEvents = 50

ScoreConfig.EventDefinitions = {
	escape_success = {
		category = "objective",
		basePoints = 100,
		decayWindowSeconds = 60,
		decayMultiplier = 0.5,
		minMultiplier = 0.25,
		repeatCap = 12,
		actorRole = "Tinyfolk",
	},
	rescue_complete = {
		category = "teamplay",
		basePoints = 80,
		decayWindowSeconds = 45,
		decayMultiplier = 0.5,
		minMultiplier = 0.25,
		repeatCap = 4,
		actorRole = "Tinyfolk",
	},
	capture_success = {
		category = "control",
		basePoints = 90,
		decayWindowSeconds = 45,
		decayMultiplier = 0.5,
		minMultiplier = 0.3,
		repeatCap = 5,
		actorRole = "Giant",
	},
	capture_release = {
		category = "control",
		basePoints = 40,
		decayWindowSeconds = 30,
		decayMultiplier = 0.5,
		minMultiplier = 0.25,
		repeatCap = 5,
		actorRole = "Giant",
	},
}

ScoreConfig.CategoryPointCaps = {
	objective = 500,
	teamplay = 400,
	control = 500,
}

ScoreConfig.StateAttributes = {
	ScoreTotal = "ScoreTotal",
	ScoreLastReason = "ScoreLastReason",
	ScoreObjective = "ScoreObjective",
	ScoreTeamplay = "ScoreTeamplay",
	ScoreControl = "ScoreControl",
}

return ScoreConfig
