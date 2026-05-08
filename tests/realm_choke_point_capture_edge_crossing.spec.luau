--!strict
-- Slice 19: capture_zone_route_edge_blocking
--
-- Tests that route edges are treated as blocked when the edge segment passes
-- through a GiantCapture zone sphere, even when both endpoint nodes lie outside.
--
-- Geometric rule: same segment-sphere intersection as Slice 18.
--   Tangent (closest distance == radius) counts as blocked — consistent with
--   node-point convention (dist3 <= radius) and the control-zone edge rule.
--
-- The check is gated by config.checkCaptureZoneEdgeBlocking = true.
-- Zones are read from descriptor.captureZones (not controlZones).
-- Tag filter is always "GiantCapture".

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

-- ── Shared test geometry ─────────────────────────────────────────────────────
--
-- Same 4-node diamond graph used in realm_choke_point_edge_crossing.spec.luau.
--
--   S  = (0,0,0)    [spawn]
--   N  = (0,0,100)  [waypoint]   — "north" path
--   K  = (50,0,100) [waypoint]   — "south" detour path
--   E  = (0,0,200)  [escape, primary]
--
-- Paths:
--   Path-1: S → N → E
--   Path-2: S → K → E
--
-- Key edge-crossing zone at (0,0,150) radius=10:
--   N→E segment passes through (0,0,150); dist=0 < 10 → BLOCKED
--   N(0,0,100) dist=50 > 10 → outside zone  ✓
--   E(0,0,200) dist=50 > 10 → outside zone  ✓
--   K→E from (50,0,100): closest ≈ 22.4 > 10 → NOT BLOCKED
--   → 1 path (via K) survives after zone blocks N→E

local DIAMOND_NODES = {
	{ name = "S", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn" },
	{ name = "N", position = { x = 0, y = 0, z = 100 }, nodeType = "waypoint" },
	{ name = "K", position = { x = 50, y = 0, z = 100 }, nodeType = "waypoint" },
	{ name = "E", position = { x = 0, y = 0, z = 200 }, nodeType = "escape", tier = "primary" },
}

local DIAMOND_EDGES = {
	{ from = "S", to = "N", distance = 100 },
	{ from = "N", to = "S", distance = 100 },
	{ from = "S", to = "K", distance = 111 },
	{ from = "K", to = "S", distance = 111 },
	{ from = "N", to = "E", distance = 100 },
	{ from = "E", to = "N", distance = 100 },
	{ from = "K", to = "E", distance = 111 },
	{ from = "E", to = "K", distance = 111 },
}

-- Config requiring 2 paths, with capture-zone edge blocking enabled.
local STANDARD_CONFIG = {
	zoneTagFilter = "GiantControl",
	minimumDisjointPathCount = 2,
	requireFallbackEscapeReachability = false,
	checkCaptureZoneEdgeBlocking = true,
}

-- Relaxed config: only 1 path required.
local RELAXED_CONFIG = {
	zoneTagFilter = "GiantControl",
	minimumDisjointPathCount = 1,
	requireFallbackEscapeReachability = false,
	checkCaptureZoneEdgeBlocking = true,
}

-- Config with capture-zone edge blocking disabled.
local DISABLED_CONFIG = {
	zoneTagFilter = "GiantControl",
	minimumDisjointPathCount = 2,
	requireFallbackEscapeReachability = false,
	checkCaptureZoneEdgeBlocking = false,
}

local function makeDescriptor(nodes, edges, captureZones, controlZones)
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
		routeGraph = { nodes = nodes, edges = edges },
	}
end

local function run()
	-- ============================================================
	-- BLOCK 1: No capture zones, check enabled — 2 paths survive → PASS
	-- Baseline: vacuous pass when captureZones is empty.
	-- ============================================================
	local r1 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {}),
		STANDARD_CONFIG
	)
	assertEqual(r1.passed, true, "block1 overall")
	assertCheckPassed(
		requireResult(r1.results, "capture_zone_route_edge_blocking", "block1"),
		"block1 no capture zones → vacuous pass"
	)

	-- ============================================================
	-- BLOCK 2: Node-point blocked by capture zone (regression)
	-- Zone placed directly on waypoint N at (0,0,100), radius=5.
	-- N is inside zone (dist=0 <= 5) → blocked by point-containment rule.
	-- All edges incident on N removed; only K path survives.
	-- 1 path < min=2 → FAIL
	-- ============================================================
	local r2 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "CaptureZone_OnN", position = { x = 0, y = 0, z = 100 }, radius = 5, tag = "GiantCapture" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r2.passed, false, "block2 overall")
	assertCheckFailed(
		requireResult(r2.results, "capture_zone_route_edge_blocking", "block2"),
		"block2 capture zone on N → 1 path < min=2"
	)

	-- ============================================================
	-- BLOCK 3: Edge crosses capture zone — both endpoints outside (KEY NEW CASE)
	-- Zone at (0,0,150) radius=10.
	--   N(0,0,100): dist=50 > 10 → outside ✓
	--   E(0,0,200): dist=50 > 10 → outside ✓
	--   Segment N→E closest point at (0,0,150): dist=0 < 10 → BLOCKED
	-- K→E not blocked (closest≈22.4 > 10).
	-- 1 path survives → FAIL (min=2)
	-- ============================================================
	local r3 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "CaptureZone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantCapture" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r3.passed, false, "block3 overall")
	assertCheckFailed(
		requireResult(r3.results, "capture_zone_route_edge_blocking", "block3"),
		"block3 edge N→E crosses capture zone (endpoints outside) → 1 path < min=2"
	)

	-- ============================================================
	-- BLOCK 4: Capture zone near but misses all edges → PASS (min=2)
	-- Zone at (100,0,50) radius=5.
	-- All segments have closest points far from this center → no edge crossed.
	-- 2 paths survive.
	-- ============================================================
	local r4 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "CaptureZone_Miss", position = { x = 100, y = 0, z = 50 }, radius = 5, tag = "GiantCapture" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r4.passed, true, "block4 overall")
	assertCheckPassed(
		requireResult(r4.results, "capture_zone_route_edge_blocking", "block4"),
		"block4 capture zone misses all edges → 2 paths survive"
	)

	-- ============================================================
	-- BLOCK 5: Tangent edge contact → BLOCKED (documented convention)
	-- Zone at (0,10,150) radius=10.
	--   N→E segment: closest to (0,10,150) is (0,0,150), dist=10 = radius.
	--   Convention: tangent counts as blocked (<=, matching node-point rule).
	-- N→E blocked; K→E unaffected.
	-- 1 path (via K) survives → FAIL (min=2)
	-- ============================================================
	local r5 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "CaptureZone_Tangent", position = { x = 0, y = 10, z = 150 }, radius = 10, tag = "GiantCapture" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r5.passed, false, "block5 overall")
	assertCheckFailed(
		requireResult(r5.results, "capture_zone_route_edge_blocking", "block5"),
		"block5 tangent contact counts as blocked → 1 path < min=2"
	)

	-- ============================================================
	-- BLOCK 6: One path blocked by capture edge-crossing, alternate survives
	-- Same zone at (0,0,150) radius=10 as block3, but relaxed config (min=1).
	-- K path survives; 1 path >= min=1 → PASS
	-- ============================================================
	local r6 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "CaptureZone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantCapture" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r6.passed, true, "block6 overall")
	assertCheckPassed(
		requireResult(r6.results, "capture_zone_route_edge_blocking", "block6"),
		"block6 N path edge-crossed, K path survives → 1 >= min=1"
	)

	-- ============================================================
	-- BLOCK 7: Both paths blocked by capture edge-crossing → FAIL (min=1)
	-- Zone at (10,0,150) radius=20 blocks both N→E and K→E:
	--   N→E: closest=(0,0,150), dist to (10,0,150)=10 < 20 → BLOCKED
	--   K→E: closest≈(22,0,156), dist≈13.4 < 20 → BLOCKED
	--   Nodes N, K, E all outside zone.
	-- 0 paths → FAIL (min=1)
	-- ============================================================
	local r7 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "CaptureZone_BothPaths", position = { x = 10, y = 0, z = 150 }, radius = 20, tag = "GiantCapture" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r7.passed, false, "block7 overall")
	assertCheckFailed(
		requireResult(r7.results, "capture_zone_route_edge_blocking", "block7"),
		"block7 both N→E and K→E blocked by capture zone → 0 paths < min=1"
	)

	-- ============================================================
	-- BLOCK 8: 3D crossing case
	-- Single edge S3D→E3D on 3D diagonal.
	-- Zone at midpoint (50,50,50) radius=10 blocks the edge.
	-- Then verify a laterally offset zone misses.
	-- ============================================================
	local nodes3D = {
		{ name = "S3D", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn" },
		{ name = "E3D", position = { x = 100, y = 100, z = 100 }, nodeType = "escape", tier = "primary" },
	}
	local edges3D = {
		{ from = "S3D", to = "E3D", distance = 173 },
		{ from = "E3D", to = "S3D", distance = 173 },
	}

	-- Zone at 3D midpoint → BLOCKED → 0 paths → FAIL
	local r8a = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(nodes3D, edges3D, {
			{ name = "CaptureZone_3D", position = { x = 50, y = 50, z = 50 }, radius = 10, tag = "GiantCapture" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r8a.passed, false, "block8a overall")
	assertCheckFailed(
		requireResult(r8a.results, "capture_zone_route_edge_blocking", "block8a"),
		"block8a capture zone at 3D midpoint blocks S3D→E3D"
	)

	-- Offset zone misses → 1 path survives → PASS
	local r8b = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(nodes3D, edges3D, {
			{ name = "CaptureZone_3D_Miss", position = { x = 100, y = 50, z = 50 }, radius = 10, tag = "GiantCapture" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r8b.passed, true, "block8b overall")
	assertCheckPassed(
		requireResult(r8b.results, "capture_zone_route_edge_blocking", "block8b"),
		"block8b offset capture zone misses S3D→E3D in 3D → PASS"
	)

	-- ============================================================
	-- BLOCK 9: Deterministic result stability
	-- Run same descriptor twice; both results must agree.
	-- ============================================================
	local desc9 = makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
		{ name = "CaptureZone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantCapture" },
	})
	local r9a = RealmChokepointValidator.ValidateChokepoints(desc9, STANDARD_CONFIG)
	local r9b = RealmChokepointValidator.ValidateChokepoints(desc9, STANDARD_CONFIG)
	local c9a = requireResult(r9a.results, "capture_zone_route_edge_blocking", "block9a")
	local c9b = requireResult(r9b.results, "capture_zone_route_edge_blocking", "block9b")
	assertEqual(c9a.passed, c9b.passed, "block9 passed stability")
	assertEqual(c9a.reason, c9b.reason, "block9 reason stability")

	-- ============================================================
	-- BLOCK 10: check disabled — capture zone would block, but check is off
	-- Same zone at (0,0,150) r=10 as block3, but checkCaptureZoneEdgeBlocking=false.
	-- The capture_zone_route_edge_blocking check must report passed=true (skipped).
	-- ============================================================
	local r10 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "CaptureZone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantCapture" },
		}),
		DISABLED_CONFIG
	)
	assertCheckPassed(
		requireResult(r10.results, "capture_zone_route_edge_blocking", "block10"),
		"block10 check disabled → capture_zone_route_edge_blocking always passes"
	)

	-- ============================================================
	-- BLOCK 11: GiantControl zone does not trigger this check
	-- Same geometry as block3, but zone is in controlZones with GiantControl tag.
	-- capture_zone_route_edge_blocking reads captureZones only → vacuous pass.
	-- (choke_point_escape_reachability would catch it via controlZones.)
	-- ============================================================
	local r11 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {}, {
			{ name = "ControlZone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
		}),
		STANDARD_CONFIG
	)
	assertCheckPassed(
		requireResult(r11.results, "capture_zone_route_edge_blocking", "block11"),
		"block11 control zone in controlZones does not trigger capture check"
	)

	-- ============================================================
	-- BLOCK 12: Non-GiantCapture tag in captureZones is ignored
	-- Zone with tag "GiantControl" placed in captureZones (wrong field for tag).
	-- getZonesByTag filters to "GiantCapture" only → no blocking zones → vacuous pass.
	-- ============================================================
	local r12 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(DIAMOND_NODES, DIAMOND_EDGES, {
			{ name = "WrongTag", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
		}),
		STANDARD_CONFIG
	)
	assertCheckPassed(
		requireResult(r12.results, "capture_zone_route_edge_blocking", "block12"),
		"block12 non-GiantCapture tag in captureZones → filtered out → vacuous pass"
	)

	print("realm_choke_point_capture_edge_crossing: all checks passed")
end

run()
