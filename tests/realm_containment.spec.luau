--!strict

local RealmContainmentValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmContainmentValidator")

type RealmDescriptor = RealmContainmentValidator.RealmDescriptor
type NamedNode = RealmContainmentValidator.NamedNode
type RouteEdge = RealmContainmentValidator.RouteEdge
type NamedZone = RealmContainmentValidator.NamedZone
type RealmContainmentConfig = RealmContainmentValidator.RealmContainmentConfig

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
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

local function requireResult(results, id, context)
	for _, check in results do
		if check.id == id then
			return check
		end
	end
	error(string.format("check id=%s not present in results [%s]", id, context))
end

-- ============================================================
-- Shared prototype route graph
--
--   TinyfolkSpawn (spawn)  ──►  RouteNorth (waypoint)  ──►  EscapeRoute_A (escape, primary)
--                          ──►  RouteSouth (waypoint)  ──►  EscapeRoute_A
--   RouteNorth             ──►  EscapeRoute_B (escape, fallback)
--   (all edges are bidirectional via reverse entries)
-- ============================================================
local PROTOTYPE_ROUTE_GRAPH: { nodes: { NamedNode }, edges: { RouteEdge } } = {
	nodes = {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "RouteNorth", position = { x = 0, y = 0, z = -90 }, nodeType = "waypoint" },
		{ name = "RouteSouth", position = { x = 0, y = 0, z = 90 }, nodeType = "waypoint" },
		{
			name = "EscapeRoute_A",
			position = { x = 0, y = 1, z = 170 },
			nodeType = "escape",
			tier = "primary",
		},
		{
			name = "EscapeRoute_B",
			position = { x = -90, y = 1, z = 170 },
			nodeType = "escape",
			tier = "fallback",
		},
	},
	edges = {
		{ from = "TinyfolkSpawn", to = "RouteNorth", distance = 90 },
		{ from = "TinyfolkSpawn", to = "RouteSouth", distance = 90 },
		{ from = "RouteNorth", to = "EscapeRoute_A", distance = 80 },
		{ from = "RouteSouth", to = "EscapeRoute_A", distance = 80 },
		{ from = "RouteNorth", to = "EscapeRoute_B", distance = 90 },
		{ from = "RouteNorth", to = "TinyfolkSpawn", distance = 90 },
		{ from = "RouteSouth", to = "TinyfolkSpawn", distance = 90 },
		{ from = "EscapeRoute_A", to = "RouteNorth", distance = 80 },
		{ from = "EscapeRoute_A", to = "RouteSouth", distance = 80 },
		{ from = "EscapeRoute_B", to = "RouteNorth", distance = 90 },
	},
}

local EMPTY_ROUTE_GRAPH: { nodes: { NamedNode }, edges: { RouteEdge } } = { nodes = {}, edges = {} }

local STANDARD_CONFIG: RealmContainmentConfig = {
	captureZoneTagFilter = "GiantCapture",
	controlZoneTagFilter = "GiantControl",
}

local function run()
	-- ============================================================
	-- BLOCK 1: No capture zones → vacuous pass
	-- ============================================================
	local noCaptureZones: RealmDescriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {},
		captureZones = {},
		props = {},
		routeGraph = PROTOTYPE_ROUTE_GRAPH,
	}
	local r1 = RealmContainmentValidator.ValidateContainment(noCaptureZones, STANDARD_CONFIG)
	assertEqual(r1.passed, true, "block1 overall pass")
	assertEqual(#r1.results, 1, "block1 result count")
	assertCheckPassed(
		requireResult(r1.results, "containment_capture_escape_reachability", "block1"),
		"block1 no capture zones → vacuous pass"
	)

	-- ============================================================
	-- BLOCK 2: Zone near RouteNorth (0,0,-90), no control zones.
	-- Nearest unblocked node is RouteNorth; BFS reaches EscapeRoute_A → PASS
	-- ============================================================
	local zoneClearPath: RealmDescriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {},
		captureZones = {
			{ name = "CaptureZone_A", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = PROTOTYPE_ROUTE_GRAPH,
	}
	local r2 = RealmContainmentValidator.ValidateContainment(zoneClearPath, STANDARD_CONFIG)
	assertEqual(r2.passed, true, "block2 overall pass")
	assertCheckPassed(
		requireResult(r2.results, "containment_capture_escape_reachability", "block2"),
		"block2 zone near RouteNorth, no blocking → escape reachable"
	)

	-- ============================================================
	-- BLOCK 3: Zone at TinyfolkSpawn (-12,0.5,0).
	-- Control zones block BOTH RouteNorth and RouteSouth.
	-- No unblocked path to any escape node → FAIL
	-- ============================================================
	local zoneBothPathsBlocked: RealmDescriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{ name = "BlockNorth", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
			{ name = "BlockSouth", position = { x = 0, y = 0, z = 90 }, radius = 5, tag = "GiantControl" },
		},
		captureZones = {
			{ name = "CaptureZone_A", position = { x = -12, y = 0.5, z = 0 }, radius = 5, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = PROTOTYPE_ROUTE_GRAPH,
	}
	local r3 = RealmContainmentValidator.ValidateContainment(zoneBothPathsBlocked, STANDARD_CONFIG)
	assertEqual(r3.passed, false, "block3 overall fail")
	assertCheckFailed(
		requireResult(r3.results, "containment_capture_escape_reachability", "block3"),
		"block3 both waypoints blocked → no escape reachable from capture zone"
	)

	-- ============================================================
	-- BLOCK 4: Zone at TinyfolkSpawn (-12,0.5,0).
	-- Control zone blocks only RouteNorth; RouteSouth path survives → PASS
	-- ============================================================
	local zoneOnePathSurvives: RealmDescriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{ name = "BlockNorth", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
		},
		captureZones = {
			{ name = "CaptureZone_A", position = { x = -12, y = 0.5, z = 0 }, radius = 5, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = PROTOTYPE_ROUTE_GRAPH,
	}
	local r4 = RealmContainmentValidator.ValidateContainment(zoneOnePathSurvives, STANDARD_CONFIG)
	assertEqual(r4.passed, true, "block4 overall pass")
	assertCheckPassed(
		requireResult(r4.results, "containment_capture_escape_reachability", "block4"),
		"block4 RouteNorth blocked, RouteSouth survives → escape reachable"
	)

	-- ============================================================
	-- BLOCK 5: Two capture zones.
	-- CaptureZone_A has a clear path; CaptureZone_B has both paths blocked.
	-- Overall → FAIL (one zone fails)
	-- ============================================================
	local twoZonesOneFails: RealmDescriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {
			{ name = "BlockNorth", position = { x = 0, y = 0, z = -90 }, radius = 5, tag = "GiantControl" },
			{ name = "BlockSouth", position = { x = 0, y = 0, z = 90 }, radius = 5, tag = "GiantControl" },
		},
		captureZones = {
			-- Zone near EscapeRoute_A (170 studs away from TinyfolkSpawn side): escape is adjacent
			{ name = "CaptureZone_Clear", position = { x = 0, y = 1, z = 170 }, radius = 5, tag = "GiantCapture" },
			-- Zone at TinyfolkSpawn: both waypoints blocked, no path out
			{ name = "CaptureZone_Blocked", position = { x = -12, y = 0.5, z = 0 }, radius = 5, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = PROTOTYPE_ROUTE_GRAPH,
	}
	local r5 = RealmContainmentValidator.ValidateContainment(twoZonesOneFails, STANDARD_CONFIG)
	assertEqual(r5.passed, false, "block5 overall fail")
	assertCheckFailed(
		requireResult(r5.results, "containment_capture_escape_reachability", "block5"),
		"block5 two zones, second has no escape path → overall fail"
	)

	-- ============================================================
	-- BLOCK 6: Capture zone present but route graph is empty.
	-- No unblocked nodes to start BFS from → FAIL
	-- ============================================================
	local zoneEmptyGraph: RealmDescriptor = {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {},
		captureZones = {
			{ name = "CaptureZone_A", position = { x = 0, y = 0, z = 0 }, radius = 5, tag = "GiantCapture" },
		},
		props = {},
		routeGraph = EMPTY_ROUTE_GRAPH,
	}
	local r6 = RealmContainmentValidator.ValidateContainment(zoneEmptyGraph, STANDARD_CONFIG)
	assertEqual(r6.passed, false, "block6 overall fail")
	assertCheckFailed(
		requireResult(r6.results, "containment_capture_escape_reachability", "block6"),
		"block6 empty route graph → no unblocked node, zone fails"
	)

	print("realm_containment: all checks passed")
end

run()
