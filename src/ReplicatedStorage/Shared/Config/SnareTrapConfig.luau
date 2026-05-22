--!strict

local SnareTrapConfig: any = {}

SnareTrapConfig.StructureId = "GiantStructure_Runtime_Snare_A"
SnareTrapConfig.NoBuildRadiusStuds = 18
SnareTrapConfig.TriggerRadiusStuds = 8
SnareTrapConfig.TriggerDurationSeconds = 30

SnareTrapConfig.Attributes = {
	Armed = "SnareTrapArmed",
	TriggeredAt = "SnareTrapTriggeredAt",
	TriggeredByUserId = "SnareTrapTriggeredByUserId",
	ExpiresAt = "SnareTrapExpiresAt",
	TriggerRadiusStuds = "SnareTrapTriggerRadiusStuds",
	PlacedAt = "SnareTrapPlacedAt",
}

return SnareTrapConfig
