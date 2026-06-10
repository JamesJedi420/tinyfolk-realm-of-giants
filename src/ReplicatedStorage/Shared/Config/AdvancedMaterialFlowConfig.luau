--!strict

local AdvancedMaterialFlowConfig: any = {}

AdvancedMaterialFlowConfig.SCHEMA_VERSION = 1

-- Session warehouse delivery grants inventory craft materials (not persisted).
AdvancedMaterialFlowConfig.InventoryGrantsByDeliveredMaterial = {
	Metal = {
		iron_filings = 1,
	},
	Stone = {
		stone_shard = 1,
	},
}

AdvancedMaterialFlowConfig.GrantUnitsPerDeliveredMaterial = {
	Metal = 1,
	Stone = 2,
}

return AdvancedMaterialFlowConfig
