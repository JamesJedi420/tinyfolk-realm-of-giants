--!strict

local TinyfolkLaborUpgradeConfig: any = {}

TinyfolkLaborUpgradeConfig.BenchNamePrefix = "TinyfolkLaborBench_"
TinyfolkLaborUpgradeConfig.DefaultHaulBenchId = "TinyfolkLaborBench_Haul_A"
TinyfolkLaborUpgradeConfig.DefaultPaceBenchId = "TinyfolkLaborBench_Pace_A"
TinyfolkLaborUpgradeConfig.InteractionRangeStuds = 14
TinyfolkLaborUpgradeConfig.RequestCooldownSeconds = 0.25
TinyfolkLaborUpgradeConfig.MaxLevel = 2
TinyfolkLaborUpgradeConfig.TokensPerWorkAction = 1

TinyfolkLaborUpgradeConfig.Tracks = {
	HaulYield = "haul_yield",
	TaskPace = "task_pace",
}

TinyfolkLaborUpgradeConfig.TrackByBenchId = {
	[TinyfolkLaborUpgradeConfig.DefaultHaulBenchId] = TinyfolkLaborUpgradeConfig.Tracks.HaulYield,
	[TinyfolkLaborUpgradeConfig.DefaultPaceBenchId] = TinyfolkLaborUpgradeConfig.Tracks.TaskPace,
}

TinyfolkLaborUpgradeConfig.UpgradeCostsByTrackAndLevel = {
	haul_yield = {
		[1] = { laborTokens = 3 },
		[2] = { laborTokens = 6 },
	},
	task_pace = {
		[1] = { food = 4 },
		[2] = { food = 8 },
	},
}

TinyfolkLaborUpgradeConfig.HaulYieldMultiplierByLevel = {
	[0] = 1,
	[1] = 1.25,
	[2] = 1.5,
}

TinyfolkLaborUpgradeConfig.TaskPaceMultiplierByLevel = {
	[0] = 1,
	[1] = 0.85,
	[2] = 0.7,
}

TinyfolkLaborUpgradeConfig.LaborTokensAttribute = "TinyfolkLaborTokens"
TinyfolkLaborUpgradeConfig.HaulYieldLevelAttribute = "TinyfolkLaborHaulYieldLevel"
TinyfolkLaborUpgradeConfig.TaskPaceLevelAttribute = "TinyfolkLaborTaskPaceLevel"
TinyfolkLaborUpgradeConfig.LastReasonAttribute = "TinyfolkLaborUpgradeLastReason"
TinyfolkLaborUpgradeConfig.EffectiveHaulYieldMultiplierAttribute = "TinyfolkLaborEffectiveHaulYieldMultiplier"
TinyfolkLaborUpgradeConfig.EffectiveTaskPaceMultiplierAttribute = "TinyfolkLaborEffectiveTaskPaceMultiplier"

return TinyfolkLaborUpgradeConfig
