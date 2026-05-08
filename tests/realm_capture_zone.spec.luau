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

local config: RealmCaptureZoneValidator.CaptureZoneConfig = { minimumSpawnSeparationStuds = 70 }

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

print("✓ realm_capture_zone.spec.luau: all 8 blocks passed")
