--!strict

local RealmCaptureZoneValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmCaptureZoneValidator")
local RealmTopologyValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmTopologyValidator")

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
	} :: RealmTopologyValidator.RealmDescriptor
end

local config: RealmCaptureZoneValidator.CaptureZoneConfig = {
	minimumSpawnSeparationStuds = 70,
	minimumEscapeSeparationStuds = 80,
	minimumCaptureRadiusStuds = 8,
	maximumCaptureRadiusStuds = 25,
}

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
	assert(
		string.find(result.reason, "GiantCaptureZone_B") ~= nil,
		"Block 5: Reason should identify the violating zone"
	)
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
	assert(string.find(result.reason, "TinyfolkSpawn_A") ~= nil, "Block 6: Reason should identify the nearest spawn")
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
	} :: RealmTopologyValidator.RealmDescriptor
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
	assert(
		string.find(result.reason, "GiantCaptureZone_B") ~= nil,
		"Block 14: Reason should identify the violating zone"
	)
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
	} :: RealmTopologyValidator.RealmDescriptor
	-- Zone_A at (20,0,0): 180 studs from EscapeRoute_A (pass), 40 studs from EscapeRoute_B (fail)
	local result = RealmCaptureZoneValidator.captureZoneEscapeSeparation(d3, config)
	assert(result.passed == false, "Block 15: Should fail when zone is too close to any escape route")
	assert(string.find(result.reason, "EscapeRoute_B") ~= nil, "Block 15: Reason should identify EscapeRoute_B")
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
	assert(
		string.find(result.reason, "GiantCaptureZone_B") ~= nil,
		"Block 23: Reason should identify the violating zone"
	)
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
	} :: RealmTopologyValidator.RealmDescriptor
	local result = RealmCaptureZoneValidator.captureZoneRadiusBounds(d4, config)
	assert(result.passed == true, "Block 24: Non-GiantCapture tagged zones are not validated by this rule")
	assert(result.reason == nil, "Block 24: Reason should be nil")
end

print("✓ realm_capture_zone.spec.luau: all 24 blocks passed")
