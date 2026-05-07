local RealmChokepointValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmChokepointValidator")

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

-- ============================================================
-- Shared test data
-- ============================================================

-- Prototype route graph: bipartite diamond
--
--   TinyfolkSpawn (spawn, -12,0.5,0)
--     ├─▶ RouteNorth (waypoint, 0,0,-90) ─▶ EscapeRoute_A (escape, 0,1,170)
--     └─▶ RouteSouth (waypoint, 0,0, 90) ─▶ EscapeRoute_A
--
-- Both directions stored; 2 edge-disjoint spawn-to-escape paths.
local PROTOTYPE_ROUTE_GRAPH = {
	nodes = {
		{ name = "TinyfolkSpawn",  position = { x = -12, y = 0.5, z = 0   }, nodeType = "spawn"    },
		{ name = "RouteNorth",     position = { x = 0,   y = 0,   z = -90 }, nodeType = "waypoint" },
		{ name = "RouteSouth",     position = { x = 0,   y = 0,   z = 90  }, nodeType = "waypoint" },
		{ name = "EscapeRoute_A",  position = { x = 0,   y = 1,   z = 170 }, nodeType = "escape",  tier = "primary"  },
		{ name = "EscapeRoute_B",  position = { x = -90, y = 1,   z = 170 }, nodeType = "escape",  tier = "fallback" },
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

-- Standard config: need 2 independent escape paths, filter "GiantControl" zones.
local STANDARD_CONFIG = {
	zoneTagFilter                      = "GiantControl",
	minimumDisjointPathCount           = 2,
	requireFallbackEscapeReachability  = false,
}

-- Relaxed config: only 1 path required.
local RELAXED_CONFIG = {
	zoneTagFilter                      = "GiantControl",
	minimumDisjointPathCount           = 1,
	requireFallbackEscapeReachability  = false,
}

local EMPTY_SPAWNS        = {}
local EMPTY_ESCAPE_ROUTES = {}
local EMPTY_RETURN_POINTS = {}
local EMPTY_STATIONS      = {}
local EMPTY_SITES         = {}
local EMPTY_BOARDS        = {}
local EMPTY_CONTROL_ZONES = {}

local function run()

	-- ============================================================
	-- BLOCK 1: Prototype route graph, no control zones
	-- 2 paths (north and south) survive → PASS (min=2)
	-- ============================================================
	local noZones = {
		spawns            = EMPTY_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = EMPTY_CONTROL_ZONES,
		props             = {},
		routeGraph        = PROTOTYPE_ROUTE_GRAPH,
	}
	local r1 = RealmChokepointValidator.ValidateChokepoints(noZones, STANDARD_CONFIG)
	assertEqual(r1.passed, true, "block1 overall pass")
	assertCheckPassed(
		requireResult(r1.results, "choke_point_escape_reachability", "block1"),
		"block1 no zones → 2 paths survive"
	)

	-- ============================================================
	-- BLOCK 2: Zone exactly on RouteNorth (0,0,-90), radius 5
	-- RouteNorth is blocked; all 4 edges touching it are removed.
	-- Only RouteSouth path survives → 1 path → FAIL (min=2)
	-- ============================================================
	local zoneBlocksNorth = {
		spawns            = EMPTY_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "Zone_North", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = PROTOTYPE_ROUTE_GRAPH,
	}
	local r2 = RealmChokepointValidator.ValidateChokepoints(zoneBlocksNorth, STANDARD_CONFIG)
	assertEqual(r2.passed, false, "block2 overall fail")
	assertCheckFailed(
		requireResult(r2.results, "choke_point_escape_reachability", "block2"),
		"block2 zone blocks north → 1 path < min=2"
	)

	-- ============================================================
	-- BLOCK 3: Two zones — one on RouteNorth, one on RouteSouth
	-- Both waypoints blocked; no route edges remain.
	-- 0 paths → FAIL (min=2)
	-- ============================================================
	local zoneBothRoutes = {
		spawns            = EMPTY_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "Zone_North", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
			{ name = "Zone_South", position = { x = 0, y = 0, z = 90  }, radius = 5, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = PROTOTYPE_ROUTE_GRAPH,
	}
	local r3 = RealmChokepointValidator.ValidateChokepoints(zoneBothRoutes, STANDARD_CONFIG)
	assertEqual(r3.passed, false, "block3 overall fail")
	assertCheckFailed(
		requireResult(r3.results, "choke_point_escape_reachability", "block3"),
		"block3 both routes blocked → 0 paths < min=2"
	)

	-- ============================================================
	-- BLOCK 4: Zone far from all nodes — (200,0,200) radius 30
	-- No node within range; all edges survive.
	-- 2 paths → PASS (min=2)
	-- ============================================================
	local zoneDistant = {
		spawns            = EMPTY_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "Zone_Far", position = { x = 200, y = 0, z = 200 }, radius = 30, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = PROTOTYPE_ROUTE_GRAPH,
	}
	local r4 = RealmChokepointValidator.ValidateChokepoints(zoneDistant, STANDARD_CONFIG)
	assertEqual(r4.passed, true, "block4 overall pass")
	assertCheckPassed(
		requireResult(r4.results, "choke_point_escape_reachability", "block4"),
		"block4 distant zone → 2 paths unaffected"
	)

	-- ============================================================
	-- BLOCK 5: Zone blocks RouteNorth, but config min=1 (relaxed)
	-- RouteSouth path survives → 1 path ≥ min=1 → PASS
	-- ============================================================
	local relaxedWithBlockedNorth = {
		spawns            = EMPTY_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = {
			{ name = "Zone_North", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
		},
		props             = {},
		routeGraph        = PROTOTYPE_ROUTE_GRAPH,
	}
	local r5 = RealmChokepointValidator.ValidateChokepoints(relaxedWithBlockedNorth, RELAXED_CONFIG)
	assertEqual(r5.passed, true, "block5 overall pass")
	assertCheckPassed(
		requireResult(r5.results, "choke_point_escape_reachability", "block5"),
		"block5 relaxed min=1, north blocked → 1 path ≥ 1"
	)

	-- ============================================================
	-- BLOCK 6: Empty route graph, no zones → vacuous pass
	-- No spawn or escape nodes registered; nothing to validate.
	-- ============================================================
	local emptyGraph = {
		spawns            = EMPTY_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = EMPTY_CONTROL_ZONES,
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r6 = RealmChokepointValidator.ValidateChokepoints(emptyGraph, STANDARD_CONFIG)
	assertEqual(r6.passed, true, "block6 overall pass")
	assertCheckPassed(
		requireResult(r6.results, "choke_point_escape_reachability", "block6"),
		"block6 empty graph → vacuous pass"
	)

	print("realm_choke_point: all checks passed")
end

run()
