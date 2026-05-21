--!nocheck

local RealmRouteGraphValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmRouteGraphValidator")

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

local STANDARD_CONFIG = {
	tinyfolkSpawnPrefix = "TinyfolkSpawn",
}

local function makeDescriptor(spawns, escapeRoutes, routeGraphNodes, routeGraphEdges)
	return {
		spawns = spawns,
		escapeRoutes = escapeRoutes,
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {},
		captureZones = {},
		props = {},
		routeGraph = {
			nodes = routeGraphNodes,
			edges = routeGraphEdges or {},
		},
	}
end

local function run()
	-- ============================================================
	-- BLOCK 1: Prototype registration passes both rules.
	-- GiantSpawn is intentionally excluded from spawn registration checks.
	-- ============================================================
	local prototype = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	})
	local r1 = RealmRouteGraphValidator.ValidateRouteGraph(prototype, STANDARD_CONFIG)
	assertEqual(r1.passed, true, "block1 overall pass")
	assertEqual(#r1.results, 4, "block1 result count")
	assertCheckPassed(requireResult(r1.results, "route_graph_spawn_registration", "block1"), "block1 spawn")
	assertCheckPassed(requireResult(r1.results, "route_graph_escape_registration", "block1"), "block1 escape")
	assertCheckPassed(requireResult(r1.results, "route_graph_edge_consistency", "block1"), "block1 edge consistency")
	assertCheckPassed(
		requireResult(r1.results, "route_graph_tinyfolk_only_metadata", "block1"),
		"block1 tinyfolk-only metadata vacuous"
	)

	-- ============================================================
	-- BLOCK 2: Missing tinyfolk spawn node -> spawn registration fails.
	-- ============================================================
	local missingSpawnNode = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	})
	local r2 = RealmRouteGraphValidator.ValidateRouteGraph(missingSpawnNode, STANDARD_CONFIG)
	assertEqual(r2.passed, false, "block2 overall fail")
	assertCheckFailed(requireResult(r2.results, "route_graph_spawn_registration", "block2"), "block2 spawn")
	assertCheckPassed(requireResult(r2.results, "route_graph_escape_registration", "block2"), "block2 escape")
	assertCheckPassed(requireResult(r2.results, "route_graph_edge_consistency", "block2"), "block2 edge consistency")

	-- ============================================================
	-- BLOCK 3: Missing escape node -> escape registration fails.
	-- ============================================================
	local missingEscapeNode = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
	})
	local r3 = RealmRouteGraphValidator.ValidateRouteGraph(missingEscapeNode, STANDARD_CONFIG)
	assertEqual(r3.passed, false, "block3 overall fail")
	assertCheckPassed(requireResult(r3.results, "route_graph_spawn_registration", "block3"), "block3 spawn")
	assertCheckFailed(requireResult(r3.results, "route_graph_escape_registration", "block3"), "block3 escape")
	assertCheckPassed(requireResult(r3.results, "route_graph_edge_consistency", "block3"), "block3 edge consistency")

	-- ============================================================
	-- BLOCK 4: Both missing -> both checks fail.
	-- ============================================================
	local bothMissing = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
	}, {})
	local r4 = RealmRouteGraphValidator.ValidateRouteGraph(bothMissing, STANDARD_CONFIG)
	assertEqual(r4.passed, false, "block4 overall fail")
	assertCheckFailed(requireResult(r4.results, "route_graph_spawn_registration", "block4"), "block4 spawn")
	assertCheckFailed(requireResult(r4.results, "route_graph_escape_registration", "block4"), "block4 escape")
	assertCheckPassed(requireResult(r4.results, "route_graph_edge_consistency", "block4"), "block4 edge consistency")

	-- ============================================================
	-- BLOCK 5: Empty spawn/escape lists -> vacuous pass independently.
	-- ============================================================
	local emptyLists = makeDescriptor({}, {}, {})
	local r5 = RealmRouteGraphValidator.ValidateRouteGraph(emptyLists, STANDARD_CONFIG)
	assertEqual(r5.passed, true, "block5 overall pass")
	assertCheckPassed(requireResult(r5.results, "route_graph_spawn_registration", "block5"), "block5 spawn vacuous")
	assertCheckPassed(requireResult(r5.results, "route_graph_escape_registration", "block5"), "block5 escape vacuous")
	assertCheckPassed(requireResult(r5.results, "route_graph_edge_consistency", "block5"), "block5 edge vacuous")
	assertCheckPassed(
		requireResult(r5.results, "route_graph_tinyfolk_only_metadata", "block5"),
		"block5 metadata vacuous"
	)

	-- ============================================================
	-- BLOCK 6: Valid prototype graph edges -> edge consistency passes.
	-- ============================================================
	local validEdgeGraph = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "RouteNorth", position = { x = 0, y = 0, z = -90 }, nodeType = "waypoint" },
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	}, {
		{ from = "TinyfolkSpawn", to = "RouteNorth", distance = 90 },
		{ from = "RouteNorth", to = "EscapeRoute_A", distance = 80 },
	})
	local r6 = RealmRouteGraphValidator.ValidateRouteGraph(validEdgeGraph, STANDARD_CONFIG)
	assertEqual(r6.passed, true, "block6 overall pass")
	assertCheckPassed(requireResult(r6.results, "route_graph_edge_consistency", "block6"), "block6 edge consistency")

	-- ============================================================
	-- BLOCK 7: Non-existent "to" node -> edge consistency fails.
	-- ============================================================
	local missingToNode = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	}, {
		{ from = "TinyfolkSpawn", to = "GhostToNode", distance = 10 },
	})
	local r7 = RealmRouteGraphValidator.ValidateRouteGraph(missingToNode, STANDARD_CONFIG)
	assertEqual(r7.passed, false, "block7 overall fail")
	local block7 = requireResult(r7.results, "route_graph_edge_consistency", "block7")
	assertCheckFailed(block7, "block7 edge consistency")
	assertEqual(
		string.find(block7.reason :: string, "GhostToNode", 1, true) ~= nil,
		true,
		"block7 reason includes missing to node"
	)

	-- ============================================================
	-- BLOCK 8: Non-existent "from" node -> edge consistency fails.
	-- ============================================================
	local missingFromNode = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	}, {
		{ from = "GhostFromNode", to = "EscapeRoute_A", distance = 10 },
	})
	local r8 = RealmRouteGraphValidator.ValidateRouteGraph(missingFromNode, STANDARD_CONFIG)
	assertEqual(r8.passed, false, "block8 overall fail")
	local block8 = requireResult(r8.results, "route_graph_edge_consistency", "block8")
	assertCheckFailed(block8, "block8 edge consistency")
	assertEqual(
		string.find(block8.reason :: string, "GhostFromNode", 1, true) ~= nil,
		true,
		"block8 reason includes missing from node"
	)

	-- ============================================================
	-- BLOCK 9: Opt-in Tinyfolk-only route metadata passes.
	-- ============================================================
	local metadataConfig = {
		tinyfolkSpawnPrefix = "TinyfolkSpawn",
		requireTinyfolkOnlyRouteMetadata = true,
		tinyfolkOnlyRouteAttribute = "TinyfolkOnlyRoute",
		routeEnabledAttribute = "RouteEnabled",
	}
	local validMetadata = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	}, {
		{
			name = "EscapeRoute_A",
			position = { x = 0, y = 1, z = 170 },
			attributes = { TinyfolkOnlyRoute = true, RouteEnabled = true },
		},
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	})
	local r9 = RealmRouteGraphValidator.ValidateRouteGraph(validMetadata, metadataConfig)
	assertEqual(r9.passed, true, "block9 overall pass")
	assertCheckPassed(requireResult(r9.results, "route_graph_tinyfolk_only_metadata", "block9"), "block9 metadata")

	local fallbackConfig = {
		tinyfolkSpawnPrefix = "TinyfolkSpawn",
		requireTinyfolkOnlyRouteMetadata = true,
		tinyfolkOnlyRouteAttribute = "",
		routeEnabledAttribute = "",
	}
	local fallbackConfigResult = RealmRouteGraphValidator.ValidateRouteGraph(validMetadata, fallbackConfig)
	assertEqual(fallbackConfigResult.passed, true, "block9 malformed attribute config falls back to canonical names")

	local topLevelMetadata = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	}, {
		{
			name = "EscapeRoute_A",
			position = { x = 0, y = 1, z = 170 },
			TinyfolkOnlyRoute = true,
			attributes = {},
		},
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	})
	local topLevelMetadataResult = RealmRouteGraphValidator.ValidateRouteGraph(topLevelMetadata, metadataConfig)
	assertEqual(
		topLevelMetadataResult.passed,
		true,
		"block9 top-level route metadata accepted when attributes omit field"
	)

	-- ============================================================
	-- BLOCK 10: Missing/disabled/duplicate Tinyfolk-only metadata fails.
	-- ============================================================
	local invalidMetadata = makeDescriptor({
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	}, {
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
		{
			name = "EscapeRoute_A",
			position = { x = 1, y = 1, z = 170 },
			attributes = { TinyfolkOnlyRoute = true, RouteEnabled = false },
		},
		{ name = "", position = { x = 2, y = 1, z = 170 }, attributes = { TinyfolkOnlyRoute = true } },
	}, {
		{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 }, nodeType = "spawn" },
		{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 }, nodeType = "escape" },
	})
	local r10 = RealmRouteGraphValidator.ValidateRouteGraph(invalidMetadata, metadataConfig)
	assertEqual(r10.passed, false, "block10 overall fail")
	local block10 = requireResult(r10.results, "route_graph_tinyfolk_only_metadata", "block10")
	assertCheckFailed(block10, "block10 metadata")
	assertEqual(
		string.find(block10.reason :: string, "missing TinyfolkOnlyRoute=true", 1, true) ~= nil,
		true,
		"block10 missing metadata reason"
	)
	assertEqual(
		string.find(block10.reason :: string, "duplicate route id", 1, true) ~= nil,
		true,
		"block10 duplicate reason"
	)
	assertEqual(string.find(block10.reason :: string, "is disabled", 1, true) ~= nil, true, "block10 disabled reason")
	assertEqual(
		string.find(block10.reason :: string, "route id missing", 1, true) ~= nil,
		true,
		"block10 malformed route id reason"
	)

	print("realm_route_graph: all checks passed")
end

run()
