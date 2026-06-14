--!strict

type GiantStructureDefinition = {
	displayName: string,
	category: string,
	woodCost: number,
	stoneCost: number,
}

local GiantStructureCatalog: { [string]: GiantStructureDefinition } = {
	GiantStructure_Runtime_A = {
		displayName = "Runtime Test Structure A",
		category = "utility",
		woodCost = 12,
		stoneCost = 8,
	},
	GiantStructure_Runtime_B = {
		displayName = "Runtime Test Structure B",
		category = "defensive",
		woodCost = 16,
		stoneCost = 10,
	},
	GiantStructure_Runtime_Snare_A = {
		displayName = "Runtime Test Snare Challenge A",
		category = "trap",
		woodCost = 10,
		stoneCost = 4,
	},
	GiantStructure_Containment_Cage_A = {
		displayName = "Containment Cage",
		category = "containment",
		woodCost = 20,
		stoneCost = 12,
	},
	GiantStructure_Containment_Jar_A = {
		displayName = "Containment Jar",
		category = "containment",
		woodCost = 14,
		stoneCost = 6,
	},
}

for structureId, definition in pairs(GiantStructureCatalog) do
	assert(type(structureId) == "string" and structureId ~= "", "invalid giant structure catalog key")
	assert(
		type(definition) == "table",
		string.format("invalid giant structure catalog entry structureId=%s", structureId)
	)
	assert(
		type(definition.displayName) == "string" and definition.displayName ~= "",
		string.format("invalid giant structure displayName structureId=%s", structureId)
	)
	assert(
		type(definition.category) == "string" and definition.category ~= "",
		string.format("invalid giant structure category structureId=%s", structureId)
	)
	assert(
		type(definition.woodCost) == "number" and definition.woodCost >= 0,
		string.format("invalid giant structure woodCost structureId=%s", structureId)
	)
	assert(
		type(definition.stoneCost) == "number" and definition.stoneCost >= 0,
		string.format("invalid giant structure stoneCost structureId=%s", structureId)
	)
end

return GiantStructureCatalog
