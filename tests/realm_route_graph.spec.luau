--!strict

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

local function makeDescriptor(spawns, escapeRoutes, routeGraphNodes)
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
			edges = {},
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
	assertEqual(#r1.results, 2, "block1 result count")
	assertCheckPassed(requireResult(r1.results, "route_graph_spawn_registration", "block1"), "block1 spawn")
	assertCheckPassed(requireResult(r1.results, "route_graph_escape_registration", "block1"), "block1 escape")

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

	-- ============================================================
	-- BLOCK 5: Empty spawn/escape lists -> vacuous pass independently.
	-- ============================================================
	local emptyLists = makeDescriptor({}, {}, {})
	local r5 = RealmRouteGraphValidator.ValidateRouteGraph(emptyLists, STANDARD_CONFIG)
	assertEqual(r5.passed, true, "block5 overall pass")
	assertCheckPassed(requireResult(r5.results, "route_graph_spawn_registration", "block5"), "block5 spawn vacuous")
	assertCheckPassed(requireResult(r5.results, "route_graph_escape_registration", "block5"), "block5 escape vacuous")

	print("realm_route_graph: all checks passed")
end

run()
