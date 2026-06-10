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
	return InventoryCraftState.NewState(InventoryCraftConfig.TEST_STARTING_ITEMS)
end

do
	local state = makeBootstrapState()
	local snapshot = InventoryCraftState.GetSnapshot(state, InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertEqual(snapshot.itemCounts.raw_fiber, 4, "bootstrap raw_fiber count")
	assertEqual(snapshot.itemCounts.wood_scrap, 3, "bootstrap wood_scrap count")
	assertEqual(snapshot.itemCounts.stone_shard, 3, "bootstrap stone_shard count")
	assertEqual(snapshot.itemCounts.plant_resin, 2, "bootstrap plant_resin count")
	assertEqual(#snapshot.items, 6, "bootstrap item entry count")
	assertTrue(#snapshot.craftableRecipeIds >= 3, "bootstrap craftable recipe count")
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
	assertEqual(crafted.state.itemCounts.raw_fiber, 2, "twine satchel consumed raw_fiber")
	assertEqual(crafted.state.itemCounts.wood_scrap, 2, "twine satchel consumed wood_scrap")
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
	assertEqual(crafted.state.itemCounts.wood_scrap, 2, "repair wedge consumed wood_scrap")
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

do
	local state = makeBootstrapState()
	local crafted = InventoryCraftState.ResolveCraft(state, {
		recipeId = "craft_smoke_pouch",
		requesterRole = "Tinyfolk",
		now = 70,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertTrue(crafted.accepted, "smoke pouch craft accepted")
	assertEqual(crafted.state.itemCounts.smoke_pouch, 1, "smoke pouch output")
end

do
	local state = makeBootstrapState()
	local twineCrafted = InventoryCraftState.ResolveCraft(state, {
		recipeId = "craft_twine_satchel",
		requesterRole = "Tinyfolk",
		now = 80,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertTrue(twineCrafted.accepted, "twine satchel for chain accepted")
	local ropeCrafted = InventoryCraftState.ResolveCraft(twineCrafted.state, {
		recipeId = "craft_rope_anchor",
		requesterRole = "Tinyfolk",
		now = 81,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertTrue(ropeCrafted.accepted, "rope anchor chain craft accepted")
	assertEqual(ropeCrafted.state.itemCounts.rope_anchor, 1, "rope anchor chain output")
end

do
	local state = makeBootstrapState()
	local wedgeCrafted = InventoryCraftState.ResolveCraft(state, {
		recipeId = "craft_repair_wedge",
		requesterRole = "Tinyfolk",
		now = 90,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertTrue(wedgeCrafted.accepted, "repair wedge for chain accepted")
	local spikeCrafted = InventoryCraftState.ResolveCraft(wedgeCrafted.state, {
		recipeId = "craft_spike_wedge",
		requesterRole = "Tinyfolk",
		now = 91,
	}, InventoryCraftConfig.DEFAULT_ITEM_CATALOG, InventoryCraftConfig.DEFAULT_RECIPE_CATALOG)
	assertTrue(spikeCrafted.accepted, "spike wedge chain craft accepted")
	assertEqual(spikeCrafted.state.itemCounts.spike_wedge, 1, "spike wedge chain output")
end

do
	local state = InventoryCraftState.NewState({
		smoke_pouch = 1,
	})
	local consumed =
		InventoryCraftState.ConsumeItems(state, { smoke_pouch = 1 }, InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertTrue(consumed.accepted, "crafted item consume accepted")
	assertEqual(consumed.state.itemCounts.smoke_pouch, nil, "smoke pouch consumed")
	assertEqual(consumed.state.lastReason, "items_consumed", "consume reason")
end

do
	local state = InventoryCraftState.NewState({
		raw_fiber = 1,
	})
	local rejected =
		InventoryCraftState.ConsumeItems(state, { raw_fiber = 1 }, InventoryCraftConfig.DEFAULT_ITEM_CATALOG)
	assertFalse(rejected.accepted, "material consume rejected")
	assertEqual(rejected.reason, "crafted_item_required", "material consume reason")
end

do
	local state = makeBootstrapState()
	local craftable = InventoryCraftState.ListCraftableRecipes(
		state,
		"Tinyfolk",
		InventoryCraftConfig.DEFAULT_ITEM_CATALOG,
		InventoryCraftConfig.DEFAULT_RECIPE_CATALOG
	)
	assertTrue(#craftable >= 3, "list craftable recipes count")
	local foundSmoke = false
	for _, entry in ipairs(craftable) do
		if entry.recipeId == "craft_smoke_pouch" then
			foundSmoke = true
		end
	end
	assertTrue(foundSmoke, "craft_smoke_pouch listed as craftable")
end

print("inventory_craft_state: all checks passed")
