local RealmPropCoverageValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmPropCoverageValidator")

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

local STANDARD_CONFIG = {
	coverPropType = "cover",
	tinyfolkSpawnPrefix = "TinyfolkSpawn",
	coverObjectiveMaxStuds = 20,
}

local EMPTY_RETURN_POINTS = {}
local EMPTY_STATIONS = {}
local EMPTY_SITES = {}
local EMPTY_BOARDS = {}
local EMPTY_ZONES = {}
local EMPTY_ROUTE_GRAPH = { nodes = {}, edges = {} }

local function makeDescriptor(spawns, escapeRoutes, props)
	return {
		spawns = spawns,
		escapeRoutes = escapeRoutes,
		returnPoints = EMPTY_RETURN_POINTS,
		stations = EMPTY_STATIONS,
		constructionSites = EMPTY_SITES,
		upgradeBoards = EMPTY_BOARDS,
		controlZones = EMPTY_ZONES,
		props = props,
		routeGraph = EMPTY_ROUTE_GRAPH,
	}
end

local function run()
	-- BLOCK 1: Baseline pass (both objectives covered)
	local baseline = makeDescriptor(
		{
			{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
			{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
		},
		{
			{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
		},
		{
			{ name = "Cover_A", position = { x = -8, y = 0.5, z = 0 }, propType = "cover" },
			{ name = "Cover_B", position = { x = 0, y = 0.5, z = 165 }, propType = "cover" },
		}
	)
	local r1 = RealmPropCoverageValidator.ValidatePropCoverage(baseline, STANDARD_CONFIG)
	assertEqual(r1.passed, true, "block1 overall pass")
	assertEqual(#r1.results, 1, "block1 result count")
	assertCheckPassed(requireResult(r1.results, "prop_cover_objective_proximity", "block1"), "block1 proximity pass")

	-- BLOCK 2: Tinyfolk spawn uncovered -> fail
	local spawnUncovered = makeDescriptor(
		{
			{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		},
		{
			{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
		},
		{
			{ name = "Cover_B", position = { x = 0, y = 0.5, z = 165 }, propType = "cover" },
		}
	)
	local r2 = RealmPropCoverageValidator.ValidatePropCoverage(spawnUncovered, STANDARD_CONFIG)
	assertEqual(r2.passed, false, "block2 overall fail")
	assertCheckFailed(requireResult(r2.results, "prop_cover_objective_proximity", "block2"), "block2 spawn uncovered")

	-- BLOCK 3: Escape route uncovered -> fail
	local escapeUncovered = makeDescriptor(
		{
			{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		},
		{
			{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
		},
		{
			{ name = "Cover_A", position = { x = -8, y = 0.5, z = 0 }, propType = "cover" },
		}
	)
	local r3 = RealmPropCoverageValidator.ValidatePropCoverage(escapeUncovered, STANDARD_CONFIG)
	assertEqual(r3.passed, false, "block3 overall fail")
	assertCheckFailed(requireResult(r3.results, "prop_cover_objective_proximity", "block3"), "block3 escape uncovered")

	-- BLOCK 4: Non-cover props are ignored -> fail
	local wrongTypeProps = makeDescriptor(
		{
			{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
		},
		{
			{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
		},
		{
			{ name = "Crate_A", position = { x = -8, y = 0.5, z = 0 }, propType = "decor" },
			{ name = "Crate_B", position = { x = 0, y = 0.5, z = 165 }, propType = "decor" },
		}
	)
	local r4 = RealmPropCoverageValidator.ValidatePropCoverage(wrongTypeProps, STANDARD_CONFIG)
	assertEqual(r4.passed, false, "block4 overall fail")
	assertCheckFailed(requireResult(r4.results, "prop_cover_objective_proximity", "block4"), "block4 wrong prop type")

	-- BLOCK 5: Distance exactly at threshold (20) passes
	local thresholdBoundary = makeDescriptor(
		{
			{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
		},
		{},
		{
			{ name = "Cover_Exact", position = { x = 20, y = 0, z = 0 }, propType = "cover" },
		}
	)
	local r5 = RealmPropCoverageValidator.ValidatePropCoverage(thresholdBoundary, STANDARD_CONFIG)
	assertEqual(r5.passed, true, "block5 overall pass")
	assertCheckPassed(requireResult(r5.results, "prop_cover_objective_proximity", "block5"), "block5 boundary pass")

	-- BLOCK 6: No required objectives (no Tinyfolk spawns, no escape routes) -> vacuous pass
	local noObjectives = makeDescriptor(
		{
			{ name = "GiantSpawn", position = { x = 12, y = 0.5, z = 0 } },
		},
		{},
		{}
	)
	local r6 = RealmPropCoverageValidator.ValidatePropCoverage(noObjectives, STANDARD_CONFIG)
	assertEqual(r6.passed, true, "block6 overall pass")
	assertCheckPassed(requireResult(r6.results, "prop_cover_objective_proximity", "block6"), "block6 vacuous pass")

	-- BLOCK 7: Deterministic sorted missing objective names in failure reason
	local sortedReasonCase = makeDescriptor(
		{
			{ name = "TinyfolkSpawn_B", position = { x = 0, y = 0, z = 0 } },
			{ name = "TinyfolkSpawn_A", position = { x = 100, y = 0, z = 0 } },
		},
		{
			{ name = "EscapeRoute_C", position = { x = 200, y = 0, z = 0 } },
		},
		{}
	)
	local r7 = RealmPropCoverageValidator.ValidatePropCoverage(sortedReasonCase, STANDARD_CONFIG)
	local check7 = requireResult(r7.results, "prop_cover_objective_proximity", "block7")
	assertCheckFailed(check7, "block7 deterministic reason")
	assertEqual(
		check7.reason,
		"objectives without nearby cover cover (max 20.0): EscapeRoute_C, TinyfolkSpawn_A, TinyfolkSpawn_B",
		"block7 exact sorted reason"
	)

	-- BLOCK 8: Giant spawns are not required objectives
	local giantIgnored = makeDescriptor(
		{
			{ name = "TinyfolkSpawn", position = { x = -12, y = 0.5, z = 0 } },
			{ name = "GiantSpawn", position = { x = 400, y = 0.5, z = 0 } },
		},
		{
			{ name = "EscapeRoute_A", position = { x = 0, y = 1, z = 170 } },
		},
		{
			{ name = "Cover_A", position = { x = -8, y = 0.5, z = 0 }, propType = "cover" },
			{ name = "Cover_B", position = { x = 0, y = 0.5, z = 165 }, propType = "cover" },
		}
	)
	local r8 = RealmPropCoverageValidator.ValidatePropCoverage(giantIgnored, STANDARD_CONFIG)
	assertEqual(r8.passed, true, "block8 overall pass")
	assertCheckPassed(requireResult(r8.results, "prop_cover_objective_proximity", "block8"), "block8 giant ignored")

	print("realm_prop_coverage: all checks passed")
end

run()
