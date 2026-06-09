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
end

do
	local capacity = VillageWorksiteUpgradeState.ResolveCapacityModifiers(2)
	assertEqual(capacity.inTransitMultiplier, 1.5, "capacity in-transit multiplier level 2")
	assertEqual(capacity.essenceMaxMultiplier, 1.5, "capacity essence multiplier level 2")
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
