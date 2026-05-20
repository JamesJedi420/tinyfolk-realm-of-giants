--!strict

local RescueContractConfig: any = {}

RescueContractConfig.RequestCooldownSeconds = 0.2
RescueContractConfig.RejectRequestCooldownSeconds = 0.05
RescueContractConfig.RescueWindowSeconds = 12
RescueContractConfig.TriggerRadiusStuds = 14
RescueContractConfig.PostRescueProtectionSeconds = 4
RescueContractConfig.RescueAccelerationDurationSeconds = 20
RescueContractConfig.RescueAccelerationWindowBonusSeconds = 3
RescueContractConfig.TargetRealmOwnerUserIdAttribute = "GiantRealmOwnerUserId"
RescueContractConfig.TargetRealmIdAttribute = "GiantRealmId"
RescueContractConfig.RescueEntryRouteAttribute = "RescueEntryRoute"
RescueContractConfig.RescueEntryRouteKind = "RescueEntry"
RescueContractConfig.QueueRewardHint = "rescue_contract"
RescueContractConfig.QueueDangerRating = 0.5

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
	RescueAccelerationActive = "RescueAccelerationActive",
	RescueAccelerationExpiresAt = "RescueAccelerationExpiresAt",
}

return RescueContractConfig
