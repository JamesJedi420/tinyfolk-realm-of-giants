--!strict

local RescueContractConfig: any = {}

RescueContractConfig.RequestCooldownSeconds = 0.2
RescueContractConfig.RejectRequestCooldownSeconds = 0.05
RescueContractConfig.RescueWindowSeconds = 12
RescueContractConfig.TriggerRadiusStuds = 14
RescueContractConfig.PostRescueProtectionSeconds = 4
RescueContractConfig.PostRescueMovementSpeedMultiplier = 1.15
RescueContractConfig.PostRescueEscapeCooldownMultiplier = 0.5
RescueContractConfig.RescueAccelerationDurationSeconds = 20
RescueContractConfig.RescueAccelerationWindowBonusSeconds = 3
RescueContractConfig.TargetRealmOwnerUserIdAttribute = "GiantRealmOwnerUserId"
RescueContractConfig.TargetRealmIdAttribute = "GiantRealmId"
RescueContractConfig.RescueEntryRouteAttribute = "RescueEntryRoute"
RescueContractConfig.RescueEntryRouteKind = "RescueEntry"
RescueContractConfig.QueueRewardHint = "rescue_contract"
RescueContractConfig.QueueDangerRating = 0.5
RescueContractConfig.RefreshCoalesceSeconds = 1
RescueContractConfig.ReconcileBatchSize = 50
RescueContractConfig.DefaultListLimit = 20
RescueContractConfig.MaxListLimit = 50
RescueContractConfig.HubRequestCooldownSeconds = 0.5

RescueContractConfig.BoardNamePrefix = "RescueContractBoardHub_"
RescueContractConfig.DefaultBoardId = "RescueContractBoardHub_A"
RescueContractConfig.InteractionRangeStuds = 16
RescueContractConfig.OpenRequestAttribute = "RescueContractBoardOpenRequested"
RescueContractConfig.DebugOpenKeyName = "R"

RescueContractConfig.Remotes = {
	Notify = "RescueContractHubNotify",
	ListRequest = "RescueContractBoardListRequest",
	ListResponse = "RescueContractBoardListResponse",
	AcceptRequest = "RescueContractBoardAcceptRequest",
	AcceptResponse = "RescueContractBoardAcceptResponse",
}

RescueContractConfig.RewardTierBuckets = {
	{ minDanger = 0.75, label = "High Risk" },
	{ minDanger = 0.5, label = "Elevated" },
	{ minDanger = 0.25, label = "Moderate" },
	{ minDanger = 0.0, label = "Lower" },
}

RescueContractConfig.StateAttributes = {
	RescueActive = "RescueContractActive",
	RescueTargetUserId = "RescueContractTargetUserId",
	RescueRescuerUserId = "RescueContractRescuerUserId",
	RescueTargetRealmOwnerUserId = "RescueContractTargetRealmOwnerUserId",
	RescueEntryRouteId = "RescueContractEntryRouteId",
	RescueEntryRouteKind = "RescueContractEntryRouteKind",
	RescueExpiresAt = "RescueContractExpiresAt",
	RescueLastReason = "RescueContractLastReason",
	PostRescueProtected = "PostRescueProtected",
	PostRescueProtectionExpiresAt = "PostRescueProtectionExpiresAt",
	PostRescueMovementSpeedMultiplier = "PostRescueMovementSpeedMultiplier",
	RescueAccelerationActive = "RescueAccelerationActive",
	RescueAccelerationExpiresAt = "RescueAccelerationExpiresAt",
}

return RescueContractConfig
