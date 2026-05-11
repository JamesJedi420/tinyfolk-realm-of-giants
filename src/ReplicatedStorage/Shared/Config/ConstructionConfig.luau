--!strict

local ConstructionConfig: any = {}

ConstructionConfig.ConstructionSiteNamePrefix = "ConstructionSite_"
ConstructionConfig.DefaultConstructionSiteId = "ConstructionSite_A"

ConstructionConfig.InteractionRangeStuds = 16
ConstructionConfig.RequestCooldownSeconds = 0.2

ConstructionConfig.CostBySiteId = {
	ConstructionSite_A = {
		wood = 8,
		stone = 6,
	},
}

ConstructionConfig.DistrictDefaultCost = {
	wood = 10,
	stone = 8,
}

return ConstructionConfig
