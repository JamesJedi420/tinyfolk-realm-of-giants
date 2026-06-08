--!strict

local VillageWorksiteUpgradeConfig: any = {}

VillageWorksiteUpgradeConfig.MaxLevel = 3
VillageWorksiteUpgradeConfig.RequestCooldownSeconds = 0.25

VillageWorksiteUpgradeConfig.UpgradeCostsByKindAndLevel = {
	work_station = {
		[1] = { wood = 10, stone = 4, essence = 0 },
		[2] = { wood = 20, stone = 10, essence = 0 },
		[3] = { wood = 35, stone = 18, essence = 8 },
	},
	mining_station = {
		[1] = { wood = 8, stone = 6, essence = 0 },
		[2] = { wood = 16, stone = 14, essence = 0 },
		[3] = { wood = 28, stone = 24, essence = 6 },
	},
}

VillageWorksiteUpgradeConfig.ProductionMultipliersByLevel = {
	[0] = { perTick = 1, maxTotal = 1 },
	[1] = { perTick = 1.25, maxTotal = 1.25 },
	[2] = { perTick = 1.5, maxTotal = 1.5 },
	[3] = { perTick = 2, maxTotal = 2 },
}

return VillageWorksiteUpgradeConfig
