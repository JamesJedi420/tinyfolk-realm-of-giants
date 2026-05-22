local RealmExitValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmExitValidator")

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

-- Config values matching current prototype constants:
--   EscapeConfig.TriggerRadiusStuds = 10 → exitGiantSpawnMinSeparationStuds = 30
--   exitClusteringMinSeparationStuds = 40 (exits must not share one defended zone)
--   returnPointExitMaxStuds = 100 (EscapeRoute_A is ~50 studs from ReturnPoint)
local STANDARD_CONFIG = {
	exitCountMinimum = 2,
	exitGiantSpawnMinSeparationStuds = 30,
	exitClusteringMinSeparationStuds = 40,
	returnPointExitMaxStuds = 100,
}

-- Map positions from Layout.model.json:
--   TinyfolkSpawn:        (-12, 0.5,   0)
--   GiantSpawn:           ( 12, 0.5,   0)
--   EscapeRoute_A:        (  0, 1,   170)   -- ~170 studs from GiantSpawn
--   TinyfolkReturnPoint:  (  0, 1,   220)   -- ~50 studs from EscapeRoute_A
local PROTOTYPE_SPAWNS = {
	{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
}
local PROTOTYPE_ESCAPE_ROUTES = {
	{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
}
local PROTOTYPE_RETURN_POINTS = {
	{ name = "TinyfolkReturnPoint", position = { x = 0, y = 1, z = 220 } },
}
local EMPTY_STATIONS = {}
local EMPTY_SITES = {}
local EMPTY_BOARDS = {}
local EMPTY_ZONES = {}
local EMPTY_ROUTE_GRAPH = { nodes = {}, edges = {} }

-- Synthetic two-exit descriptor: exits well-separated, far from spawns, near return point.
--   EscapeRoute_B: (0, 1, 170) — same as prototype A, ~170 studs from GiantSpawn
--   EscapeRoute_C: (60, 1, 170) — 60 studs from B (>40), ~168 studs from GiantSpawn
--   Both exits are ~50–80 studs from TinyfolkReturnPoint (0,1,220) — within 100
local TWO_EXIT_DESCRIPTOR = {
	spawns = PROTOTYPE_SPAWNS,
	escapeRoutes = {
		{ name = "EscapeRoute_B", position = { x = 0, y = 1, z = 170 } },
		{ name = "EscapeRoute_C", position = { x = 60, y = 1, z = 170 } },
	},
	returnPoints = PROTOTYPE_RETURN_POINTS,
	stations = EMPTY_STATIONS,
	constructionSites = EMPTY_SITES,
	upgradeBoards = EMPTY_BOARDS,
	controlZones = EMPTY_ZONES,
	captureZones = {},
	props = {},
	routeGraph = EMPTY_ROUTE_GRAPH,
}

local PROTOTYPE_DESCRIPTOR = {
	spawns = PROTOTYPE_SPAWNS,
	escapeRoutes = PROTOTYPE_ESCAPE_ROUTES,
	returnPoints = PROTOTYPE_RETURN_POINTS,
	stations = EMPTY_STATIONS,
	constructionSites = EMPTY_SITES,
	upgradeBoards = EMPTY_BOARDS,
	controlZones = EMPTY_ZONES,
	captureZones = {},
	props = {},
	routeGraph = EMPTY_ROUTE_GRAPH,
}

local function run()
	-- ============================================================
	-- BLOCK 1: Synthetic two-exit descriptor — all 4 checks pass
	-- EscapeRoute_B (0,1,170) and EscapeRoute_C (60,1,170):
	--   exit_count_minimum:               2 >= 2 ✓
	--   exit_giant_spawn_separation:      B ~170 studs, C ~168 studs > 30 ✓
	--   exit_clustering:                  60 studs apart > 40 ✓
	--   return_point_exit_proximity:      B ~50 studs from ReturnPoint < 100 ✓
	-- ============================================================
	local r1 = RealmExitValidator.ValidateExits(TWO_EXIT_DESCRIPTOR, STANDARD_CONFIG)
	assertEqual(r1.passed, true, "two-exit descriptor overall pass")
	assertEqual(#r1.results, 4, "two-exit descriptor result count")

	local expectedIds = {
		"exit_count_minimum",
		"exit_giant_spawn_separation",
		"exit_clustering",
		"return_point_exit_proximity",
	}
	for _, id in expectedIds do
		requireResult(r1.results, id, "two-exit id presence")
	end
	for _, check in r1.results do
		assertCheckPassed(check, "two-exit all pass")
	end

	-- ============================================================
	-- BLOCK 2: Prototype map — exit_count_minimum fails (1 < 2),
	-- other three pass. Documents a known prototype map gap.
	-- ============================================================
	local r2 = RealmExitValidator.ValidateExits(PROTOTYPE_DESCRIPTOR, STANDARD_CONFIG)
	assertEqual(r2.passed, false, "prototype map overall fail (only 1 exit)")

	assertCheckFailed(
		requireResult(r2.results, "exit_count_minimum", "prototype"),
		"prototype exit_count_minimum fails"
	)
	assertCheckPassed(
		requireResult(r2.results, "exit_giant_spawn_separation", "prototype"),
		"prototype exit_giant_spawn_separation passes"
	)
	assertCheckPassed(
		requireResult(r2.results, "exit_clustering", "prototype"),
		"prototype exit_clustering passes (only one exit)"
	)
	assertCheckPassed(
		requireResult(r2.results, "return_point_exit_proximity", "prototype"),
		"prototype return_point_exit_proximity passes"
	)

	-- ============================================================
	-- BLOCK 3: Failure — only 1 exit, minimum 2
	-- ============================================================
	local oneExit = {
		spawns = PROTOTYPE_SPAWNS,
		escapeRoutes = { { name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } } },
		returnPoints = PROTOTYPE_RETURN_POINTS,
		stations = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards = EMPTY_BOARDS,
		controlZones = EMPTY_ZONES,
		captureZones = {},
		props = {},
		routeGraph = EMPTY_ROUTE_GRAPH,
	}
	local r3 = RealmExitValidator.ValidateExits(oneExit, STANDARD_CONFIG)
	assertEqual(r3.passed, false, "one exit overall fail")
	assertCheckFailed(
		requireResult(r3.results, "exit_count_minimum", "one exit"),
		"exit_count_minimum fails with 1 exit"
	)

	-- ============================================================
	-- BLOCK 4: Failure — two exits clustered within 40 studs
	-- EscapeRoute_D: (0,1,170), EscapeRoute_E: (20,1,170) — 20 studs apart < 40
	-- ============================================================
	local clusteredExits = {
		spawns = PROTOTYPE_SPAWNS,
		escapeRoutes = {
			{ name = "EscapeRoute_D", position = { x = 0, y = 1, z = 170 } },
			{ name = "EscapeRoute_E", position = { x = 20, y = 1, z = 170 } },
		},
		returnPoints = PROTOTYPE_RETURN_POINTS,
		stations = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards = EMPTY_BOARDS,
		controlZones = EMPTY_ZONES,
		captureZones = {},
		props = {},
		routeGraph = EMPTY_ROUTE_GRAPH,
	}
	local r4 = RealmExitValidator.ValidateExits(clusteredExits, STANDARD_CONFIG)
	assertEqual(r4.passed, false, "clustered exits overall fail")
	assertCheckFailed(
		requireResult(r4.results, "exit_clustering", "clustered exits"),
		"exit_clustering fails when exits too close"
	)

	-- ============================================================
	-- BLOCK 5: Failure — exit within 30 studs of a GiantSpawn
	-- EscapeRoute_F at (12,0.5,20) — ~20 studs from GiantSpawn(12,0.5,0) < 30
	-- Pair with a distant exit to pass exit_count_minimum.
	-- ============================================================
	local exitNearGiantSpawn = {
		spawns = PROTOTYPE_SPAWNS,
		escapeRoutes = {
			{ name = "EscapeRoute_F", position = { x = 12, y = 0.5, z = 20 } },
			{ name = "EscapeRoute_G", position = { x = -80, y = 1, z = 170 } },
		},
		returnPoints = PROTOTYPE_RETURN_POINTS,
		stations = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards = EMPTY_BOARDS,
		controlZones = EMPTY_ZONES,
		captureZones = {},
		props = {},
		routeGraph = EMPTY_ROUTE_GRAPH,
	}
	local r5 = RealmExitValidator.ValidateExits(exitNearGiantSpawn, STANDARD_CONFIG)
	assertEqual(r5.passed, false, "exit near Giant spawn overall fail")
	assertCheckFailed(
		requireResult(r5.results, "exit_giant_spawn_separation", "exit near Giant spawn"),
		"exit_giant_spawn_separation fails when exit too close to GiantSpawn"
	)

	-- ============================================================
	-- BLOCK 6: Failure — return point more than 100 studs from all exits
	-- ReturnPoint at (0,1,220); exits at (200,1,0) and (240,1,0) — both >200 studs away
	-- ============================================================
	local isolatedReturnPoint = {
		spawns = PROTOTYPE_SPAWNS,
		escapeRoutes = {
			{ name = "EscapeRoute_H", position = { x = 200, y = 1, z = 0 } },
			{ name = "EscapeRoute_I", position = { x = 240, y = 1, z = 0 } },
		},
		returnPoints = {
			{ name = "TinyfolkReturnPoint", position = { x = 0, y = 1, z = 220 } },
		},
		stations = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards = EMPTY_BOARDS,
		controlZones = EMPTY_ZONES,
		captureZones = {},
		props = {},
		routeGraph = EMPTY_ROUTE_GRAPH,
	}
	local r6 = RealmExitValidator.ValidateExits(isolatedReturnPoint, STANDARD_CONFIG)
	assertEqual(r6.passed, false, "isolated return point overall fail")
	assertCheckFailed(
		requireResult(r6.results, "return_point_exit_proximity", "isolated return point"),
		"return_point_exit_proximity fails when return point isolated from exits"
	)

	print("realm_exit: all checks passed")
end

run()
