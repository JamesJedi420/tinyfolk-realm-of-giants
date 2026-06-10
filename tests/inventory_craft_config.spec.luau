--!nocheck

local InventoryCraftConfig = require("../src/ReplicatedStorage/Shared/Config/InventoryCraftConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

do
	local valid, reason = InventoryCraftConfig.ValidateItemCatalog(InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertTrue(valid, "default item catalog valid")
	assertEqual(reason, nil, "default item catalog reason")
end

do
	local valid, reason = InventoryCraftConfig.ValidateRecipeCatalog(
		InventoryCraftConfig.DEFAULT_RECIPE_CATALOG,
		InventoryCraftConfig.DEFAULT_ITEM_CATALOG
	)
	assertTrue(valid, "default recipe catalog valid")
	assertEqual(reason, nil, "default recipe catalog reason")
end

do
	local invalidRecipeCatalog = {
		{
			recipeId = "craft_missing_output",
			displayName = "Missing Output",
			requiredRole = "Tinyfolk",
			inputs = {
				raw_fiber = 1,
			},
			outputs = {
				unknown_output = 1,
			},
			sourceId = "tin40_invalid_output",
		},
	}
	local valid, reason =
		InventoryCraftConfig.ValidateRecipeCatalog(invalidRecipeCatalog, InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertFalse(valid, "invalid output rejected")
	assertTrue(
		type(reason) == "string" and string.find(reason, "recipe_output_item_missing", 1, true) ~= nil,
		"invalid output reason"
	)
end

do
	local recipes = InventoryCraftConfig.GetAllRecipeRecords()
	assertEqual(#recipes, 6, "recipe catalog count")
	local items = InventoryCraftConfig.GetAllItemRecords()
	assertEqual(#items, 12, "item catalog count")
end

print("inventory_craft_config: all checks passed")
