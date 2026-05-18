--!strict

local RescueContractConfig: any = {}

RescueContractConfig.RequestCooldownSeconds = 0.2
RescueContractConfig.RescueWindowSeconds = 12
RescueContractConfig.TriggerRadiusStuds = 14
RescueContractConfig.PostRescueProtectionSeconds = 4

RescueContractConfig.StateAttributes = {
	RescueActive = "RescueContractActive",
	RescueTargetUserId = "RescueContractTargetUserId",
	RescueRescuerUserId = "RescueContractRescuerUserId",
	RescueExpiresAt = "RescueContractExpiresAt",
	RescueLastReason = "RescueContractLastReason",
	PostRescueProtected = "PostRescueProtected",
	PostRescueProtectionExpiresAt = "PostRescueProtectionExpiresAt",
}

return RescueContractConfig
