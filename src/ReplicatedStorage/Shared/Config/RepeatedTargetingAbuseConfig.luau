--!strict

local RepeatedTargetingAbuseConfig: any = {}

RepeatedTargetingAbuseConfig.PairRepeatWindowSeconds = 300
RepeatedTargetingAbuseConfig.PairRepeatCaptureThreshold = 3

RepeatedTargetingAbuseConfig.TargetCustodyLoopWindowSeconds = 180
RepeatedTargetingAbuseConfig.TargetCustodyLoopThreshold = 5

RepeatedTargetingAbuseConfig.TransferLoopWindowSeconds = 120
RepeatedTargetingAbuseConfig.TransferLoopThreshold = 2

RepeatedTargetingAbuseConfig.ShortCycleWindowSeconds = 300
RepeatedTargetingAbuseConfig.ShortCycleMaxSeconds = 15
RepeatedTargetingAbuseConfig.ShortCycleThreshold = 3

RepeatedTargetingAbuseConfig.DetectionLogCooldownSeconds = 60
RepeatedTargetingAbuseConfig.MaxSuspiciousLoopRecords = 50

RepeatedTargetingAbuseConfig.CustodyBlockDurationSeconds = 120
RepeatedTargetingAbuseConfig.RewardDampeningWindowSeconds = 300

RepeatedTargetingAbuseConfig.RewardDampeningMultipliers = {
	pair_repeat_targeting = 0.5,
	target_custody_loop = 0.5,
	custody_transfer_loop = 0.25,
	short_custody_cycle = 0.5,
	pair_reward_cap_reached = 0,
}

RepeatedTargetingAbuseConfig.CustodyBlockPatterns = {
	pair_repeat_targeting = true,
	target_custody_loop = true,
	custody_transfer_loop = true,
	short_custody_cycle = true,
}

RepeatedTargetingAbuseConfig.EventLogCategory = "repeated_targeting_abuse"

RepeatedTargetingAbuseConfig.StateAttributes = {
	AbuseFlag = "RepeatedTargetingAbuseFlag",
	AbusePattern = "RepeatedTargetingAbusePattern",
	AbuseEventCount = "RepeatedTargetingAbuseEventCount",
	AbuseLastAt = "RepeatedTargetingAbuseLastAt",
	CustodyBlockActive = "RepeatedTargetingAbuseCustodyBlockActive",
	CustodyBlockExpiresAt = "RepeatedTargetingAbuseCustodyBlockExpiresAt",
	CustodyBlockPattern = "RepeatedTargetingAbuseCustodyBlockPattern",
	RewardDampeningMultiplier = "RepeatedTargetingAbuseRewardDampeningMultiplier",
}

return RepeatedTargetingAbuseConfig
