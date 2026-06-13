--!strict

local CaptureConfig: any = {}

-- Request validation
CaptureConfig.RequestCooldownSeconds = 0.2
CaptureConfig.RejectRequestCooldownSeconds = 0.05
CaptureConfig.TriggerRadiusStuds = 14

-- Base concurrent custody slots per Giant custodian; pen upgrades scale via held-capacity multipliers.
CaptureConfig.BaseMaxConcurrentCapturesPerCustodian = 1

-- Custody window: how long target remains in captured state before auto-release
CaptureConfig.CustodyWindowSeconds = 8

-- Custody timeout: prevent indefinite captivity beyond custody window
CaptureConfig.MaxCustodyDurationSeconds = 12
CaptureConfig.MaxCapturedDurationSeconds = 12
CaptureConfig.MaxContainedDurationSeconds = 12

-- Reward anti-farming: repeated Giant/Tinyfolk pair rewards diminish within this window.
CaptureConfig.ContainmentRewardPairCooldownSeconds = 300

-- Captivity struggle / escape progress minigame (TIN-85)
CaptureConfig.StruggleProgressRequired = 5
CaptureConfig.StruggleProgressPerAction = 1
CaptureConfig.StruggleActionCooldownSeconds = 0.35
CaptureConfig.AllyAssistProgressBonus = 1
CaptureConfig.AllyAssistCooldownSeconds = 0.5
CaptureConfig.StruggleProgressDecayIntervalSeconds = 2.5
CaptureConfig.StruggleProgressDecayAmount = 1
CaptureConfig.StruggleAllyRadiusStuds = 14
CaptureConfig.StruggleAllyProgressBonusPerAlly = 1
CaptureConfig.ContainmentZoneNamePrefix = "GiantCaptureZone_"
CaptureConfig.ContainmentZoneFolderPath = { "Map", "CaptureZones" }

-- State attributes
CaptureConfig.StateAttributes = {
	CaptureActive = "CaptureActive",
	CaptureCustodianUserId = "CaptureCustodianUserId",
	CaptureExpiresAt = "CaptureExpiresAt",
	CaptureLastReason = "CaptureLastReason",
	CaptivityEscapeProgress = "CaptivityEscapeProgress",
	CaptivityEscapeProgressRequired = "CaptivityEscapeProgressRequired",
	CaptivityEscapeSuppressed = "CaptivityEscapeSuppressed",
	CaptivityEscapeLastReason = "CaptivityEscapeLastReason",
}

return CaptureConfig
