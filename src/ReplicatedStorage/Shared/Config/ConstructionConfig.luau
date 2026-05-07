--!strict

local ConstructionConfig = {}

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

return ConstructionConfig
