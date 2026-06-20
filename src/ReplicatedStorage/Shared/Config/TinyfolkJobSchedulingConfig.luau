--!strict

local TinyfolkJobSchedulingConfig: any = {}

TinyfolkJobSchedulingConfig.ProcessIntervalSeconds = 2
TinyfolkJobSchedulingConfig.MaxAssignmentsPerTick = 8
TinyfolkJobSchedulingConfig.UseDyadicWorkerRanking = true

TinyfolkJobSchedulingConfig.JobKinds = {
	None = "none",
	SpecialistProduction = "specialist_production",
	GeneralHaul = "general_haul",
}

TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute = "TinyfolkScheduledJobKind"
TinyfolkJobSchedulingConfig.ScheduledJobDemandIdAttribute = "TinyfolkScheduledJobDemandId"
TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute = "TinyfolkScheduledJobStationId"
TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute = "TinyfolkScheduledJobMaterial"
TinyfolkJobSchedulingConfig.ScheduledJobLastReasonAttribute = "TinyfolkScheduledJobLastReason"
TinyfolkJobSchedulingConfig.ScheduledJobUpdatedAtAttribute = "TinyfolkScheduledJobUpdatedAt"

TinyfolkJobSchedulingConfig.HaulMaterials = { "Wood", "Stone", "Food", "Metal" }

TinyfolkJobSchedulingConfig.SourceStationIdByMaterial = {
	Wood = "WorkStation_A",
	Stone = "MiningStation_A",
	Food = "Farm_A",
	Metal = "Forge_A",
}

TinyfolkJobSchedulingConfig.SpecialistDemandPriority = 100
TinyfolkJobSchedulingConfig.HaulDemandPriority = 50

TinyfolkJobSchedulingConfig.ShrineSpecialistDemands = {
	{
		shrineId = "Shrine_A",
		requiredSpecialistRole = "Worshipper",
	},
}

TinyfolkJobSchedulingConfig.DebugRequestRemoteName = "TinyfolkJobSchedulingDebugRequest"
TinyfolkJobSchedulingConfig.DebugResponseRemoteName = "TinyfolkJobSchedulingDebugResponse"

return TinyfolkJobSchedulingConfig
