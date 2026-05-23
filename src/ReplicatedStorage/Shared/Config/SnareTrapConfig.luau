--!strict

local SnareTrapConfig: any = {}

SnareTrapConfig.StructureId = "GiantStructure_Runtime_Snare_A"
SnareTrapConfig.NoBuildRadiusStuds = 18
SnareTrapConfig.TriggerRadiusStuds = 8
SnareTrapConfig.TriggerDurationSeconds = 30
SnareTrapConfig.MaxActiveTrapsPerGiant = 3
SnareTrapConfig.PlacementRechargeSeconds = 10
SnareTrapConfig.InteractionDurationSeconds = 2
SnareTrapConfig.InteractionRadiusStuds = 10
SnareTrapConfig.CoarseAlertGridSizeStuds = 50

SnareTrapConfig.Attributes = {
	TrapId = "SnareTrapId",
	Status = "SnareTrapStatus",
	Armed = "SnareTrapArmed",
	TriggeredAt = "SnareTrapTriggeredAt",
	TriggeredByUserId = "SnareTrapTriggeredByUserId",
	ResolvedAt = "SnareTrapResolvedAt",
	ResolvedByUserId = "SnareTrapResolvedByUserId",
	ExpiresAt = "SnareTrapExpiresAt",
	TriggerRadiusStuds = "SnareTrapTriggerRadiusStuds",
	PlacedAt = "SnareTrapPlacedAt",
}

return SnareTrapConfig
