--!strict

local InventoryCraftConfig: any = {}

export type ItemKind = "material" | "crafted"
export type ItemRecord = {
	itemId: string,
	displayName: string,
	kind: ItemKind,
	maxStack: number,
	sourceId: string,
}
export type RecipeRecord = {
	recipeId: string,
	displayName: string,
	requiredRole: string,
	inputs: { [string]: number },
	outputs: { [string]: number },
	sourceId: string,
}

InventoryCraftConfig.SCHEMA_VERSION = 1
InventoryCraftConfig.CATALOG_VERSION = "inventory_craft_v2"

InventoryCraftConfig.Roles = {
	Tinyfolk = "Tinyfolk",
}

InventoryCraftConfig.ItemKinds = {
	Material = "material",
	Crafted = "crafted",
}

InventoryCraftConfig.Attributes = {
	ItemCount = "InventoryItemCount",
	CraftedTotal = "InventoryCraftedTotal",
	CraftableRecipeCount = "InventoryCraftableRecipeCount",
	LastCraftRecipeId = "InventoryLastCraftRecipeId",
	LastCraftAt = "InventoryLastCraftAt",
	LastReason = "InventoryLastReason",
}

InventoryCraftConfig.TEST_STARTING_ITEMS = {
	raw_fiber = 4,
	wood_scrap = 3,
	stone_shard = 3,
	plant_resin = 2,
	iron_filings = 2,
	cloth_patch = 2,
}

InventoryCraftConfig.DEFAULT_ITEM_CATALOG = {
	{
		itemId = "raw_fiber",
		displayName = "Raw Fiber",
		kind = "material",
		maxStack = 99,
		sourceId = "tin22_raw_fiber",
	},
	{
		itemId = "wood_scrap",
		displayName = "Wood Scrap",
		kind = "material",
		maxStack = 99,
		sourceId = "tin22_wood_scrap",
	},
	{
		itemId = "stone_shard",
		displayName = "Stone Shard",
		kind = "material",
		maxStack = 99,
		sourceId = "tin22_stone_shard",
	},
	{
		itemId = "twine_satchel",
		displayName = "Twine Satchel",
		kind = "crafted",
		maxStack = 10,
		sourceId = "tin22_twine_satchel",
	},
	{
		itemId = "repair_wedge",
		displayName = "Repair Wedge",
		kind = "crafted",
		maxStack = 10,
		sourceId = "tin22_repair_wedge",
	},
	{
		itemId = "plant_resin",
		displayName = "Plant Resin",
		kind = "material",
		maxStack = 99,
		sourceId = "tin40_plant_resin",
	},
	{
		itemId = "iron_filings",
		displayName = "Iron Filings",
		kind = "material",
		maxStack = 99,
		sourceId = "tin40_iron_filings",
	},
	{
		itemId = "cloth_patch",
		displayName = "Cloth Patch",
		kind = "material",
		maxStack = 99,
		sourceId = "tin40_cloth_patch",
	},
	{
		itemId = "smoke_pouch",
		displayName = "Smoke Pouch",
		kind = "crafted",
		maxStack = 10,
		sourceId = "tin40_smoke_pouch",
	},
	{
		itemId = "rope_anchor",
		displayName = "Rope Anchor",
		kind = "crafted",
		maxStack = 10,
		sourceId = "tin40_rope_anchor",
	},
	{
		itemId = "field_kit",
		displayName = "Field Kit",
		kind = "crafted",
		maxStack = 10,
		sourceId = "tin40_field_kit",
	},
	{
		itemId = "spike_wedge",
		displayName = "Spike Wedge",
		kind = "crafted",
		maxStack = 10,
		sourceId = "tin40_spike_wedge",
	},
}

InventoryCraftConfig.DEFAULT_RECIPE_CATALOG = {
	{
		recipeId = "craft_twine_satchel",
		displayName = "Twine Satchel",
		requiredRole = "Tinyfolk",
		inputs = {
			raw_fiber = 2,
			wood_scrap = 1,
		},
		outputs = {
			twine_satchel = 1,
		},
		sourceId = "tin22_recipe_twine_satchel",
	},
	{
		recipeId = "craft_repair_wedge",
		displayName = "Repair Wedge",
		requiredRole = "Tinyfolk",
		inputs = {
			stone_shard = 2,
			wood_scrap = 1,
		},
		outputs = {
			repair_wedge = 1,
		},
		sourceId = "tin22_recipe_repair_wedge",
	},
	{
		recipeId = "craft_smoke_pouch",
		displayName = "Smoke Pouch",
		requiredRole = "Tinyfolk",
		inputs = {
			raw_fiber = 1,
			plant_resin = 2,
		},
		outputs = {
			smoke_pouch = 1,
		},
		sourceId = "tin40_recipe_smoke_pouch",
	},
	{
		recipeId = "craft_rope_anchor",
		displayName = "Rope Anchor",
		requiredRole = "Tinyfolk",
		inputs = {
			twine_satchel = 1,
			plant_resin = 1,
			wood_scrap = 1,
		},
		outputs = {
			rope_anchor = 1,
		},
		sourceId = "tin40_recipe_rope_anchor",
	},
	{
		recipeId = "craft_field_kit",
		displayName = "Field Kit",
		requiredRole = "Tinyfolk",
		inputs = {
			twine_satchel = 1,
			cloth_patch = 2,
			wood_scrap = 1,
		},
		outputs = {
			field_kit = 1,
		},
		sourceId = "tin40_recipe_field_kit",
	},
	{
		recipeId = "craft_spike_wedge",
		displayName = "Spike Wedge",
		requiredRole = "Tinyfolk",
		inputs = {
			repair_wedge = 1,
			stone_shard = 1,
			iron_filings = 2,
		},
		outputs = {
			spike_wedge = 1,
		},
		sourceId = "tin40_recipe_spike_wedge",
	},
} :: { RecipeRecord }

local VALID_ITEM_KINDS = {
	material = true,
	crafted = true,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value == math.floor(value)
end

local function validateItemRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "item_record_invalid"
	end
	if type(record.itemId) ~= "string" or record.itemId == "" then
		return false, "item_id_invalid"
	end
	if type(record.displayName) ~= "string" or record.displayName == "" then
		return false, "item_display_name_invalid"
	end
	if VALID_ITEM_KINDS[record.kind] ~= true then
		return false, "item_kind_invalid"
	end
	if not isPositiveInteger(record.maxStack) then
		return false, "item_max_stack_invalid"
	end
	if type(record.sourceId) ~= "string" or record.sourceId == "" then
		return false, "item_source_id_invalid"
	end
	return true, nil
end

local function validateRecipeRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "recipe_record_invalid"
	end
	if type(record.recipeId) ~= "string" or record.recipeId == "" then
		return false, "recipe_id_invalid"
	end
	if type(record.displayName) ~= "string" or record.displayName == "" then
		return false, "recipe_display_name_invalid"
	end
	if type(record.requiredRole) ~= "string" or record.requiredRole == "" then
		return false, "recipe_required_role_invalid"
	end
	if type(record.inputs) ~= "table" then
		return false, "recipe_inputs_invalid"
	end
	if type(record.outputs) ~= "table" then
		return false, "recipe_outputs_invalid"
	end

	for itemId, count in pairs(record.inputs) do
		if type(itemId) ~= "string" or itemId == "" or not isPositiveInteger(count) then
			return false, "recipe_input_invalid"
		end
	end

	local hasOutput = false
	for itemId, count in pairs(record.outputs) do
		if type(itemId) ~= "string" or itemId == "" or not isPositiveInteger(count) then
			return false, "recipe_output_invalid"
		end
		hasOutput = true
	end
	if not hasOutput then
		return false, "recipe_outputs_empty"
	end

	if type(record.sourceId) ~= "string" or record.sourceId == "" then
		return false, "recipe_source_id_invalid"
	end

	return true, nil
end

local function buildItemIndex(catalog: { ItemRecord }): { [string]: ItemRecord }
	local index: { [string]: ItemRecord } = {}
	for _, record in ipairs(catalog) do
		local valid, _reason = validateItemRecord(record)
		if valid then
			index[record.itemId] = record
		end
	end
	return index
end

local function buildRecipeIndex(catalog: { RecipeRecord }): { [string]: RecipeRecord }
	local index: { [string]: RecipeRecord } = {}
	for _, record in ipairs(catalog) do
		local valid, _reason = validateRecipeRecord(record)
		if valid then
			index[record.recipeId] = record
		end
	end
	return index
end

function InventoryCraftConfig.GetAllItemRecords(catalogOverride: any?): { ItemRecord }
	if type(catalogOverride) == "table" then
		return catalogOverride
	end
	return InventoryCraftConfig.DEFAULT_ITEM_CATALOG
end

function InventoryCraftConfig.GetAllRecipeRecords(catalogOverride: any?): { RecipeRecord }
	if type(catalogOverride) == "table" then
		return catalogOverride
	end
	return InventoryCraftConfig.DEFAULT_RECIPE_CATALOG
end

function InventoryCraftConfig.GetItemRecord(itemId: any, catalogOverride: any?): (ItemRecord?, string?)
	if type(itemId) ~= "string" or itemId == "" then
		return nil, "item_id_invalid"
	end

	local record = buildItemIndex(InventoryCraftConfig.GetAllItemRecords(catalogOverride))[itemId]
	if record == nil then
		return nil, "item_missing"
	end
	return record, nil
end

function InventoryCraftConfig.GetRecipeRecord(recipeId: any, catalogOverride: any?): (RecipeRecord?, string?)
	if type(recipeId) ~= "string" or recipeId == "" then
		return nil, "recipe_id_invalid"
	end

	local record = buildRecipeIndex(InventoryCraftConfig.GetAllRecipeRecords(catalogOverride))[recipeId]
	if record == nil then
		return nil, "recipe_missing"
	end
	return record, nil
end

function InventoryCraftConfig.ValidateItemCatalog(catalog: any): (boolean, string?)
	if type(catalog) ~= "table" then
		return false, "item_catalog_invalid"
	end

	local seen: { [string]: boolean } = {}
	for index, record in ipairs(catalog) do
		local valid, reason = validateItemRecord(record)
		if not valid then
			return false, string.format("%s index=%d", tostring(reason), index)
		end
		if seen[record.itemId] == true then
			return false, string.format("item_id_duplicate index=%d", index)
		end
		seen[record.itemId] = true
	end

	return true, nil
end

function InventoryCraftConfig.ValidateRecipeCatalog(catalog: any, itemCatalog: any?): (boolean, string?)
	if type(catalog) ~= "table" then
		return false, "recipe_catalog_invalid"
	end

	local resolvedItemCatalog = InventoryCraftConfig.GetAllItemRecords(itemCatalog)
	local itemIndex = buildItemIndex(resolvedItemCatalog)
	local seen: { [string]: boolean } = {}

	for index, record in ipairs(catalog) do
		local valid, reason = validateRecipeRecord(record)
		if not valid then
			return false, string.format("%s index=%d", tostring(reason), index)
		end
		if seen[record.recipeId] == true then
			return false, string.format("recipe_id_duplicate index=%d", index)
		end
		seen[record.recipeId] = true

		for itemId, _count in pairs(record.inputs) do
			if itemIndex[itemId] == nil then
				return false, string.format("recipe_input_item_missing recipeId=%s itemId=%s", record.recipeId, itemId)
			end
		end

		for itemId, _count in pairs(record.outputs) do
			if itemIndex[itemId] == nil then
				return false, string.format("recipe_output_item_missing recipeId=%s itemId=%s", record.recipeId, itemId)
			end
		end
	end

	return true, nil
end

return InventoryCraftConfig
