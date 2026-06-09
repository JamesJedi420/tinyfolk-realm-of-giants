--!strict

local VillageWorksiteUpgradeState = require("../src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local kind = VillageWorksiteUpgradeState.ResolveWorksiteKind("WorkStation_A")
	assertEqual(kind, VillageWorksiteUpgradeState.WorksiteKinds.WorkStation, "workstation kind")
	local miningKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("MiningStation_A")
	assertEqual(miningKind, VillageWorksiteUpgradeState.WorksiteKinds.MiningStation, "mining kind")
	local warehouseKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("Warehouse_A")
	assertEqual(warehouseKind, VillageWorksiteUpgradeState.WorksiteKinds.Warehouse, "warehouse kind")
	local granaryKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("Granary_A")
	assertEqual(granaryKind, VillageWorksiteUpgradeState.WorksiteKinds.Granary, "granary kind")
	local shrineKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("Shrine_A")
	assertEqual(shrineKind, VillageWorksiteUpgradeState.WorksiteKinds.Shrine, "shrine kind")
	local farmKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("Farm_A")
	assertEqual(farmKind, VillageWorksiteUpgradeState.WorksiteKinds.Farm, "farm kind")
	local penKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("Pen_A")
	assertEqual(penKind, VillageWorksiteUpgradeState.WorksiteKinds.Pen, "pen kind")
	local guardTowerKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("GuardTower_A")
	assertEqual(guardTowerKind, VillageWorksiteUpgradeState.WorksiteKinds.GuardTower, "guard tower kind")
	local dwellingKind = VillageWorksiteUpgradeState.ResolveWorksiteKind("GiantDwelling_A")
	assertEqual(dwellingKind, VillageWorksiteUpgradeState.WorksiteKinds.GiantDwelling, "giant dwelling kind")
end

do
	local effectKind = VillageWorksiteUpgradeState.ResolveEffectKind(VillageWorksiteUpgradeState.WorksiteKinds.Pen)
	assertEqual(effectKind, VillageWorksiteUpgradeState.EffectKinds.Capacity, "pen capacity effect")
	local guardEffectKind =
		VillageWorksiteUpgradeState.ResolveEffectKind(VillageWorksiteUpgradeState.WorksiteKinds.GuardTower)
	assertEqual(guardEffectKind, VillageWorksiteUpgradeState.EffectKinds.Defense, "guard tower defense effect")
	local dwellingEffectKind =
		VillageWorksiteUpgradeState.ResolveEffectKind(VillageWorksiteUpgradeState.WorksiteKinds.GiantDwelling)
	assertEqual(
		dwellingEffectKind,
		VillageWorksiteUpgradeState.EffectKinds.GiantHousingCapacity,
		"giant dwelling housing effect"
	)
end

do
	local maxCaptures = VillageWorksiteUpgradeState.ResolveMaxConcurrentCaptures(1, 2)
	assertEqual(maxCaptures, 2, "pen held capacity multiplier scales concurrent captures")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local result = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "Pen_A",
		at = 14,
	})
	assertTrue(result.accepted, "pen upgrade accepted")
	assertEqual(result.cost.wood, 11, "pen level 1 wood cost")
end

do
	local defense = VillageWorksiteUpgradeState.ResolveDefenseModifiers(2)
	assertEqual(defense.treasuryAwardMultiplier, 1.5, "defense treasury multiplier level 2")
	assertEqual(defense.barrierDurationMultiplier, 1.5, "defense barrier multiplier level 2")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local result = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "GuardTower_A",
		at = 16,
	})
	assertTrue(result.accepted, "guard tower upgrade accepted")
	assertEqual(result.cost.wood, 14, "guard tower level 1 wood cost")
end

do
	local effectKind = VillageWorksiteUpgradeState.ResolveEffectKind(VillageWorksiteUpgradeState.WorksiteKinds.Farm)
	assertEqual(effectKind, VillageWorksiteUpgradeState.EffectKinds.Production, "farm production effect")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local result = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "Farm_A",
		at = 12,
	})
	assertTrue(result.accepted, "farm upgrade accepted")
	assertEqual(result.cost.wood, 9, "farm level 1 wood cost")
	assertEqual(result.cost.food, 2, "farm level 1 food cost")
end

do
	local housing = VillageWorksiteUpgradeState.ResolveGiantHousingCapacityModifiers(2)
	assertEqual(housing.housingCapacityMultiplier, 3, "giant housing capacity multiplier level 2")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local result = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "GiantDwelling_A",
		at = 18,
	})
	assertTrue(result.accepted, "giant dwelling upgrade accepted")
	assertEqual(result.cost.wood, 16, "giant dwelling level 1 wood cost")
end

do
	local capacity = VillageWorksiteUpgradeState.ResolveCapacityModifiers(2)
	assertEqual(capacity.inTransitMultiplier, 1.5, "capacity in-transit multiplier level 2")
	assertEqual(capacity.essenceMaxMultiplier, 1.5, "capacity essence multiplier level 2")
	assertEqual(capacity.heldCapacityMultiplier, 1.5, "capacity held multiplier level 2")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local result = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "Warehouse_A",
		at = 15,
	})
	assertTrue(result.accepted, "warehouse upgrade accepted")
	assertEqual(result.cost.wood, 14, "warehouse level 1 wood cost")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local result = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "WorkStation_A",
		at = 10,
	})
	assertTrue(result.accepted, "first upgrade accepted")
	assertEqual(result.level, 1, "first upgrade level")
	assertEqual(result.cost.wood, 10, "level 1 wood cost")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local first = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "WorkStation_A",
		at = 10,
	})
	local second = VillageWorksiteUpgradeState.ResolveUpgrade(first.state, {
		worksiteId = "WorkStation_A",
		at = 20,
	})
	assertTrue(second.accepted, "second upgrade accepted")
	assertEqual(second.level, 2, "second upgrade level")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local current = state
	for level = 1, 3 do
		local result = VillageWorksiteUpgradeState.ResolveUpgrade(current, {
			worksiteId = "MiningStation_A",
			at = level * 10,
		})
		assertTrue(result.accepted, "upgrade level " .. tostring(level))
		current = result.state
	end
	local blocked = VillageWorksiteUpgradeState.ResolveUpgrade(current, {
		worksiteId = "MiningStation_A",
		at = 40,
	})
	assertEqual(blocked.reason, "max_level_reached", "max level blocked")
end

do
	local modifiers = VillageWorksiteUpgradeState.ResolveProductionModifiers(2)
	assertEqual(modifiers.perTickMultiplier, 1.5, "level 2 per tick multiplier")
	assertEqual(modifiers.maxTotalMultiplier, 1.5, "level 2 max total multiplier")
end

do
	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	local upgraded = VillageWorksiteUpgradeState.ResolveUpgrade(state, {
		worksiteId = "WorkStation_A",
		at = 5,
	})
	local serialized = VillageWorksiteUpgradeState.SerializePersistenceState(upgraded.state)
	local applied = VillageWorksiteUpgradeState.ApplyPersistenceState(serialized)
	assertTrue(applied.accepted, "persistence round trip accepted")
	assertEqual(
		VillageWorksiteUpgradeState.GetUpgradeLevel(applied.state, "WorkStation_A"),
		1,
		"restored upgrade level"
	)
end

print("village_worksite_upgrade_state.spec.luau: all checks passed")
