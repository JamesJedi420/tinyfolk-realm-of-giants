--!strict

local RaidBoardConfig: any = {}

RaidBoardConfig.RequestCooldownSeconds = 0.5
RaidBoardConfig.RefreshCoalesceSeconds = 1.0
RaidBoardConfig.DefaultListLimit = 20
RaidBoardConfig.MaxListLimit = 50
RaidBoardConfig.OwnerDisplayNameCacheMax = 64
RaidBoardConfig.PartyIdPrefix = "raid_board:"

RaidBoardConfig.BoardNamePrefix = "RaidBoardHub_"
RaidBoardConfig.DefaultBoardId = "RaidBoardHub_A"
RaidBoardConfig.InteractionRangeStuds = 16
RaidBoardConfig.OpenRequestAttribute = "RaidBoardOpenRequested"

RaidBoardConfig.Remotes = {
	ListRequest = "RaidBoardListRequest",
	ListResponse = "RaidBoardListResponse",
	QueueRequest = "RaidBoardQueueRequest",
	QueueResponse = "RaidBoardQueueResponse",
	Notify = "RaidBoardNotify",
}

RaidBoardConfig.EntryTypeLabels = {
	public = "Raid",
	raid_enabled = "Raid Open",
}

RaidBoardConfig.RewardTierBuckets = {
	{ minDanger = 0.75, label = "Legendary" },
	{ minDanger = 0.5, label = "High" },
	{ minDanger = 0.25, label = "Moderate" },
	{ minDanger = 0.0, label = "Low" },
}

RaidBoardConfig.DebugOpenKeyName = "B"

return RaidBoardConfig
