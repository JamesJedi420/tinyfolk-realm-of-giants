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

-- Prototype route graph (5 nodes, 10 edges — from TIN-168):
--
--   TinyfolkSpawn (spawn)
--     ├─▶ RouteNorth (waypoint) ─▶ EscapeRoute_A (escape, primary)
--     │                          ─▶ EscapeRoute_B (escape, fallback)
--     └─▶ RouteSouth (waypoint) ─▶ EscapeRoute_A
--
-- EscapeRoute_B reachable only via RouteNorth (no direct RouteSouth edge).
local PROTOTYPE_NODES = {
	{ name = "TinyfolkSpawn",  position = { x = -12, y = 0.5, z = 0   }, nodeType = "spawn"    },
	{ name = "RouteNorth",     position = { x = 0,   y = 0,   z = -90 }, nodeType = "waypoint" },
	{ name = "RouteSouth",     position = { x = 0,   y = 0,   z = 90  }, nodeType = "waypoint" },
	{ name = "EscapeRoute_A",  position = { x = 0,   y = 1,   z = 170 }, nodeType = "escape",  tier = "primary"  },
	{ name = "EscapeRoute_B",  position = { x = -90, y = 1,   z = 170 }, nodeType = "escape",  tier = "fallback" },
}

local PROTOTYPE_EDGES = {
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
}

local EMPTY_CONTROL_ZONES = {}

-- Config that requires fallback escape reachability.
local REQUIRE_FALLBACK_CONFIG = {
	zoneTagFilter                     = "GiantControl",
	minimumDisjointPathCount          = 1,
	requireFallbackEscapeReachability = true,
}

-- Config that skips the fallback check.
local SKIP_FALLBACK_CONFIG = {
	zoneTagFilter                     = "GiantControl",
	minimumDisjointPathCount          = 1,
	requireFallbackEscapeReachability = false,
}

local function makeDescriptor(nodes, edges, controlZones)
	return {
		spawns            = {},
		escapeRoutes      = {},
		returnPoints      = {},
		stations          = {},
		constructionSites = {},
		upgradeBoards     = {},
		controlZones      = controlZones,
		captureZones      = {},
		props             = {},
		routeGraph        = { nodes = nodes, edges = edges },
	}
end

local function run()

	-- ============================================================
	-- BLOCK 1: Prototype graph, no zones
	-- EscapeRoute_B is unblocked and reachable via RouteNorth → PASS
	-- ============================================================
	local r1 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(PROTOTYPE_NODES, PROTOTYPE_EDGES, EMPTY_CONTROL_ZONES),
		REQUIRE_FALLBACK_CONFIG
	)
	assertEqual(r1.passed, true, "block1 overall pass")
	assertCheckPassed(
		requireResult(r1.results, "choke_point_fallback_reachability", "block1"),
		"block1 no zones → EscapeRoute_B reachable"
	)

	-- ============================================================
	-- BLOCK 2: Zone blocks RouteNorth (the only path to EscapeRoute_B)
	-- RouteNorth at (0,0,-90), zone radius 5 → RouteNorth blocked.
	-- All edges touching RouteNorth removed; EscapeRoute_B unreachable.
	-- choke_point_fallback_reachability → FAIL
	-- ============================================================
	local r2 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(PROTOTYPE_NODES, PROTOTYPE_EDGES, {
			{ name = "Zone_North", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
		}),
		REQUIRE_FALLBACK_CONFIG
	)
	assertCheckFailed(
		requireResult(r2.results, "choke_point_fallback_reachability", "block2"),
		"block2 RouteNorth blocked → EscapeRoute_B unreachable"
	)

	-- ============================================================
	-- BLOCK 3: Zone sits directly on EscapeRoute_B (-90,1,170), radius 5
	-- EscapeRoute_B is blocked itself → treated as blocked node, not a
	-- candidate fallback → vacuous pass (no unblocked fallback nodes).
	-- choke_point_fallback_reachability → PASS (vacuous)
	-- ============================================================
	local r3 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(PROTOTYPE_NODES, PROTOTYPE_EDGES, {
			{ name = "Zone_B", position = { x = -90, y = 1, z = 170 }, radius = 5, tag = "GiantControl" },
		}),
		REQUIRE_FALLBACK_CONFIG
	)
	assertCheckPassed(
		requireResult(r3.results, "choke_point_fallback_reachability", "block3"),
		"block3 EscapeRoute_B itself blocked → vacuous pass (no unblocked fallback candidates)"
	)

	-- ============================================================
	-- BLOCK 4: Zone blocks RouteNorth, but EscapeRoute_B also connected
	-- to RouteSouth via an extra edge (added inline to this descriptor).
	-- RouteSouth survives → EscapeRoute_B reachable via RouteSouth → PASS
	-- ============================================================
	local edgesWithAltPath = {}
	for _, e in PROTOTYPE_EDGES do
		table.insert(edgesWithAltPath, e)
	end
	table.insert(edgesWithAltPath, { from = "RouteSouth",    to = "EscapeRoute_B", distance = 100 })
	table.insert(edgesWithAltPath, { from = "EscapeRoute_B", to = "RouteSouth",    distance = 100 })

	local r4 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(PROTOTYPE_NODES, edgesWithAltPath, {
			{ name = "Zone_North", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
		}),
		REQUIRE_FALLBACK_CONFIG
	)
	assertCheckPassed(
		requireResult(r4.results, "choke_point_fallback_reachability", "block4"),
		"block4 alt path via RouteSouth → EscapeRoute_B still reachable"
	)

	-- ============================================================
	-- BLOCK 5: requireFallbackEscapeReachability = false
	-- Zone blocks RouteNorth; fallback check is skipped entirely → PASS
	-- ============================================================
	local r5 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(PROTOTYPE_NODES, PROTOTYPE_EDGES, {
			{ name = "Zone_North", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
		}),
		SKIP_FALLBACK_CONFIG
	)
	assertCheckPassed(
		requireResult(r5.results, "choke_point_fallback_reachability", "block5"),
		"block5 requireFallbackEscapeReachability=false → check skipped, always pass"
	)

	-- ============================================================
	-- BLOCK 6: Empty route graph, no zones, requireFallback=true
	-- No fallback escape nodes registered → vacuous pass
	-- ============================================================
	local r6 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor({}, {}, EMPTY_CONTROL_ZONES),
		REQUIRE_FALLBACK_CONFIG
	)
	assertEqual(r6.passed, true, "block6 overall pass")
	assertCheckPassed(
		requireResult(r6.results, "choke_point_fallback_reachability", "block6"),
		"block6 empty graph → vacuous pass"
	)

	print("realm_choke_point_fallback: all checks passed")
end

run()
