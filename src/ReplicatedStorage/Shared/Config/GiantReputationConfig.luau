--!strict

local GiantReputationConfig: any = {}

GiantReputationConfig.MaxRetainedRecentEvents = 50

-- Rank thresholds: index is rank, value is minimum cumulative score.
GiantReputationConfig.RankThresholds = { 0, 50, 150, 300, 500, 800, 1200 }

GiantReputationConfig.RankTitlesByIndex = {
	"Unknown Giant",
	"Collector",
	"Custodian",
	"Warden",
	"Tyrant",
	"Sovereign",
	"Legend",
}

GiantReputationConfig.ScoreAwardsByTrophyKind = {
	capture_success = 15,
	containment_held = 20,
	containment_starvation = 10,
	containment_escape_failure = 25,
}

GiantReputationConfig.StateAttributes = {
	Score = "GiantReputationScore",
	Rank = "GiantReputationRank",
	RankTitle = "GiantReputationRankTitle",
	ScoreToNextRank = "GiantReputationScoreToNextRank",
	RankUpSignal = "GiantReputationRankUpSignal",
}

return GiantReputationConfig
