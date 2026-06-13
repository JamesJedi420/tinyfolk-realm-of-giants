--!strict

local RealmCaptureZoneValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmCaptureZoneValidator")

type RealmDescriptor = any
type CaptureZoneConfig = any

local function makeDescriptor(captureZones, spawns)
	return {
		spawns = spawns,
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 100, y = 0, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = captureZones,
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 100, y = 0, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 100 } },
		},
	} :: RealmDescriptor
end

local config: CaptureZoneConfig = {
	minimumSpawnSeparationStuds = 70,
	minimumEscapeSeparationStuds = 80,
	minimumGiantRouteSeparationStuds = 5,
	minimumCaptureRadiusStuds = 8,
	maximumCaptureRadiusStuds = 25,
	minimumCaptureZoneGapStuds = 5,
	captureZoneClusterRadiusStuds = 40,
	maximumCaptureZoneNeighborsInClusterRadius = 2,
	maximumCaptureZonesPerRealm = 4,
	safeZoneNowSeconds = 100,
}

local function reasonContains(reason: string?, text: string): boolean
	if type(reason) ~= "string" then
		return false
	end
	return string.find(reason, text, 1, true) ~= nil
end

-- Block 1: Vacuous pass (empty captureZones)
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	assert(result.passed == true, "Block 1: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 1: Reason should be nil for vacuous pass")
end

-- Block 2: Vacuous pass (empty spawns)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	assert(result.passed == true, "Block 2: Should vacuously pass with empty spawns")
	assert(result.reason == nil, "Block 2: Reason should be nil for vacuous pass")
end

-- Block 3: Valid separation (capture 70+ studs from spawn)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 70, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	assert(result.passed == true, "Block 3: Should pass with exactly 70 studs separation")
	assert(result.reason == nil, "Block 3: Reason should be nil for pass")
end

-- Block 4: Invalid separation (capture too close to spawn)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	assert(result.passed == false, "Block 4: Should fail with 50 studs separation (< 70)")
	assert(result.reason ~= nil, "Block 4: Reason should explain the violation")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 4: Reason should include capture zone name")
	assert(string.find(result.reason, "TinyfolkSpawn") ~= nil, "Block 4: Reason should include spawn name")
end

-- Block 5: Multiple capture zones, one fails
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 75, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	assert(result.passed == false, "Block 5: Should fail when any capture zone violates minimum separation")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 5: Reason should identify the violating zone")
end

-- Block 6: Multiple spawns, capture too close to at least one
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn_A", position = { x = 0, y = 0, z = 0 } },
		{ name = "TinyfolkSpawn_B", position = { x = 200, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	assert(result.passed == false, "Block 6: Should fail if capture zone is too close to any spawn")
	assert(reasonContains(result.reason, "TinyfolkSpawn_A"), "Block 6: Reason should identify the nearest spawn")
end

-- Block 7: 3D distance check (not just XZ plane)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 70, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	assert(result.passed == true, "Block 7: Should correctly compute 3D distance (70 studs in X direction)")
end

-- Block 8: Pythagoras check (diagonal distance)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 40, y = 0, z = 40 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnSeparation(descriptor, config)
	-- sqrt(40^2 + 40^2) = sqrt(3200) ≈ 56.57, which is < 70
	assert(result.passed == false, "Block 8: Should fail for diagonal distance < 70 (56.57 studs)")
end

-- ── Slice 12: capture_zone_escape_separation ────────────────────────────────

-- Block 9: Vacuous pass (empty captureZones)
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(descriptor, config)
	assert(result.passed == true, "Block 9: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 9: Reason should be nil")
end

-- Block 10: Vacuous pass (empty escapeRoutes)
do
	local d2 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = {},
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
			},
			edges = {},
		},
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(d2, config)
	assert(result.passed == true, "Block 10: Should vacuously pass with empty escapeRoutes")
	assert(result.reason == nil, "Block 10: Reason should be nil")
end

-- Block 11: Baseline pass (capture zone >= 80 studs from escape route)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(descriptor, config)
	-- escape route in makeDescriptor is at (100, 0, 0) → distance = 100 studs
	assert(result.passed == true, "Block 11: Should pass when capture zone is 100 studs from escape route")
	assert(result.reason == nil, "Block 11: Reason should be nil")
end

-- Block 12: Single-zone fail (capture zone < 80 studs from escape route)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 70, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	-- escape route at (100, 0, 0) → distance = 30 studs
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(descriptor, config)
	assert(result.passed == false, "Block 12: Should fail with 30 studs from escape route (< 80)")
	assert(result.reason ~= nil, "Block 12: Reason should explain the violation")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 12: Reason should include capture zone name")
	assert(string.find(result.reason, "EscapeRoute_A") ~= nil, "Block 12: Reason should include escape route name")
end

-- Block 13: Boundary pass (exactly 80 studs from escape route)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 20, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	-- escape route at (100, 0, 0) → distance = 80 studs exactly
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(descriptor, config)
	assert(result.passed == true, "Block 13: Should pass at exactly 80 studs boundary")
	assert(result.reason == nil, "Block 13: Reason should be nil")
end

-- Block 14: Multiple zones mixed (one valid, one invalid)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 70, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	-- Zone_A at (0,0,0): 100 studs from escape → pass
	-- Zone_B at (70,0,0): 30 studs from escape → fail
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(descriptor, config)
	assert(result.passed == false, "Block 14: Should fail when any capture zone violates escape separation")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 14: Reason should identify the violating zone")
end

-- Block 15: Multiple escape routes (valid against one, invalid against another)
do
	local d3 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = {
			{ name = "EscapeRoute_A", position = { x = 200, y = 0, z = 0 } },
			{ name = "EscapeRoute_B", position = { x = 60, y = 0, z = 0 } },
		},
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 20, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 200, y = 0, z = 0 } },
				{ name = "EscapeRoute_B", nodeType = "escape", position = { x = 60, y = 0, z = 0 } },
			},
			edges = {
				{ from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 200 },
				{ from = "TinyfolkSpawn", to = "EscapeRoute_B", distance = 60 },
			},
		},
	} :: RealmDescriptor
	-- Zone_A at (20,0,0): 180 studs from EscapeRoute_A (pass), 40 studs from EscapeRoute_B (fail)
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(d3, config)
	assert(result.passed == false, "Block 15: Should fail when zone is too close to any escape route")
	assert(reasonContains(result.reason, "EscapeRoute_B"), "Block 15: Reason should identify EscapeRoute_B")
end

-- Block 16: 3D distance verification
do
	local descriptor = makeDescriptor({
		-- at (60, 50, 0): distance to escape at (100,0,0) = sqrt(40^2 + 50^2) = sqrt(4100) ≈ 64.0 studs
		{ name = "GiantCaptureZone_A", position = { x = 60, y = 50, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(descriptor, config)
	-- 3D distance ≈ 64.0 < 80 → fail
	assert(result.passed == false, "Block 16: Should use full 3D distance (≈64 studs, < 80)")
end

-- ── Slice 13: capture_zone_radius_bounds ────────────────────────────────────

-- Block 17: Vacuous pass (no capture zones)
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(descriptor, config)
	assert(result.passed == true, "Block 17: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 17: Reason should be nil")
end

-- Block 18: Single valid zone (radius within bounds)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(descriptor, config)
	assert(result.passed == true, "Block 18: Should pass with radius 15 (within [8, 25])")
	assert(result.reason == nil, "Block 18: Reason should be nil")
end

-- Block 19: Minimum boundary pass (radius exactly 8)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 8, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(descriptor, config)
	assert(result.passed == true, "Block 19: Should pass at exact minimum radius 8")
	assert(result.reason == nil, "Block 19: Reason should be nil")
end

-- Block 20: Maximum boundary pass (radius exactly 25)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 25, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(descriptor, config)
	assert(result.passed == true, "Block 20: Should pass at exact maximum radius 25")
	assert(result.reason == nil, "Block 20: Reason should be nil")
end

-- Block 21: Below minimum fail (radius 7)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 7, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(descriptor, config)
	assert(result.passed == false, "Block 21: Should fail with radius 7 (< minimum 8)")
	assert(result.reason ~= nil, "Block 21: Reason should describe the violation")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 21: Reason should include zone name")
	assert(string.find(result.reason, "minimum") ~= nil, "Block 21: Reason should mention minimum")
end

-- Block 22: Above maximum fail (radius 26)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 26, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(descriptor, config)
	assert(result.passed == false, "Block 22: Should fail with radius 26 (> maximum 25)")
	assert(result.reason ~= nil, "Block 22: Reason should describe the violation")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 22: Reason should include zone name")
	assert(string.find(result.reason, "maximum") ~= nil, "Block 22: Reason should mention maximum")
end

-- Block 23: Multiple zones mixed (one valid, one below minimum)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 300, y = 0, z = 0 }, radius = 5, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(descriptor, config)
	assert(result.passed == false, "Block 23: Should fail when any zone violates radius bounds")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 23: Reason should identify the violating zone")
end

-- Block 24: Non-GiantCapture tag is ignored
-- Convention: captureZoneRadiusBounds only validates zones tagged GiantCapture.
-- Zones with a different tag are skipped, regardless of their radius value.
do
	local d4 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 500, y = 0, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "OtherZone_A", position = { x = 200, y = 0, z = 0 }, radius = 1, tag = "GiantControl" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 500, y = 0, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 500 } },
		},
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(d4, config)
	assert(result.passed == true, "Block 24: Non-GiantCapture tagged zones are not validated by this rule")
	assert(result.reason == nil, "Block 24: Reason should be nil")
end

print("✓ realm_capture_zone.spec.luau: all 24 blocks passed")

-- ── Slice 14: capture_zone_spawn_perimeter_clearance ─────────────────────────
-- Convention: vacuous pass when captureZones or spawns is empty.
-- Non-GiantCapture tags are skipped.

-- Block 25: Vacuous pass (no capture zones)
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == true, "Block 25: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 25: Reason should be nil")
end

-- Block 26: Vacuous pass (no spawns)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {})
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == true, "Block 26: Should vacuously pass with empty spawns")
	assert(result.reason == nil, "Block 26: Reason should be nil")
end

-- Block 27: Spawn clearly outside perimeter (dist > radius)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	-- dist = 200, radius = 15 → dist - radius = 185 > 0 → pass
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == true, "Block 27: Spawn 200 studs away from radius-15 zone should pass")
	assert(result.reason == nil, "Block 27: Reason should be nil")
end

-- Block 28: Spawn inside perimeter (dist < radius)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 10, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	-- dist = 10, radius = 15 → dist - radius = -5 ≤ 0 → fail
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == false, "Block 28: Spawn inside capture zone perimeter should fail")
	assert(result.reason ~= nil, "Block 28: Reason should describe the violation")
	assert(string.find(result.reason, "TinyfolkSpawn") ~= nil, "Block 28: Reason should include spawn name")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 28: Reason should include zone name")
end

-- Block 29: Spawn exactly on perimeter (dist == radius)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 15, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	-- dist = 15, radius = 15 → dist - radius = 0 ≤ 0 → fail
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == false, "Block 29: Spawn exactly on perimeter should fail (dist - radius = 0)")
end

-- Block 30: Multiple zones mixed (one valid, one encloses spawn)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 200, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 5, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == false, "Block 30: Should fail when any zone encloses a spawn")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 30: Reason should identify the violating zone")
end

-- Block 31: Multiple spawns mixed (one outside, one inside)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 5, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn_A", position = { x = 200, y = 0, z = 0 } },
		{ name = "TinyfolkSpawn_B", position = { x = 0, y = 0, z = 0 } },
	})
	-- TinyfolkSpawn_A: dist=195, radius=15 → pass; TinyfolkSpawn_B: dist=5, radius=15 → fail
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == false, "Block 31: Should fail when any spawn is inside any zone")
	assert(reasonContains(result.reason, "TinyfolkSpawn_B"), "Block 31: Reason should identify the enclosed spawn")
end

-- Block 32: 3D perimeter case (Y offset matters)
do
	local descriptor = makeDescriptor({
		-- center at (0, 20, 0), radius 15. Spawn at (0,0,0): dist=20, 20-15=5 > 0 → pass
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 20, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(descriptor, config)
	assert(result.passed == true, "Block 32: 3D distance (dist=20, radius=15) should pass")
end

-- Block 33: Non-GiantCapture zone is ignored
do
	local d5 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 500, y = 0, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = {
			-- radius 500 would enclose spawn if tag were GiantCapture, but it's not
			{ name = "OtherZone_A", position = { x = 0, y = 0, z = 0 }, radius = 500, tag = "GiantControl" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 500, y = 0, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 500 } },
		},
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneSpawnPerimeterClearance(d5, config)
	assert(result.passed == true, "Block 33: Non-GiantCapture zone is skipped by this rule")
end

print("✓ realm_capture_zone.spec.luau: all 33 blocks passed (Slice 14 done)")

-- ── Slice 15: capture_zone_escape_perimeter_clearance ────────────────────────
-- Convention: vacuous pass when captureZones or escapeRoutes is empty.
-- Non-GiantCapture tags are skipped.

-- Block 34: Vacuous pass (no capture zones)
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(descriptor, config)
	assert(result.passed == true, "Block 34: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 34: Reason should be nil")
end

-- Block 35: Vacuous pass (no escape routes)
do
	local d6 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = {},
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		routeGraph = {
			nodes = { { name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } } },
			edges = {},
		},
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(d6, config)
	assert(result.passed == true, "Block 35: Should vacuously pass with empty escapeRoutes")
	assert(result.reason == nil, "Block 35: Reason should be nil")
end

-- Block 36: Escape route clearly outside perimeter
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 200 } },
	})
	-- escape route in makeDescriptor is at (100,0,0): dist=100, radius=15 → 100-15=85 > 0 → pass
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(descriptor, config)
	assert(result.passed == true, "Block 36: Escape route 100 studs away from radius-15 zone should pass")
	assert(result.reason == nil, "Block 36: Reason should be nil")
end

-- Block 37: Escape route inside perimeter
do
	local d7 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 10, y = 0, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 10, y = 0, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 10 } },
		},
	} :: RealmDescriptor
	-- dist=10, radius=15 → dist-radius=-5 ≤ 0 → fail
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(d7, config)
	assert(result.passed == false, "Block 37: Escape route inside capture zone perimeter should fail")
	assert(result.reason ~= nil, "Block 37: Reason should describe the violation")
	assert(string.find(result.reason, "EscapeRoute_A") ~= nil, "Block 37: Reason should include escape route name")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 37: Reason should include zone name")
end

-- Block 38: Escape route exactly on perimeter (dist == radius)
do
	local d8 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 15, y = 0, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 15, y = 0, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 15 } },
		},
	} :: RealmDescriptor
	-- dist=15, radius=15 → dist-radius=0 ≤ 0 → fail
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(d8, config)
	assert(result.passed == false, "Block 38: Escape route exactly on perimeter should fail (dist - radius = 0)")
end

-- Block 39: Multiple zones mixed (one valid, one encloses escape route)
do
	local d9 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 100, y = 0, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
			{ name = "GiantCaptureZone_B", position = { x = 100, y = 0, z = 0 }, radius = 20, tag = "GiantCapture" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 100, y = 0, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 100 } },
		},
	} :: RealmDescriptor
	-- Zone_A at (0,0,0) radius 15: dist to escape = 100 → 100-15=85 > 0 → pass
	-- Zone_B at (100,0,0) radius 20: dist to escape = 0 → 0-20=-20 ≤ 0 → fail
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(d9, config)
	assert(result.passed == false, "Block 39: Should fail when any zone encloses an escape route")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 39: Reason should identify the violating zone")
end

-- Block 40: 3D perimeter case
do
	local d10 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		-- escape at (0,12,0), zone center (0,0,0) radius 15: dist=12, 12-15=-3 ≤ 0 → fail
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 0, y = 12, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 0, y = 12, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 12 } },
		},
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(d10, config)
	assert(result.passed == false, "Block 40: 3D Y-axis escape inside perimeter (dist=12 < radius=15) should fail")
end

-- Block 41: Non-GiantCapture zone is ignored
do
	local d11 = {
		spawns = { { name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } } },
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 5, y = 0, z = 0 } } },
		controlZones = {},
		props = {},
		captureZones = {
			-- radius 500 would enclose escape route if tag were GiantCapture, but it's not
			{ name = "OtherZone_A", position = { x = 0, y = 0, z = 0 }, radius = 500, tag = "GiantControl" },
		},
		routeGraph = {
			nodes = {
				{ name = "TinyfolkSpawn", nodeType = "spawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "EscapeRoute_A", nodeType = "escape", position = { x = 5, y = 0, z = 0 } },
			},
			edges = { { from = "TinyfolkSpawn", to = "EscapeRoute_A", distance = 5 } },
		},
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneEscapePerimeterClearance(d11, config)
	assert(result.passed == true, "Block 41: Non-GiantCapture zone is skipped by this rule")
end

print("✓ realm_capture_zone.spec.luau: all 41 blocks passed")

-- ── Slice 16: capture_zone_overlap ───────────────────────────────────────────
-- Rule: fail if dist < r1 + r2 for any pair of GiantCapture zones.
-- Touching (dist == r1 + r2) is allowed.
-- Non-GiantCapture zones are ignored.
-- Vacuous pass when fewer than two GiantCapture zones exist.

-- Block 42: Vacuous pass (no capture zones)
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == true, "Block 42: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 42: Reason should be nil")
end

-- Block 43: Vacuous pass (single capture zone)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == true, "Block 43: Single zone should vacuously pass")
	assert(result.reason == nil, "Block 43: Reason should be nil")
end

-- Block 44: Two clearly disjoint zones (dist >> r1 + r2)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 200, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	-- dist=200, r1+r2=20 → 200 >= 20 → pass
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == true, "Block 44: Clearly disjoint zones should pass")
	assert(result.reason == nil, "Block 44: Reason should be nil")
end

-- Block 45: Two overlapping zones (dist < r1 + r2)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 20, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	-- dist=20, r1+r2=30 → 20 < 30 → fail
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == false, "Block 45: Overlapping zones should fail")
	assert(result.reason ~= nil, "Block 45: Reason should describe the violation")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 45: Reason should include zone A name")
	assert(string.find(result.reason, "GiantCaptureZone_B") ~= nil, "Block 45: Reason should include zone B name")
end

-- Block 46: Exact boundary touch (dist == r1 + r2) — allowed, should pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 30, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	-- dist=30, r1+r2=30 → 30 >= 30 → pass
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == true, "Block 46: Boundary touch (dist == r1+r2) should pass")
	assert(result.reason == nil, "Block 46: Reason should be nil")
end

-- Block 47: Multiple zones with one bad pair
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 200, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 210, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	-- A-B: dist=200, r1+r2=20 → pass
	-- A-C: dist=210, r1+r2=20 → pass
	-- B-C: dist=10, r1+r2=20 → 10 < 20 → fail
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == false, "Block 47: Should fail when any pair overlaps")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 47: Reason should include zone B")
	assert(reasonContains(result.reason, "GiantCaptureZone_C"), "Block 47: Reason should include zone C")
end

-- Block 48: 3D overlap case (Y-axis separation)
do
	local descriptor = makeDescriptor({
		-- center at (0,0,0) r=10 and center at (0,15,0) r=10: dist=15, r1+r2=20 → 15 < 20 → fail
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 0, y = 15, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == false, "Block 48: 3D Y-axis overlap (dist=15 < r1+r2=20) should fail")
end

-- Block 49: Non-GiantCapture zone ignored (overlapping with a differently tagged zone)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		-- Positioned to overlap with A, but tag is GiantControl — should be ignored
		{ name = "OtherZone_B", position = { x = 5, y = 0, z = 0 }, radius = 10, tag = "GiantControl" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	-- Only one GiantCapture zone → vacuous pass (fewer than 2 GiantCapture zones)
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(
		result.passed == true,
		"Block 49: Non-GiantCapture zone must be ignored; only one GiantCapture → vacuous pass"
	)
	assert(result.reason == nil, "Block 49: Reason should be nil")
end

-- Block 50: Deterministic pair reporting (first violating pair in index order is reported)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 5, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 3, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	-- A-B checked first (i=1, j=2): dist=5, r1+r2=20 → fail immediately with A and B
	local result = RealmCaptureZoneValidator.captureZoneOverlap(descriptor, config)
	assert(result.passed == false, "Block 50: Should fail on first violating pair")
	-- The first pair in iteration order (A, B) must be reported, not C
	assert(reasonContains(result.reason, "GiantCaptureZone_A"), "Block 50: First zone in pair should be A")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 50: Second zone in pair should be B")
end

print("✓ realm_capture_zone.spec.luau: all 50 blocks passed")

-- ── Slice 17: capture_zone_minimum_spacing ──────────────────────────────────
-- Rule: fail if perimeterGap = dist - (r1 + r2) is below minimumCaptureZoneGapStuds.
-- Boundary pass at exact minimum gap is allowed.
-- Non-GiantCapture zones are ignored.

-- Block 51: Vacuous pass (no capture zones)
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == true, "Block 51: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 51: Reason should be nil")
end

-- Block 52: Vacuous pass (single GiantCapture zone)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == true, "Block 52: Single zone should vacuously pass")
	assert(result.reason == nil, "Block 52: Reason should be nil")
end

-- Block 53: Two zones with gap above minimum (pass)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 30, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- dist=30, r1+r2=20, gap=10 >= minimum 5 → pass
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == true, "Block 53: Gap above minimum should pass")
	assert(result.reason == nil, "Block 53: Reason should be nil")
end

-- Block 54: Two zones with gap below minimum (fail)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 24, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- dist=24, r1+r2=20, gap=4 < minimum 5 → fail
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == false, "Block 54: Gap below minimum should fail")
	assert(result.reason ~= nil, "Block 54: Reason should describe the violation")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 54: Reason should include zone A")
	assert(string.find(result.reason, "GiantCaptureZone_B") ~= nil, "Block 54: Reason should include zone B")
end

-- Block 55: Exact minimum gap boundary (pass)
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 25, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- dist=25, r1+r2=20, gap=5 == minimum 5 → pass
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == true, "Block 55: Exact minimum gap should pass")
	assert(result.reason == nil, "Block 55: Reason should be nil")
end

-- Block 56: Overlapping zones also fail under spacing rule
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 15, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- dist=15, r1+r2=20, gap=-5 < minimum 5 → fail
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == false, "Block 56: Overlap should fail minimum-spacing rule as well")
end

-- Block 57: Multiple zones with one bad pair
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 60, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 84, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- A-B: gap=40 pass; A-C: gap=64 pass; B-C: dist=24 gap=4 fail
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == false, "Block 57: Any bad pair should fail")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 57: Reason should include zone B")
	assert(reasonContains(result.reason, "GiantCaptureZone_C"), "Block 57: Reason should include zone C")
end

-- Block 58: 3D spacing case
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 0, y = 0, z = 24 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- dist=24 in 3D, r1+r2=20, gap=4 < minimum 5 → fail
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == false, "Block 58: 3D spacing should use full center-to-center distance")
end

-- Block 59: Non-GiantCapture zone ignored
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "OtherZone_B", position = { x = 2, y = 0, z = 0 }, radius = 10, tag = "GiantControl" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- Only one GiantCapture zone after filtering → vacuous pass
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == true, "Block 59: Non-GiantCapture zones should be ignored")
	assert(result.reason == nil, "Block 59: Reason should be nil")
end

-- Block 60: Deterministic pair reporting
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 24, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 23, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- A-B is checked first and already violates gap minimum, so A/B should be reported.
	local result = RealmCaptureZoneValidator.captureZoneMinimumSpacing(descriptor, config)
	assert(result.passed == false, "Block 60: Should fail on first violating pair")
	assert(reasonContains(result.reason, "GiantCaptureZone_A"), "Block 60: First pair should include A")
	assert(reasonContains(result.reason, "GiantCaptureZone_B"), "Block 60: First pair should include B")
end

print("✓ realm_capture_zone.spec.luau: all 60 blocks passed")

-- ── Slice 21: capture_zone_cluster_density_cap ──────────────────────────────
-- Rule: for each GiantCapture zone, count how many other GiantCapture zone
-- centers are within captureZoneClusterRadiusStuds.
-- Fail if count exceeds maximumCaptureZoneNeighborsInClusterRadius.
-- Boundary pass at exact maximum is allowed.
-- Non-GiantCapture zones are ignored.

-- Block 61: no capture zones -> vacuous pass
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == true, "Block 61: Should vacuously pass with empty captureZones")
	assert(result.reason == nil, "Block 61: Reason should be nil")
end

-- Block 62: single capture zone -> vacuous pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == true, "Block 62: Single GiantCapture zone should vacuously pass")
	assert(result.reason == nil, "Block 62: Reason should be nil")
end

-- Block 63: two zones inside radius but under cap -> pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- radius=40, each has 1 neighbor -> 1 <= max 2
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == true, "Block 63: Neighbor count below cap should pass")
	assert(result.reason == nil, "Block 63: Reason should be nil")
end

-- Block 64: one zone with too many neighbors inside radius -> fail
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = -20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = 0, y = 0, z = 20 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- Zone A has 3 neighbors within 40 -> exceeds max 2
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == false, "Block 64: Too many local neighbors should fail")
	assert(result.reason ~= nil, "Block 64: Reason should describe violation")
	assert(string.find(result.reason, "GiantCaptureZone_A") ~= nil, "Block 64: Reason should identify center zone")
end

-- Block 65: exact boundary at max neighbors -> pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = -20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- Zone A has exactly 2 neighbors within 40 -> boundary pass
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == true, "Block 65: Exact max neighbor boundary should pass")
	assert(result.reason == nil, "Block 65: Reason should be nil")
end

-- Block 66: neighbors outside cluster radius do not count -> pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 45, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 0, y = 0, z = 45 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = -45, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- Distances from A are 45 (>40), so neighbor count is 0
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == true, "Block 66: Neighbors outside radius must not count")
	assert(result.reason == nil, "Block 66: Reason should be nil")
end

-- Block 67: mixed tags: non-GiantCapture ignored -> pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "OtherZone_C", position = { x = -20, y = 0, z = 0 }, radius = 10, tag = "GiantControl" },
		{ name = "OtherZone_D", position = { x = 0, y = 0, z = 20 }, radius = 10, tag = "GiantControl" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- Counting only GiantCapture -> each has 1 neighbor within 40 -> pass
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == true, "Block 67: Non-GiantCapture zones should be ignored")
	assert(result.reason == nil, "Block 67: Reason should be nil")
end

-- Block 68: 3D distance case uses full 3D counting
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 0, y = 30, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 0, y = -30, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = 0, y = 0, z = 30 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	-- For A, all B/C/D are within 30 in 3D -> 3 neighbors > max 2 -> fail
	local result = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(result.passed == false, "Block 68: 3D neighbor counting should fail with 3 neighbors inside radius")
	assert(reasonContains(result.reason, "GiantCaptureZone_A"), "Block 68: Reason should identify center zone")
end

-- Block 69: deterministic failure reporting / stable repeat behavior
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = -20, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = 0, y = 0, z = 20 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	local resultA = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	local resultB = RealmCaptureZoneValidator.captureZoneClusterDensityCap(descriptor, config)
	assert(resultA.passed == false, "Block 69: First run should fail")
	assert(resultB.passed == false, "Block 69: Second run should fail")
	assert(resultA.reason == resultB.reason, "Block 69: Failure reason should be deterministic and stable")
end

print("✓ realm_capture_zone.spec.luau: all 69 blocks passed")

-- ── Slice 22: capture_zone_total_cap ────────────────────────────────────────
-- Rule: count only GiantCapture zones and fail when the total exceeds
-- maximumCaptureZonesPerRealm.

-- Block 70: no capture zones -> pass
do
	local descriptor = makeDescriptor({}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	assert(result.passed == true, "Block 70: No GiantCapture zones should pass")
	assert(result.reason == nil, "Block 70: Reason should be nil")
end

-- Block 71: one capture zone under cap -> pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 200, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	assert(result.passed == true, "Block 71: Count 1 <= max 4 should pass")
	assert(result.reason == nil, "Block 71: Reason should be nil")
end

-- Block 72: exact boundary at max -> pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 100, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 200, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = 300, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	assert(result.passed == true, "Block 72: Count 4 == max 4 should pass")
	assert(result.reason == nil, "Block 72: Reason should be nil")
end

-- Block 73: above max -> fail
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 100, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 200, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = 300, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_E", position = { x = 400, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 700, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	assert(result.passed == false, "Block 73: Count 5 > max 4 should fail")
	assert(result.reason ~= nil, "Block 73: Reason should describe the violation")
	assert(string.find(result.reason, "5") ~= nil, "Block 73: Reason should include total count")
end

-- Block 74: mixed tags under cap after filtering -> pass
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 100, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "OtherZone_C", position = { x = 200, y = 0, z = 0 }, radius = 10, tag = "GiantControl" },
		{ name = "OtherZone_D", position = { x = 300, y = 0, z = 0 }, radius = 10, tag = "GiantControl" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 500, y = 0, z = 0 } },
	})
	-- Filtered GiantCapture count is 2 -> pass
	local result = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	assert(result.passed == true, "Block 74: Non-GiantCapture zones should be ignored in total count")
	assert(result.reason == nil, "Block 74: Reason should be nil")
end

-- Block 75: mixed tags above cap after filtering -> fail
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 100, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 200, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = 300, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_E", position = { x = 400, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "OtherZone_F", position = { x = 500, y = 0, z = 0 }, radius = 10, tag = "GiantControl" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 700, y = 0, z = 0 } },
	})
	-- Filtered GiantCapture count is 5 -> fail
	local result = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	assert(result.passed == false, "Block 75: Filtered GiantCapture count above max should fail")
end

-- Block 76: deterministic failure reporting / stable repeat behavior
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_B", position = { x = 100, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_C", position = { x = 200, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_D", position = { x = 300, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
		{ name = "GiantCaptureZone_E", position = { x = 400, y = 0, z = 0 }, radius = 10, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 700, y = 0, z = 0 } },
	})
	local resultA = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	local resultB = RealmCaptureZoneValidator.captureZoneTotalCap(descriptor, config)
	assert(resultA.passed == false, "Block 76: First run should fail")
	assert(resultB.passed == false, "Block 76: Second run should fail")
	assert(resultA.reason == resultB.reason, "Block 76: Failure reason should be deterministic and stable")
end

print("✓ realm_capture_zone.spec.luau: all 76 blocks passed")

-- ── Slice 23: capture_zone_protected_zone_clearance ─────────────────────────

-- Block 77: Vacuous pass (no capture zones)
do
	local descriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{
				name = "SharedHubSafeZone",
				position = { x = 0, y = 0, z = 0 },
				radius = 20,
				tag = "SafeZone",
				zoneType = "SharedHub",
			},
		},
		captureZones = {},
		props = {},
		routeGraph = { nodes = {}, edges = {} },
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneProtectedZoneClearance(descriptor, config)
	assert(result.passed == true, "Block 77: no capture zones should vacuously pass")
end

-- Block 78: Shared hub is always no-capture
do
	local descriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{
				name = "SharedHubSafeZone",
				position = { x = 0, y = 0, z = 0 },
				radius = 20,
				tag = "SafeZone",
				zoneType = "SharedHub",
			},
		},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 10, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = { nodes = {}, edges = {} },
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneProtectedZoneClearance(descriptor, config)
	assert(result.passed == false, "Block 78: overlap with SharedHub safe zone must fail")
	assert(reasonContains(result.reason, "SharedHub"), "Block 78: reason should include SharedHub type")
end

-- Block 79: Realm entry protection active rejects overlap
do
	local descriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{
				name = "RealmEntrySafeZone",
				position = { x = 0, y = 0, z = 0 },
				radius = 20,
				tag = "SafeZone",
				zoneType = "RealmEntry",
				protectionEndsAt = 120,
			},
		},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 10, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = { nodes = {}, edges = {} },
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneProtectedZoneClearance(descriptor, config)
	assert(result.passed == false, "Block 79: active RealmEntry protection must fail")
	assert(
		reasonContains(result.reason, "realm_entry_protected"),
		"Block 79: reason should include entry-protected reason"
	)
end

-- Block 80: Realm entry protection expired allows placement
do
	local descriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{
				name = "RealmEntrySafeZone",
				position = { x = 0, y = 0, z = 0 },
				radius = 20,
				tag = "SafeZone",
				zoneType = "RealmEntry",
				protectionEndsAt = 50,
			},
		},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 10, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = { nodes = {}, edges = {} },
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneProtectedZoneClearance(descriptor, config)
	assert(result.passed == true, "Block 80: expired RealmEntry protection should allow placement")
end

-- Block 81: Realm exit is protected
do
	local descriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{
				name = "RealmExitSafeZone",
				position = { x = 0, y = 0, z = 0 },
				radius = 20,
				tag = "SafeZone",
				zoneType = "RealmExit",
			},
		},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 10, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = { nodes = {}, edges = {} },
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneProtectedZoneClearance(descriptor, config)
	assert(result.passed == false, "Block 81: overlap with RealmExit safe zone must fail")
	assert(
		reasonContains(result.reason, "realm_exit_protected"),
		"Block 81: reason should include realm-exit protection"
	)
end

-- Block 82: Unknown safe-zone type rejects safely
do
	local descriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{
				name = "UnknownSafeZone",
				position = { x = 0, y = 0, z = 0 },
				radius = 20,
				tag = "SafeZone",
				zoneType = "AlienZone",
			},
		},
		captureZones = {
			{ name = "GiantCaptureZone_A", position = { x = 40, y = 0, z = 0 }, radius = 5, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = { nodes = {}, edges = {} },
	} :: RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneProtectedZoneClearance(descriptor, config)
	assert(result.passed == false, "Block 82: unknown safe-zone type should reject deterministically")
	assert(reasonContains(result.reason, "unsupported zone type"), "Block 82: reason should mention unsupported type")
end

-- Block 83: Vacuous pass when giantRoutes is empty
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	local result = RealmCaptureZoneValidator.captureZoneGiantRouteSeparation(descriptor, config)
	assert(result.passed == true, "Block 83: Should vacuously pass with empty giantRoutes")
end

-- Block 84: Valid giant-route separation passes
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 50, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	descriptor.giantRoutes = {
		{ name = "GiantRoute_PlazaToHearth", position = { x = 0, y = 0, z = 0 }, widthStuds = 18 },
	}
	local result = RealmCaptureZoneValidator.captureZoneGiantRouteSeparation(descriptor, config)
	assert(result.passed == true, "Block 84: Should pass with sufficient giant-route separation")
end

-- Block 85: Invalid giant-route separation fails
do
	local descriptor = makeDescriptor({
		{ name = "GiantCaptureZone_A", position = { x = 20, y = 0, z = 0 }, radius = 15, tag = "GiantCapture" },
	}, {
		{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
	})
	descriptor.giantRoutes = {
		{ name = "GiantRoute_PlazaToHearth", position = { x = 0, y = 0, z = 0 }, widthStuds = 18 },
	}
	local result = RealmCaptureZoneValidator.captureZoneGiantRouteSeparation(descriptor, config)
	assert(result.passed == false, "Block 85: Should fail when giant route is too close to capture zone")
	assert(reasonContains(result.reason, "giant route"), "Block 85: reason should mention giant route")
end

print("✓ realm_capture_zone.spec.luau: all 85 blocks passed")
