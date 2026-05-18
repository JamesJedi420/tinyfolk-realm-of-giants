--!strict

local RescueContractConfig: any = {}

RescueContractConfig.RequestCooldownSeconds = 0.2
RescueContractConfig.RescueWindowSeconds = 12
RescueContractConfig.TriggerRadiusStuds = 14

RescueContractConfig.StateAttributes = {
	RescueActive = "RescueContractActive",
	RescueTargetUserId = "RescueContractTargetUserId",
	RescueRescuerUserId = "RescueContractRescuerUserId",
	RescueExpiresAt = "RescueContractExpiresAt",
	RescueLastReason = "RescueContractLastReason",
}

return RescueContractConfig
