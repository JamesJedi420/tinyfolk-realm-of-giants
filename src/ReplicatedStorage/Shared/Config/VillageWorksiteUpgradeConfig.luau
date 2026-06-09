--!strict

local VillageWorksiteUpgradeConfig: any = {}

VillageWorksiteUpgradeConfig.MaxLevel = 3
VillageWorksiteUpgradeConfig.RequestCooldownSeconds = 0.25
VillageWorksiteUpgradeConfig.InteractionRangeStuds = 16

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
	warehouse = {
		[1] = { wood = 14, stone = 10, essence = 0 },
		[2] = { wood = 24, stone = 18, essence = 0 },
		[3] = { wood = 40, stone = 28, essence = 6 },
	},
	granary = {
		[1] = { wood = 12, stone = 8, essence = 0 },
		[2] = { wood = 22, stone = 16, essence = 0 },
		[3] = { wood = 36, stone = 26, essence = 5 },
	},
	shrine = {
		[1] = { wood = 10, stone = 6, essence = 4 },
		[2] = { wood = 18, stone = 12, essence = 8 },
		[3] = { wood = 30, stone = 20, essence = 12 },
	},
	farm = {
		[1] = { wood = 9, stone = 3, essence = 0 },
		[2] = { wood = 18, stone = 9, essence = 0 },
		[3] = { wood = 30, stone = 16, essence = 6 },
	},
	pen = {
		[1] = { wood = 11, stone = 5, essence = 0 },
		[2] = { wood = 20, stone = 12, essence = 0 },
		[3] = { wood = 32, stone = 20, essence = 5 },
	},
}

VillageWorksiteUpgradeConfig.ProductionMultipliersByLevel = {
	[0] = { perTick = 1, maxTotal = 1 },
	[1] = { perTick = 1.25, maxTotal = 1.25 },
	[2] = { perTick = 1.5, maxTotal = 1.5 },
	[3] = { perTick = 2, maxTotal = 2 },
}

VillageWorksiteUpgradeConfig.CapacityMultipliersByLevel = {
	[0] = { inTransit = 1, essenceMax = 1, heldCapacity = 1 },
	[1] = { inTransit = 1.25, essenceMax = 1.25, heldCapacity = 1.25 },
	[2] = { inTransit = 1.5, essenceMax = 1.5, heldCapacity = 1.5 },
	[3] = { inTransit = 2, essenceMax = 2, heldCapacity = 2 },
}

return VillageWorksiteUpgradeConfig
