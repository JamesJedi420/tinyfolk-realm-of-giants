--!strict

local CaptureConfig: any = {}

-- Request validation
CaptureConfig.RequestCooldownSeconds = 0.2
CaptureConfig.RejectRequestCooldownSeconds = 0.05
CaptureConfig.TriggerRadiusStuds = 14

-- Custody window: how long target remains in captured state before auto-release
CaptureConfig.CustodyWindowSeconds = 8

-- Custody timeout: prevent indefinite captivity beyond custody window
CaptureConfig.MaxCustodyDurationSeconds = 12

-- Reward anti-farming: repeated Giant/Tinyfolk pair rewards diminish within this window.
CaptureConfig.ContainmentRewardPairCooldownSeconds = 300

-- State attributes
CaptureConfig.StateAttributes = {
	CaptureActive = "CaptureActive",
	CaptureCustodianUserId = "CaptureCustodianUserId",
	CaptureExpiresAt = "CaptureExpiresAt",
	CaptureLastReason = "CaptureLastReason",
}

return CaptureConfig
