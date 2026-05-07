local RealmStationAccessValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmStationAccessValidator")

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

-- Config mirroring prototype constants:
--   StationConfig.ActivationRangeStuds = 16 (runtime gate; 80 studs is the design-time bound)
--   All production stations and warehouse cluster near z=0 axis; max prototype distances ~64 studs
local STANDARD_CONFIG = {
	specialistStationPrefixes        = { "WorkStation_", "MiningStation_", "Shrine_" },
	productionStationPrefixes        = { "WorkStation_", "MiningStation_" },
	warehousePrefix                  = "Warehouse_",
	specialistStationMaxPathStuds    = 80,
	warehouseMaxPathStuds            = 100,
	haulMaxStuds                     = 80,
	constructionSiteMaxPathStuds     = 80,
}

-- Positions from Layout.model.json files:
--   TinyfolkSpawn:      (-12, 0.5,  0)
--   GiantSpawn:         ( 12, 0.5,  0)
--   WorkStation_A:      ( 20, 3,    0)   dist to TinyfolkSpawn ~32.1
--   MiningStation_A:    ( 36, 3,    0)   dist to TinyfolkSpawn ~48.1
--   Shrine_A:           (-20, 4,    0)   dist to TinyfolkSpawn ~8.7
--   Warehouse_A:        ( 52, 3.5,  0)   dist to TinyfolkSpawn ~64.1; dist to WorkStation ~32.0; to Mining ~16.0
--   Granary_A:          (  4, 3.5,  0)   not a specialist/production/warehouse station in config
--   ConstructionSite_A: ( 12, 0.5, 32)   dist to TinyfolkSpawn = 40.0

local PROTOTYPE_SPAWNS = {
	{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
	{ name = "GiantSpawn",    position = { x = 12,  y = 0.5, z = 0 } },
}
local PROTOTYPE_STATIONS = {
	{ name = "WorkStation_A",   position = { x = 20,  y = 3,   z = 0 } },
	{ name = "MiningStation_A", position = { x = 36,  y = 3,   z = 0 } },
	{ name = "Shrine_A",        position = { x = -20, y = 4,   z = 0 } },
	{ name = "Warehouse_A",     position = { x = 52,  y = 3.5, z = 0 } },
	{ name = "Granary_A",       position = { x = 4,   y = 3.5, z = 0 } },
}
local PROTOTYPE_SITES = {
	{ name = "ConstructionSite_A", position = { x = 12, y = 0.5, z = 32 } },
}
local EMPTY_ESCAPE_ROUTES = {}
local EMPTY_RETURN_POINTS = {}
local EMPTY_BOARDS = {}
local EMPTY_ZONES = {}
local EMPTY_ROUTE_GRAPH = { nodes = {}, edges = {} }

local PROTOTYPE_DESCRIPTOR = {
	spawns            = PROTOTYPE_SPAWNS,
	escapeRoutes      = EMPTY_ESCAPE_ROUTES,
	returnPoints      = EMPTY_RETURN_POINTS,
	stations          = PROTOTYPE_STATIONS,
	constructionSites = PROTOTYPE_SITES,
	upgradeBoards     = EMPTY_BOARDS,
	controlZones      = EMPTY_ZONES,
	captureZones      = {},
	props             = {},
	routeGraph        = EMPTY_ROUTE_GRAPH,
}

local function run()

	-- ============================================================
	-- BLOCK 1: Prototype map — all 4 checks pass
	-- WorkStation_A: ~32.1 studs from TinyfolkSpawn <= 80
	-- MiningStation_A: ~48.1 studs from TinyfolkSpawn <= 80
	-- Shrine_A: ~8.7 studs from TinyfolkSpawn <= 80
	-- Warehouse_A: ~64.1 studs from TinyfolkSpawn <= 100
	-- WorkStation_A -> Warehouse_A: ~32.0 studs <= 80 (haul)
	-- MiningStation_A -> Warehouse_A: ~16.0 studs <= 80 (haul)
	-- ConstructionSite_A: 40.0 studs from TinyfolkSpawn <= 80
	-- ============================================================
	local r1 = RealmStationAccessValidator.ValidateStationAccess(PROTOTYPE_DESCRIPTOR, STANDARD_CONFIG)
	assertEqual(r1.passed, true, "prototype overall pass")
	assertEqual(#r1.results, 4, "prototype result count")

	local expectedIds = {
		"specialist_station_tinyfolk_access",
		"warehouse_tinyfolk_access",
		"production_warehouse_haul_loop",
		"construction_site_tinyfolk_access",
	}
	for _, id in expectedIds do
		requireResult(r1.results, id, "prototype id presence")
	end
	for _, check in r1.results do
		assertCheckPassed(check, "prototype all pass")
	end

	-- ============================================================
	-- BLOCK 2: specialist_station_tinyfolk_access fails
	-- WorkStation_A at (300, 3, 0) — dist to TinyfolkSpawn ~312 >> 80
	-- ============================================================
	local distantWorkStation = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = {
			{ name = "WorkStation_A",   position = { x = 300, y = 3,   z = 0 } },
			{ name = "MiningStation_A", position = { x = 36,  y = 3,   z = 0 } },
			{ name = "Shrine_A",        position = { x = -20, y = 4,   z = 0 } },
			{ name = "Warehouse_A",     position = { x = 52,  y = 3.5, z = 0 } },
		},
		constructionSites = PROTOTYPE_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = EMPTY_ZONES,
		captureZones      = {},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r2 = RealmStationAccessValidator.ValidateStationAccess(distantWorkStation, STANDARD_CONFIG)
	assertEqual(r2.passed, false, "distant workstation overall fail")
	assertCheckFailed(
		requireResult(r2.results, "specialist_station_tinyfolk_access", "distant workstation"),
		"specialist_station_tinyfolk_access fails for distant WorkStation"
	)

	-- ============================================================
	-- BLOCK 3: warehouse_tinyfolk_access fails
	-- Warehouse_A at (300, 3, 0) — dist to TinyfolkSpawn ~312 >> 100
	-- ============================================================
	local distantWarehouse = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = {
			{ name = "WorkStation_A",   position = { x = 20,  y = 3,   z = 0 } },
			{ name = "MiningStation_A", position = { x = 36,  y = 3,   z = 0 } },
			{ name = "Shrine_A",        position = { x = -20, y = 4,   z = 0 } },
			{ name = "Warehouse_A",     position = { x = 300, y = 3,   z = 0 } },
		},
		constructionSites = PROTOTYPE_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = EMPTY_ZONES,
		captureZones      = {},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r3 = RealmStationAccessValidator.ValidateStationAccess(distantWarehouse, STANDARD_CONFIG)
	assertEqual(r3.passed, false, "distant warehouse overall fail")
	assertCheckFailed(
		requireResult(r3.results, "warehouse_tinyfolk_access", "distant warehouse"),
		"warehouse_tinyfolk_access fails for distant Warehouse"
	)

	-- ============================================================
	-- BLOCK 4: production_warehouse_haul_loop fails
	-- WorkStation at (0, 3, 0), only Warehouse at (0, 3, 300) — haul dist = 300 >> 80
	-- ============================================================
	local brokenHaulLoop = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = {
			{ name = "WorkStation_A",   position = { x = 0, y = 3,   z = 0   } },
			{ name = "MiningStation_A", position = { x = 36, y = 3,  z = 0   } },
			{ name = "Shrine_A",        position = { x = -20, y = 4, z = 0   } },
			{ name = "Warehouse_A",     position = { x = 0, y = 3,   z = 300 } },
		},
		constructionSites = PROTOTYPE_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = EMPTY_ZONES,
		captureZones      = {},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r4 = RealmStationAccessValidator.ValidateStationAccess(brokenHaulLoop, STANDARD_CONFIG)
	assertEqual(r4.passed, false, "broken haul loop overall fail")
	assertCheckFailed(
		requireResult(r4.results, "production_warehouse_haul_loop", "broken haul loop"),
		"production_warehouse_haul_loop fails when station far from warehouse"
	)

	-- ============================================================
	-- BLOCK 5: construction_site_tinyfolk_access fails
	-- ConstructionSite at (300, 0.5, 0) — dist to TinyfolkSpawn ~312 >> 80
	-- ============================================================
	local distantSite = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = PROTOTYPE_STATIONS,
		constructionSites = {
			{ name = "ConstructionSite_A", position = { x = 300, y = 0.5, z = 0 } },
		},
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = EMPTY_ZONES,
		captureZones      = {},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r5 = RealmStationAccessValidator.ValidateStationAccess(distantSite, STANDARD_CONFIG)
	assertEqual(r5.passed, false, "distant construction site overall fail")
	assertCheckFailed(
		requireResult(r5.results, "construction_site_tinyfolk_access", "distant site"),
		"construction_site_tinyfolk_access fails for distant site"
	)

	-- ============================================================
	-- BLOCK 6: Mixed — WorkStation_A close (pass), MiningStation_A far (fail)
	-- specialist_station_tinyfolk_access must still fail overall.
	-- MiningStation_A at (130, 3, 0):
	--   dist from TinyfolkSpawn (-12,0.5,0): ~142 studs >> 80 → access FAILS
	--   dist from Warehouse_A (52,3.5,0):    ~78 studs <= 80  → haul PASSES
	-- This isolates the specialist access failure without breaking the haul loop.
	-- ============================================================
	local mixedStations = {
		spawns            = PROTOTYPE_SPAWNS,
		escapeRoutes      = EMPTY_ESCAPE_ROUTES,
		returnPoints      = EMPTY_RETURN_POINTS,
		stations          = {
			{ name = "WorkStation_A",   position = { x = 20,  y = 3,   z = 0 } },  -- ~32.1 studs from spawn, passes
			{ name = "MiningStation_A", position = { x = 130, y = 3,   z = 0 } },  -- ~142 studs from spawn, fails; ~78 studs from warehouse, haul passes
			{ name = "Shrine_A",        position = { x = -20, y = 4,   z = 0 } },  -- ~8.7 studs from spawn, passes
			{ name = "Warehouse_A",     position = { x = 52,  y = 3.5, z = 0 } },  -- ~64.1 studs from spawn, passes
		},
		constructionSites = PROTOTYPE_SITES,
		upgradeBoards     = EMPTY_BOARDS,
		controlZones      = EMPTY_ZONES,
		captureZones      = {},
		props             = {},
		routeGraph        = EMPTY_ROUTE_GRAPH,
	}
	local r6 = RealmStationAccessValidator.ValidateStationAccess(mixedStations, STANDARD_CONFIG)
	assertEqual(r6.passed, false, "mixed stations overall fail")
	local mixedSpecialistCheck = requireResult(r6.results, "specialist_station_tinyfolk_access", "mixed stations")
	assertCheckFailed(mixedSpecialistCheck, "specialist_station_tinyfolk_access fails despite one passing station")
	-- Other three pass: warehouse close, WorkStation haul loop fine, site fine
	assertCheckPassed(
		requireResult(r6.results, "warehouse_tinyfolk_access", "mixed stations"),
		"warehouse_tinyfolk_access passes in mixed case"
	)
	assertCheckPassed(
		requireResult(r6.results, "production_warehouse_haul_loop", "mixed stations"),
		"production_warehouse_haul_loop passes in mixed case (WorkStation still close to Warehouse)"
	)
	assertCheckPassed(
		requireResult(r6.results, "construction_site_tinyfolk_access", "mixed stations"),
		"construction_site_tinyfolk_access passes in mixed case"
	)

	print("realm_station_access: all checks passed")
end

run()
