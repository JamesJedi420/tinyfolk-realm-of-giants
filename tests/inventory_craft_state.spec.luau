--!nocheck

local InventoryCraftConfig = require("../src/ReplicatedStorage/Shared/Config/InventoryCraftConfig")
local InventoryCraftState = require("../src/ReplicatedStorage/Shared/InventoryCraft/InventoryCraftState")

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

local function makeBootstrapState(): any
	return InventoryCraftState.NewState({
		raw_fiber = 3,
		wood_scrap = 2,
		stone_shard = 2,
	})
end

do
	local state = makeBootstrapState()
	local snapshot = InventoryCraftState.GetSnapshot(state, InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertEqual(snapshot.itemCounts.raw_fiber, 3, "bootstrap raw_fiber count")
	assertEqual(snapshot.itemCounts.wood_scrap, 2, "bootstrap wood_scrap count")
	assertEqual(snapshot.itemCounts.stone_shard, 2, "bootstrap stone_shard count")
	assertEqual(#snapshot.items, 3, "bootstrap item entry count")
end

do
	local state = makeBootstrapState()
	local rejected =
		InventoryCraftState.AddItems(state, { unknown_item = 1 }, InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertFalse(rejected.accepted, "unknown item rejected")
	assertEqual(rejected.reason, "item_missing", "unknown item reason")
end

do
	local state = makeBootstrapState()
	local rejected = InventoryCraftState.AddItems(state, { raw_fiber = 97 }, InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertFalse(rejected.accepted, "stack overflow rejected")
	assertEqual(rejected.reason, "item_stack_capacity_exceeded", "stack overflow reason")
end

do
	local state = makeBootstrapState()
	local crafted = InventoryCraftState.ResolveCraft(state, {
		recipeId = "craft_twine_satchel",
		requesterRole = "Tinyfolk",
		now = 42,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertTrue(crafted.accepted, "twine satchel craft accepted")
	assertEqual(crafted.state.itemCounts.raw_fiber, 1, "twine satchel consumed raw_fiber")
	assertEqual(crafted.state.itemCounts.wood_scrap, 1, "twine satchel consumed wood_scrap")
	assertEqual(crafted.state.itemCounts.twine_satchel, 1, "twine satchel output")
	assertEqual(crafted.state.craftedTotal, 1, "twine satchel crafted total")
	assertEqual(crafted.state.lastCraftRecipeId, "craft_twine_satchel", "twine satchel recipe id")
	assertEqual(crafted.state.lastCraftAt, 42, "twine satchel craft timestamp")
end

do
	local state = makeBootstrapState()
	local crafted = InventoryCraftState.ResolveCraft(state, {
		recipeId = "craft_repair_wedge",
		requesterRole = "Tinyfolk",
		now = 55,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertTrue(crafted.accepted, "repair wedge craft accepted")
	assertEqual(crafted.state.itemCounts.wood_scrap, 1, "repair wedge consumed wood_scrap")
	assertEqual(crafted.state.itemCounts.repair_wedge, 1, "repair wedge output")
	assertTrue(
		crafted.state.itemCounts.stone_shard == nil or crafted.state.itemCounts.stone_shard == 0,
		"repair wedge stone key cleared"
	)
end

do
	local state = InventoryCraftState.NewState({
		wood_scrap = 1,
	})
	local rejected = InventoryCraftState.ResolveCraft(state, {
		recipeId = "craft_twine_satchel",
		requesterRole = "Tinyfolk",
		now = 10,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertFalse(rejected.accepted, "insufficient inputs rejected")
	assertEqual(rejected.reason, "insufficient_inputs", "insufficient inputs reason")
end

do
	local state = makeBootstrapState()
	local rejected = InventoryCraftState.ResolveCraft(state, {
		recipeId = "craft_twine_satchel",
		requesterRole = "Giant",
		now = 10,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertFalse(rejected.accepted, "giant craft rejected")
	assertEqual(rejected.reason, "tinyfolk_role_required", "giant craft reason")
end

do
	local state = makeBootstrapState()
	local rejected = InventoryCraftState.ResolveCraft(state, {
		recipeId = "missing_recipe",
		requesterRole = "Tinyfolk",
		now = 10,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertFalse(rejected.accepted, "missing recipe rejected")
	assertEqual(rejected.reason, "recipe_missing", "missing recipe reason")
end

print("inventory_craft_state: all checks passed")
