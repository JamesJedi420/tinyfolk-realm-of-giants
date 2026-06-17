--!strict

local PartyMatchmakingQueueConfig: any = {}

PartyMatchmakingQueueConfig.RequestCooldownSeconds = 0.5
PartyMatchmakingQueueConfig.PollCoalesceSeconds = 1.0
PartyMatchmakingQueueConfig.DefaultTimeoutSeconds = 300
PartyMatchmakingQueueConfig.MaxTimeoutSeconds = 300
PartyMatchmakingQueueConfig.ProcessBatchSize = 25
PartyMatchmakingQueueConfig.ProcessIntervalSeconds = 1
PartyMatchmakingQueueConfig.OperationIdPrefix = "party_matchmaking_"
PartyMatchmakingQueueConfig.RaidBoardPartyIdPrefix = "raid_board:"

PartyMatchmakingQueueConfig.Activities = {
	Raid = "raid",
	Rescue = "rescue",
	Scouting = "scouting",
	WorkContract = "work_contract",
}

PartyMatchmakingQueueConfig.Remotes = {
	EnqueueRequest = "PartyMatchmakingEnqueueRequest",
	EnqueueResponse = "PartyMatchmakingEnqueueResponse",
	PollRequest = "PartyMatchmakingPollRequest",
	PollResponse = "PartyMatchmakingPollResponse",
	Notify = "PartyMatchmakingNotify",
}

PartyMatchmakingQueueConfig.HubAnchorPrefix = "PartyMatchmakingHub_"
PartyMatchmakingQueueConfig.DefaultHubAnchorId = "PartyMatchmakingHub_A"
PartyMatchmakingQueueConfig.InteractionRangeStuds = 16
PartyMatchmakingQueueConfig.OpenRequestAttribute = "PartyMatchmakingOpenRequested"
PartyMatchmakingQueueConfig.DebugOpenKeyName = "M"

return PartyMatchmakingQueueConfig
