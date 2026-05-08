--!strict
-- Slice 20: zone_class_specific_minimum_disjoint_paths
--
-- Focused coverage for class-specific disjoint path minimums:
-- - control-zone checks prefer minimumControlZoneDisjointPathCount
-- - capture-zone checks prefer minimumCaptureZoneDisjointPathCount
-- - both fall back to minimumDisjointPathCount when class-specific value is nil
-- - class-specific values win when both class-specific and shared values are present

local RealmChokepointValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmChokepointValidator")

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

-- Same 4-node diamond used in edge-crossing specs.
local NODES = {
	{ name = "S", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn" },
	{ name = "N", position = { x = 0, y = 0, z = 100 }, nodeType = "waypoint" },
	{ name = "K", position = { x = 50, y = 0, z = 100 }, nodeType = "waypoint" },
	{ name = "E", position = { x = 0, y = 0, z = 200 }, nodeType = "escape", tier = "primary" },
}

local EDGES = {
	{ from = "S", to = "N", distance = 100 },
	{ from = "N", to = "S", distance = 100 },
	{ from = "S", to = "K", distance = 111 },
	{ from = "K", to = "S", distance = 111 },
	{ from = "N", to = "E", distance = 100 },
	{ from = "E", to = "N", distance = 100 },
	{ from = "K", to = "E", distance = 111 },
	{ from = "E", to = "K", distance = 111 },
}

local function makeDescriptor(controlZones, captureZones)
	return {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = controlZones or {},
		captureZones = captureZones or {},
		props = {},
		routeGraph = { nodes = NODES, edges = EDGES },
	}
end

local function run()
	-- ============================================================
	-- BLOCK 1: control-zone check uses control-specific threshold
	-- Control zone edge-cross blocks N->E, leaving 1 surviving path.
	-- Shared minimum=2 would fail, control-specific minimum=1 must pass.
	-- ============================================================
	local controlSpecificConfig = {
		zoneTagFilter = "GiantControl",
		minimumDisjointPathCount = 2,
		minimumControlZoneDisjointPathCount = 1,
		requireFallbackEscapeReachability = false,
		checkCaptureZoneEdgeBlocking = false,
	}
	local r1 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor({
			{ name = "ControlCross", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
		}, {}),
		controlSpecificConfig
	)
	assertCheckPassed(
		requireResult(r1.results, "choke_point_escape_reachability", "block1"),
		"block1 control-specific min=1 overrides shared min=2"
	)

	-- ============================================================
	-- BLOCK 2: capture-zone check uses capture-specific threshold
	-- Capture zone edge-cross blocks N->E, leaving 1 surviving path.
	-- Shared minimum=2 would fail, capture-specific minimum=1 must pass.
	-- ============================================================
	local captureSpecificConfig = {
		zoneTagFilter = "GiantControl",
		minimumDisjointPathCount = 2,
		minimumCaptureZoneDisjointPathCount = 1,
		requireFallbackEscapeReachability = false,
		checkCaptureZoneEdgeBlocking = true,
	}
	local r2 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor({}, {
			{ name = "CaptureCross", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantCapture" },
		}),
		captureSpecificConfig
	)
	assertCheckPassed(
		requireResult(r2.results, "capture_zone_route_edge_blocking", "block2"),
		"block2 capture-specific min=1 overrides shared min=2"
	)

	-- ============================================================
	-- BLOCK 3: fallback to shared minimum still works
	-- No class-specific values provided; shared minimum=2 applies.
	-- One surviving path after control-zone edge-cross => fail.
	-- ============================================================
	local sharedOnlyConfig = {
		zoneTagFilter = "GiantControl",
		minimumDisjointPathCount = 2,
		requireFallbackEscapeReachability = false,
		checkCaptureZoneEdgeBlocking = false,
	}
	local r3 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor({
			{ name = "ControlCross", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
		}, {}),
		sharedOnlyConfig
	)
	assertCheckFailed(
		requireResult(r3.results, "choke_point_escape_reachability", "block3"),
		"block3 shared minimum applies when control-specific minimum is nil"
	)

	-- ============================================================
	-- BLOCK 4: specific threshold wins when both specific and shared exist
	-- One-path case with shared=1 but control-specific=2 should fail.
	-- If shared had won this would pass; expected failure proves precedence.
	-- ============================================================
	local precedenceConfig = {
		zoneTagFilter = "GiantControl",
		minimumDisjointPathCount = 1,
		minimumControlZoneDisjointPathCount = 2,
		requireFallbackEscapeReachability = false,
		checkCaptureZoneEdgeBlocking = false,
	}
	local r4 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor({
			{ name = "ControlCross", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
		}, {}),
		precedenceConfig
	)
	assertCheckFailed(
		requireResult(r4.results, "choke_point_escape_reachability", "block4"),
		"block4 control-specific min=2 wins over shared min=1"
	)

	-- ============================================================
	-- BLOCK 5: deterministic behavior unchanged with class-specific minimums
	-- Same descriptor and config produce stable pass/fail and reason text.
	-- ============================================================
	local desc5 = makeDescriptor({}, {
		{ name = "CaptureCross", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantCapture" },
	})
	local cfg5 = {
		zoneTagFilter = "GiantControl",
		minimumDisjointPathCount = 2,
		minimumCaptureZoneDisjointPathCount = 1,
		requireFallbackEscapeReachability = false,
		checkCaptureZoneEdgeBlocking = true,
	}
	local r5a = RealmChokepointValidator.ValidateChokepoints(desc5, cfg5)
	local r5b = RealmChokepointValidator.ValidateChokepoints(desc5, cfg5)
	local c5a = requireResult(r5a.results, "capture_zone_route_edge_blocking", "block5a")
	local c5b = requireResult(r5b.results, "capture_zone_route_edge_blocking", "block5b")
	assertEqual(c5a.passed, c5b.passed, "block5 pass stability")
	assertEqual(c5a.reason, c5b.reason, "block5 reason stability")

	print("realm_choke_point_zone_class_thresholds: all checks passed")
end

run()
