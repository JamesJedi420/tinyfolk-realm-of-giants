--!strict

local CaptureConfig = {}

-- Request validation
CaptureConfig.RequestCooldownSeconds = 0.2
CaptureConfig.TriggerRadiusStuds = 14

-- Custody window: how long target remains in captured state before auto-release
CaptureConfig.CustodyWindowSeconds = 8

-- Custody timeout: prevent indefinite captivity beyond custody window
CaptureConfig.MaxCustodyDurationSeconds = 12

-- State attributes
CaptureConfig.StateAttributes = {
	CaptureActive = "CaptureActive",
	CaptureCustodianUserId = "CaptureCustodianUserId",
	CaptureExpiresAt = "CaptureExpiresAt",
	CaptureLastReason = "CaptureLastReason",
}

return CaptureConfig
