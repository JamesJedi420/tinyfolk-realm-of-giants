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

RepeatedTargetingAbuseConfig.EventLogCategory = "repeated_targeting_abuse"

RepeatedTargetingAbuseConfig.StateAttributes = {
	AbuseFlag = "RepeatedTargetingAbuseFlag",
	AbusePattern = "RepeatedTargetingAbusePattern",
	AbuseEventCount = "RepeatedTargetingAbuseEventCount",
	AbuseLastAt = "RepeatedTargetingAbuseLastAt",
}

return RepeatedTargetingAbuseConfig
