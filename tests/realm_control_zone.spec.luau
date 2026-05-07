local RealmControlZoneValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmControlZoneValidator")

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
		error(string.format("expected non-empty reason [%s id=%s]", label, check.id))
	end
end

local function requireResult(results, id, context)
	for _, check in results do
		if check.id == id then
			return check
		end
	end
	error(string.format("check id=%s not present [%s]", id, context))
end

-- Standard config for Giant control zone checks
-- minimumSpawnZoneSeparationStuds=50 covers spawn being well outside grab radius (18) + approach buffer
-- minimumStationZonePerimeterStuds=5 is small buffer beyond activation range (16) for safe approach
-- minimumEscapeRouteZonePerimeterStuds=10 ensures escape isn't threatened
local STANDARD_CONFIG = {
	zoneTagFilter                          = "GiantControl",
	minimumSpawnZoneSeparationStuds        = 50,
	minimumStationZonePerimeterStuds       = 5,
	minimumEscapeRouteZonePerimeterStuds   = 10,
}

-- Prototype positions (from Layout.model.json):
--   TinyfolkSpawn:    (-12, 0.5, 0)    dist from (12,0.5,0) = 24 studs (< 50)
--   WorkStation_A:    (20, 3, 0)       dist from (12,0.5,0) = 8.1 studs; perimeter = 8.1 - 30 = -21.9 (inside)
--   MiningStation_A:  (36, 3, 0)       dist from (12,0.5,0) = 24.1 studs; perimeter = 24.1 - 30 = -5.9 (inside)
--   Shrine_A:         (-20, 4, 0)      dist from (12,0.5,0) = 32.1 studs; perimeter = 32.1 - 30 = 2.1 (barely outside)
--   EscapeRoute_A:    (0, 1, 170)      dist from (12,0.5,0) = 170 studs; perimeter = 170 - 30 = 140 (safe)

local PROTOTYPE_SPAWNS = {
	{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	{ name = "GiantSpawn",    position = { x = 12,  y = 0.5, z = 0 } },
}
local PROTOTYPE_STATIONS = {
	{ name = "WorkStation_A",   position = { x = 20,  y = 3,   z = 0 } },
	{ name = "MiningStation_A", position = { x = 36,  y = 3,   z = 0 } },
	{ name = "Shrine_A",        position = { x = -20, y = 4,   z = 0 } },
}
local PROTOTYPE_ESCAPE_ROUTES = {
	{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
}
local EMPTY_RETURN_POINTS = {}
local EMPTY_SITES = {}
local EMPTY_BOARDS = {}

-- Giant control zone as placed in prototype: centered on GiantSpawn (12, 0.5, 0), radius 30
local PROTOTYPE_CONTROL_ZONE = {
	{ name = "GiantControlZone_A", position = { x = 12, y = 0.5, z = 0 }, radius = 30, tag = "GiantControl" },
}

local PROTOTYPE_ROUTE_GRAPH = {
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
}

local EMPTY_ROUTE_GRAPH = { nodes = {}, edges = {} }

local PROTOTYPE_DESCRIPTOR = {
	spawns            = PROTOTYPE_SPAWNS,
	escapeRoutes      = PROTOTYPE_ESCAPE_ROUTES,
	returnPoints      = EMPTY_RETURN_POINTS,
	stations          = PROTOTYPE_STATIONS,
	constructionSites = EMPTY_SITES,
	upgradeBoards     = EMPTY_BOARDS,
	controlZones      = PROTOTYPE_CONTROL_ZONE,
	props             = {},
	routeGraph        = PROTOTYPE_ROUTE_GRAPH,
}

local function run()

	-- ============================================================
	-- BLOCK 1: Prototype map with aggressive zone placement
	-- GiantControlZone_A at (12, 0.5, 0), radius 30
	-- spawn_safety: FAIL (TinyfolkSpawn 24 studs < 50)
	-- station_access: FAIL (WorkStation/MiningStation inside, Shrine barely outside)
	-- escape_route_safety: PASS (EscapeRoute 140 studs outside > 10)
	-- ============================================================
	local r1 = RealmControlZoneValidator.ValidateControlZones(PROTOTYPE_DESCRIPTOR, STANDARD_CONFIG)
	assertEqual(r1.passed, false, "prototype overall fail (aggressive zone)")
	assertEqual(#r1.results, 3, "prototype result count")

	assertCheckFailed(
		requireResult(r1.results, "giant_zone_spawn_safety", "prototype"),
		"prototype spawn_safety fails (zone covers spawns)"
	)
	assertCheckFailed(
		requireResult(r1.results, "giant_zone_station_access", "prototype"),
		"prototype station_access fails (stations inside zone)"
	)
	assertCheckPassed(
		requireResult(r1.results, "giant_zone_escape_route_safety", "prototype"),
		"prototype escape_route_safety passes (route far away)"
	)

	-- ============================================================
	-- BLOCK 2: Zone repositioned away from core area
	-- GiantControlZone_A at (120, 0.5, 0), radius 30
	-- All objectives safely outside and far from zone
	-- All 3 checks should pass
	-- ============================================================
	local repositionedZone = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = PROTOTYPE_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = PROTOTYPE_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "GiantControlZone_A", position = { x = 120, y = 0.5, z = 0 }, radius = 30, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r2 = RealmControlZoneValidator.ValidateControlZones(repositionedZone, STANDARD_CONFIG)
	assertEqual(r2.passed, true, "repositioned zone overall pass")
	for _, check in r2.results do
		assertCheckPassed(check, "repositioned zone all pass")
	end

	-- ============================================================
	-- BLOCK 3: Zone positioned to block escape route
	-- GiantControlZone_A at (5, 1, 175), radius 30
	-- Escape route at (0, 1, 170) is only 5.1 studs away; perimeter ~0 (just barely outside)
	-- escape_route_safety should fail (0 < 10)
	-- ============================================================
	local zoneBlocksEscape = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = PROTOTYPE_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = PROTOTYPE_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "GiantControlZone_A", position = { x = 5, y = 1, z = 175 }, radius = 30, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r3 = RealmControlZoneValidator.ValidateControlZones(zoneBlocksEscape, STANDARD_CONFIG)
	assertEqual(r3.passed, false, "zone blocks escape overall fail")
	assertCheckFailed(
		requireResult(r3.results, "giant_zone_escape_route_safety", "zone blocks escape"),
		"escape_route_safety fails when zone threatens route"
	)

	-- ============================================================
	-- BLOCK 4: Multiple control zones
	-- Zone A at (12, 0.5, 0), zone B at (80, 0.5, 0), both radius 30
	-- spawn_safety: finds spawns outside all zones (at least one safe)
	-- station_access: must check each station against all zones
	-- escape_route_safety: must check route against all zones
	-- Zone B doesn't threaten anything; Zone A creates same failures as Block 1
	-- ============================================================
	local multiZone = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = PROTOTYPE_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = PROTOTYPE_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "GiantControlZone_A", position = { x = 12, y = 0.5, z = 0 }, radius = 30, tag = "GiantControl" },
			{ name = "GiantControlZone_B", position = { x = 80, y = 0.5, z = 0 }, radius = 30, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r4 = RealmControlZoneValidator.ValidateControlZones(multiZone, STANDARD_CONFIG)
	assertEqual(r4.passed, false, "multiple zones overall fail (Zone A still aggressive)")
	assertCheckFailed(
		requireResult(r4.results, "giant_zone_spawn_safety", "multiple zones"),
		"spawn_safety fails with multiple zones"
	)
	assertCheckFailed(
		requireResult(r4.results, "giant_zone_station_access", "multiple zones"),
		"station_access fails with Zone A"
	)
	assertCheckPassed(
		requireResult(r4.results, "giant_zone_escape_route_safety", "multiple zones"),
		"escape_route_safety passes (both zones far from route)"
	)

	-- ============================================================
	-- BLOCK 5: Zone perimeter edge case
	-- GiantControlZone at (35, 3, 0), radius 35
	-- WorkStation_A at (20, 3, 0): dist = 15 studs; perimeter = 15 - 35 = -20 (inside) → FAIL
	-- MiningStation_A at (36, 3, 0): dist = 1 stud; perimeter = 1 - 35 = -34 (inside) → FAIL
	-- Shrine_A at (-20, 4, 0): dist ~55 studs; perimeter = 55 - 35 = 20 (outside, safe) → PASS
	-- station_access should fail (two stations inside)
	-- ============================================================
	local zonePerimeterEdge = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = PROTOTYPE_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = PROTOTYPE_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "GiantControlZone_A", position = { x = 35, y = 3, z = 0 }, radius = 35, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r5 = RealmControlZoneValidator.ValidateControlZones(zonePerimeterEdge, STANDARD_CONFIG)
	assertEqual(r5.passed, false, "edge case overall fail")
	assertCheckFailed(
		requireResult(r5.results, "giant_zone_station_access", "edge case"),
		"station_access fails when some stations inside, some outside"
	)

	print("realm_control_zone: all checks passed")
end

run()
