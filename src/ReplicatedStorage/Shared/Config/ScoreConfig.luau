--!strict

local ScoreConfig: any = {}

ScoreConfig.MaxRecentEvents = 50

ScoreConfig.RewardBuckets = {
	Normal = "normal",
	Bonus = "bonus",
	Hidden = "hidden",
	Compensation = "compensation",
}

ScoreConfig.ScoreCategories = {
	objective = {
		displayName = "Objectives",
		roles = { "Tinyfolk" },
	},
	teamplay = {
		displayName = "Teamplay",
		roles = { "Tinyfolk" },
	},
	control = {
		displayName = "Control",
		roles = { "Giant" },
	},
}

ScoreConfig.EventDefinitions = {
	escape_success = {
		category = "objective",
		bucket = "normal",
		basePoints = 100,
		valueRule = "fixed",
		decayWindowSeconds = 60,
		decayMultiplier = 0.5,
		minMultiplier = 0.25,
		repeatCap = 12,
		actorRole = "Tinyfolk",
		feedbackKey = "score_escape_success",
	},
	rescue_complete = {
		category = "teamplay",
		bucket = "normal",
		basePoints = 80,
		valueRule = "fixed",
		decayWindowSeconds = 45,
		decayMultiplier = 0.5,
		minMultiplier = 0.25,
		repeatCap = 4,
		actorRole = "Tinyfolk",
		feedbackKey = "score_rescue_complete",
	},
	capture_success = {
		category = "control",
		bucket = "normal",
		basePoints = 90,
		valueRule = "fixed",
		decayWindowSeconds = 45,
		decayMultiplier = 0.5,
		minMultiplier = 0.3,
		repeatCap = 5,
		actorRole = "Giant",
		feedbackKey = "score_capture_success",
	},
	capture_release = {
		category = "control",
		bucket = "normal",
		basePoints = 40,
		valueRule = "fixed",
		decayWindowSeconds = 30,
		decayMultiplier = 0.5,
		minMultiplier = 0.25,
		repeatCap = 5,
		actorRole = "Giant",
		feedbackKey = "score_capture_release",
	},
	objective_partial = {
		category = "objective",
		bucket = "normal",
		basePoints = 60,
		valueRule = "proportional",
		contributionMetadataKey = "contributionRatio",
		minContribution = 0.25,
		maxContribution = 1,
		decayWindowSeconds = 30,
		decayMultiplier = 0.5,
		minMultiplier = 0.25,
		repeatCap = 8,
		actorRole = "Tinyfolk",
		feedbackKey = "score_objective_partial",
	},
	tutorial_bonus = {
		category = "objective",
		bucket = "bonus",
		basePoints = 200,
		valueRule = "fixed",
		decayWindowSeconds = 0,
		decayMultiplier = 1,
		minMultiplier = 1,
		repeatCap = 20,
		actorRole = "Tinyfolk",
		feedbackKey = "score_tutorial_bonus",
	},
	hidden_discovery = {
		category = "objective",
		bucket = "hidden",
		basePoints = 75,
		valueRule = "fixed",
		decayWindowSeconds = 0,
		decayMultiplier = 1,
		minMultiplier = 1,
		repeatCap = 20,
		actorRole = "Tinyfolk",
		feedbackKey = "score_hidden_discovery",
	},
	compensation_grant = {
		category = "teamplay",
		bucket = "compensation",
		basePoints = 150,
		valueRule = "fixed",
		decayWindowSeconds = 0,
		decayMultiplier = 1,
		minMultiplier = 1,
		repeatCap = 20,
		actorRole = "Tinyfolk",
		feedbackKey = "score_compensation_grant",
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
	ScoreLastFeedbackKey = "ScoreLastFeedbackKey",
	ScoreLastAwardedPoints = "ScoreLastAwardedPoints",
	ScoreLastBucket = "ScoreLastBucket",
	ScoreLastCategoryCapReached = "ScoreLastCategoryCapReached",
	ScoreObjective = "ScoreObjective",
	ScoreTeamplay = "ScoreTeamplay",
	ScoreControl = "ScoreControl",
}

return ScoreConfig
