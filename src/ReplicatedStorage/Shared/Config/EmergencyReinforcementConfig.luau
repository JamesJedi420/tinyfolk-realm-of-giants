--!strict

local EmergencyReinforcementConfig: any = {}

EmergencyReinforcementConfig.RequestCooldownSeconds = 0.25
EmergencyReinforcementConfig.RejectRequestCooldownSeconds = 0.05
EmergencyReinforcementConfig.CallCooldownSeconds = 45
EmergencyReinforcementConfig.SpawnPlacementRetryCount = 10
EmergencyReinforcementConfig.ActiveTinyfolkThreshold = 2
EmergencyReinforcementConfig.MinMatchElapsedSeconds = 45
EmergencyReinforcementConfig.ObjectiveTriggerRadiusStuds = 18

EmergencyReinforcementConfig.CallCenterObjectiveId = "CallCenter_A"
EmergencyReinforcementConfig.ObjectiveFolderPath = { "Map", "Objectives" }
EmergencyReinforcementConfig.SpawnFolderPath = { "Map", "Spawns" }
EmergencyReinforcementConfig.ReinforcementSpawnName = "ReinforcementSpawn"
EmergencyReinforcementConfig.FallbackSpawnName = "TinyfolkSpawn"

EmergencyReinforcementConfig.DefaultReinforcementClass = "Private"
EmergencyReinforcementConfig.DefaultLoadoutPreset = "Army"

EmergencyReinforcementConfig.StateAttributes = {
	Available = "EmergencyReinforcementAvailable",
	Used = "EmergencyReinforcementUsed",
	CooldownEndsAt = "EmergencyReinforcementCooldownEndsAt",
	CallStartedAt = "EmergencyReinforcementCallStartedAt",
	TriggeredByUserId = "EmergencyReinforcementTriggeredByUserId",
	SpawnedUserId = "EmergencyReinforcementSpawnedUserId",
	LastReason = "EmergencyReinforcementLastReason",
	ActiveTinyfolkCount = "EmergencyReinforcementActiveTinyfolkCount",
	ReadinessReason = "EmergencyReinforcementReadinessReason",
}

return EmergencyReinforcementConfig
