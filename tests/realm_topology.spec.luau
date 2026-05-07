local RealmTopologyValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmTopologyValidator")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertCheckPassed(check, label)
	if not check.passed then
		error(string.format("expected pass [%s id=%s] but got failure: %s", label, check.id, tostring(check.reason)))
	end
end

local function assertCheckFailed(check, label)
	if check.passed then
		error(string.format("expected failure [%s id=%s] but got pass", label, check.id))
	end
	if type(check.reason) ~= "string" or check.reason == "" then
		error(string.format("expected non-empty reason string [%s id=%s]", label, check.id))
	end
end

local function findResult(results, id)
	for _, check in results do
		if check.id == id then
			return check
		end
	end
	return nil
end

local function requireResult(results, id, context)
	local check = findResult(results, id)
	if not check then
		error(string.format("check id=%s not present in results [%s]", id, context))
	end
	return check
end

local EMPTY_ROUTE_GRAPH = { nodes = {}, edges = {} }

-- ============================================================
-- Prototype map descriptor — positions from Layout.model.json
-- ============================================================
--   TinyfolkSpawn:       (-12, 0.5,   0)
--   GiantSpawn:          ( 12, 0.5,   0)
--   EscapeRoute_A:       (  0, 1,   170)  -- 170 studs from both spawns
--   TinyfolkReturnPoint: (  0, 1,   220)
--   WorkStation_A:       ( 20, 3,     0)
--   MiningStation_A:     ( 36, 3,     0)
--   Warehouse_A:         ( 52, 3.5,   0)
--   Shrine_A:            (-20, 4,     0)
--   Granary_A:           (  4, 3.5,   0)
--   GiantUpgradeBoard_A: ( 32, 4,     0)  -- ~20.3 studs from GiantSpawn (max=32)
--   ConstructionSite_A:  ( 12, 0.5,  32)
local PROTOTYPE_DESCRIPTOR = {
	spawns = {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0   } },
		{ name = "GiantSpawn",    position = { x = 12,  y = 0.5, z = 0   } },
	},
	escapeRoutes = {
		{ name = "EscapeRoute_A", position = { x = 0,   y = 1,   z = 170 } },
	},
	returnPoints = {
		{ name = "TinyfolkReturnPoint", position = { x = 0, y = 1, z = 220 } },
	},
	stations = {
		{ name = "WorkStation_A",   position = { x = 20,  y = 3,   z = 0 } },
		{ name = "MiningStation_A", position = { x = 36,  y = 3,   z = 0 } },
		{ name = "Warehouse_A",     position = { x = 52,  y = 3.5, z = 0 } },
		{ name = "Shrine_A",        position = { x = -20, y = 4,   z = 0 } },
		{ name = "Granary_A",       position = { x = 4,   y = 3.5, z = 0 } },
	},
	constructionSites = {
		{ name = "ConstructionSite_A", position = { x = 12, y = 0.5, z = 32 } },
	},
	upgradeBoards = {
		{ name = "GiantUpgradeBoard_A", position = { x = 32, y = 4, z = 0 } },
	},
	controlZones = {},
	props = {
		{ name = "Cover_A", position = { x = -8,  y = 0.5, z = 0   }, propType = "cover" },
		{ name = "Cover_B", position = { x = 0,   y = 0.5, z = 165 }, propType = "cover" },
	},
	routeGraph = {
		nodes = {
			{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0   }, nodeType = "spawn" },
			{ name = "RouteNorth",    position = { x = 0,   y = 0,   z = -90 }, nodeType = "waypoint" },
			{ name = "RouteSouth",    position = { x = 0,   y = 0,   z = 90  }, nodeType = "waypoint" },
			{ name = "EscapeRoute_A", position = { x = 0,   y = 1,   z = 170 }, nodeType = "escape", tier = "primary"  },
			{ name = "EscapeRoute_B", position = { x = -90, y = 1,   z = 170 }, nodeType = "escape", tier = "fallback" },
		},
		edges = {
			{ from = "TinyfolkSpawn", to = "RouteNorth",    distance = 90 },
			{ from = "TinyfolkSpawn", to = "RouteSouth",    distance = 90 },
			{ from = "RouteNorth",    to = "EscapeRoute_A", distance = 80 },
			{ from = "RouteSouth",    to = "EscapeRoute_A", distance = 80 },
			{ from = "RouteNorth",    to = "EscapeRoute_B", distance = 90 },
			{ from = "RouteNorth",    to = "TinyfolkSpawn", distance = 90 },
			{ from = "RouteSouth",    to = "TinyfolkSpawn", distance = 90 },
			{ from = "EscapeRoute_A", to = "RouteNorth",    distance = 80 },
			{ from = "EscapeRoute_A", to = "RouteSouth",    distance = 80 },
			{ from = "EscapeRoute_B", to = "RouteNorth",    distance = 90 },
		},
	},
}

-- Config values mirroring current prototype configs:
--   EscapeConfig.TriggerRadiusStuds         = 10
--   UpgradeBoardConfig.InteractionRangeStuds = 16
--   StationConfig.ActivationRangeStuds       = 16
--   ConstructionConfig.InteractionRangeStuds = 16
--   StationConfig.RequiredSpecialistRoleByStationId keys
--   ConstructionConfig.CostBySiteId keys
local PROTOTYPE_CONFIG = {
	escapeTriggerRadiusStuds          = 10,
	boardInteractionRangeStuds        = 16,
	stationActivationRangeStuds       = 16,
	constructionInteractionRangeStuds = 16,
	requiredSpecialistStationIds      = { "WorkStation_A", "MiningStation_A" },
	constructionSiteIds               = { "ConstructionSite_A" },
}

local function run()

	-- ============================================================
	-- BLOCK 1: Prototype map — all 8 checks pass
	-- ============================================================
	local fullResult = RealmTopologyValidator.ValidateRealm(PROTOTYPE_DESCRIPTOR, PROTOTYPE_CONFIG)
	assertEqual(fullResult.passed, true, "prototype map overall pass")
	assertEqual(#fullResult.results, 8, "prototype map result count")

	for _, check in fullResult.results do
		assertCheckPassed(check, "prototype map")
	end

	-- Verify each check ID is present
	local expectedIds = {
		"spawn_tinyfolk_exists",
		"spawn_giant_exists",
		"escape_route_exists",
		"return_point_exists",
		"station_coverage",
		"construction_site_coverage",
		"upgrade_board_reachability",
		"escape_route_spawn_separation",
	}
	for _, id in expectedIds do
		requireResult(fullResult.results, id, "prototype map id presence")
	end

	-- ============================================================
	-- BLOCK 2: Failure — missing TinyfolkSpawn
	-- ============================================================
	local noTinyfolkSpawn = {
		spawns              = { { name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } } },
		escapeRoutes        = PROTOTYPE_DESCRIPTOR.escapeRoutes,
		returnPoints        = PROTOTYPE_DESCRIPTOR.returnPoints,
		stations            = PROTOTYPE_DESCRIPTOR.stations,
		constructionSites   = PROTOTYPE_DESCRIPTOR.constructionSites,
		upgradeBoards       = PROTOTYPE_DESCRIPTOR.upgradeBoards,
		controlZones        = {},
		props               = {},
		routeGraph          = EMPTY_ROUTE_GRAPH,
	}
	local r1 = RealmTopologyValidator.ValidateRealm(noTinyfolkSpawn, PROTOTYPE_CONFIG)
	assertEqual(r1.passed, false, "missing TinyfolkSpawn overall fail")
	assertCheckFailed(
		requireResult(r1.results, "spawn_tinyfolk_exists", "missing TinyfolkSpawn"),
		"spawn_tinyfolk_exists fails when missing"
	)

	-- ============================================================
	-- BLOCK 3: Failure — missing GiantSpawn
	-- ============================================================
	local noGiantSpawn = {
		spawns              = { { name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } } },
		escapeRoutes        = PROTOTYPE_DESCRIPTOR.escapeRoutes,
		returnPoints        = PROTOTYPE_DESCRIPTOR.returnPoints,
		stations            = PROTOTYPE_DESCRIPTOR.stations,
		constructionSites   = PROTOTYPE_DESCRIPTOR.constructionSites,
		upgradeBoards       = PROTOTYPE_DESCRIPTOR.upgradeBoards,
		controlZones        = {},
		props               = {},
		routeGraph          = EMPTY_ROUTE_GRAPH,
	}
	local r2 = RealmTopologyValidator.ValidateRealm(noGiantSpawn, PROTOTYPE_CONFIG)
	assertEqual(r2.passed, false, "missing GiantSpawn overall fail")
	assertCheckFailed(
		requireResult(r2.results, "spawn_giant_exists", "missing GiantSpawn"),
		"spawn_giant_exists fails when missing"
	)

	-- ============================================================
	-- BLOCK 4: Failure — no escape routes
	-- ============================================================
	local noEscape = {
		spawns              = PROTOTYPE_DESCRIPTOR.spawns,
		escapeRoutes        = {},
		returnPoints        = PROTOTYPE_DESCRIPTOR.returnPoints,
		stations            = PROTOTYPE_DESCRIPTOR.stations,
		constructionSites   = PROTOTYPE_DESCRIPTOR.constructionSites,
		upgradeBoards       = PROTOTYPE_DESCRIPTOR.upgradeBoards,
		controlZones        = {},
		props               = {},
		routeGraph          = EMPTY_ROUTE_GRAPH,
	}
	local r3 = RealmTopologyValidator.ValidateRealm(noEscape, PROTOTYPE_CONFIG)
	assertEqual(r3.passed, false, "no escape routes overall fail")
	assertCheckFailed(
		requireResult(r3.results, "escape_route_exists", "no escape routes"),
		"escape_route_exists fails when empty"
	)

	-- ============================================================
	-- BLOCK 5: Failure — upgrade board too far from GiantSpawn
	-- Placed at (200, 4, 200) — ~274 studs from GiantSpawn, max=32.
	-- ============================================================
	local boardTooFar = {
		spawns              = PROTOTYPE_DESCRIPTOR.spawns,
		escapeRoutes        = PROTOTYPE_DESCRIPTOR.escapeRoutes,
		returnPoints        = PROTOTYPE_DESCRIPTOR.returnPoints,
		stations            = PROTOTYPE_DESCRIPTOR.stations,
		constructionSites   = PROTOTYPE_DESCRIPTOR.constructionSites,
		upgradeBoards       = {
			{ name = "GiantUpgradeBoard_A", position = { x = 200, y = 4, z = 200 } },
		},
		controlZones        = {},
		props               = {},
		routeGraph          = EMPTY_ROUTE_GRAPH,
	}
	local r4 = RealmTopologyValidator.ValidateRealm(boardTooFar, PROTOTYPE_CONFIG)
	assertEqual(r4.passed, false, "board too far overall fail")
	assertCheckFailed(
		requireResult(r4.results, "upgrade_board_reachability", "board too far"),
		"upgrade_board_reachability fails when board too far"
	)

	-- ============================================================
	-- BLOCK 6: Failure — missing specialist station
	-- ============================================================
	local missingStation = {
		spawns              = PROTOTYPE_DESCRIPTOR.spawns,
		escapeRoutes        = PROTOTYPE_DESCRIPTOR.escapeRoutes,
		returnPoints        = PROTOTYPE_DESCRIPTOR.returnPoints,
		stations            = { { name = "WorkStation_A", position = { x = 20, y = 3, z = 0 } } }, -- MiningStation_A absent
		constructionSites   = PROTOTYPE_DESCRIPTOR.constructionSites,
		upgradeBoards       = PROTOTYPE_DESCRIPTOR.upgradeBoards,
		controlZones        = {},
		props               = {},
		routeGraph          = EMPTY_ROUTE_GRAPH,
	}
	local r5 = RealmTopologyValidator.ValidateRealm(missingStation, PROTOTYPE_CONFIG)
	assertEqual(r5.passed, false, "missing specialist station overall fail")
	assertCheckFailed(
		requireResult(r5.results, "station_coverage", "missing MiningStation_A"),
		"station_coverage fails when station missing"
	)

	-- ============================================================
	-- BLOCK 7: Failure — escape route too close to a spawn
	-- Placed at (12, 0.5, 5) — 5 studs from GiantSpawn, min=15.
	-- ============================================================
	local routeTooClose = {
		spawns              = PROTOTYPE_DESCRIPTOR.spawns,
		escapeRoutes        = {
			{ name = "EscapeRoute_A", position = { x = 12, y = 0.5, z = 5 } },
		},
		returnPoints        = PROTOTYPE_DESCRIPTOR.returnPoints,
		stations            = PROTOTYPE_DESCRIPTOR.stations,
		constructionSites   = PROTOTYPE_DESCRIPTOR.constructionSites,
		upgradeBoards       = PROTOTYPE_DESCRIPTOR.upgradeBoards,
		controlZones        = {},
		props               = {},
		routeGraph          = EMPTY_ROUTE_GRAPH,
	}
	local r6 = RealmTopologyValidator.ValidateRealm(routeTooClose, PROTOTYPE_CONFIG)
	assertEqual(r6.passed, false, "escape route too close to spawn overall fail")
	assertCheckFailed(
		requireResult(r6.results, "escape_route_spawn_separation", "route too close"),
		"escape_route_spawn_separation fails when route too close"
	)

	print("realm_topology: all checks passed")
end

run()
