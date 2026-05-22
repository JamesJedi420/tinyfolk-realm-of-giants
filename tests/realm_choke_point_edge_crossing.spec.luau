--!strict
-- Slice 18: choke_point_edge_crossing
--
-- Tests that route edges are treated as blocked when the edge segment passes
-- through a zone sphere, even when both endpoint nodes lie outside the zone.
--
-- Geometric rule: segment-sphere intersection using closest-point-on-segment
-- distance. Tangent (closest distance == radius) counts as blocked, matching
-- the node-point convention (dist3 <= radius).

local RealmChokepointValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmChokepointValidator")

type RealmDescriptor = RealmChokepointValidator.RealmDescriptor
type NamedNode = RealmChokepointValidator.NamedNode
type RouteEdge = RealmChokepointValidator.RouteEdge
type NamedZone = RealmChokepointValidator.NamedZone
type RealmChokepointConfig = RealmChokepointValidator.RealmChokepointConfig

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
-- Simple 4-node diamond graph with two edge-disjoint paths from S to E:
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
-- Edge-crossing test zone at (0,0,150) radius=10:
--   N→E segment passes through (0,0,150); dist = 0 < 10 → BLOCKED
--   Neither N(0,0,100) nor E(0,0,200) is inside zone (dist=50 each) → endpoints outside
--   K→E from (50,0,100) to (0,0,200) closest to (0,0,150) ≈ 22.4 > 10 → NOT BLOCKED
--   → 1 path (via K) survives

local EDGE_CROSSING_NODES: { NamedNode } = {
	{ name = "S", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn" },
	{ name = "N", position = { x = 0, y = 0, z = 100 }, nodeType = "waypoint" },
	{ name = "K", position = { x = 50, y = 0, z = 100 }, nodeType = "waypoint" },
	{ name = "E", position = { x = 0, y = 0, z = 200 }, nodeType = "escape", tier = "primary" },
}

local EDGE_CROSSING_EDGES: { RouteEdge } = {
	{ from = "S", to = "N", distance = 100 },
	{ from = "N", to = "S", distance = 100 },
	{ from = "S", to = "K", distance = 111 },
	{ from = "K", to = "S", distance = 111 },
	{ from = "N", to = "E", distance = 100 },
	{ from = "E", to = "N", distance = 100 },
	{ from = "K", to = "E", distance = 111 },
	{ from = "E", to = "K", distance = 111 },
}

-- Standard config: 2 disjoint paths required, GiantControl tag.
local STANDARD_CONFIG: RealmChokepointConfig = {
	zoneTagFilter = "GiantControl",
	minimumDisjointPathCount = 2,
	requireFallbackEscapeReachability = false,
	checkCaptureZoneEdgeBlocking = false,
}

-- Relaxed config: only 1 path required.
local RELAXED_CONFIG: RealmChokepointConfig = {
	zoneTagFilter = "GiantControl",
	minimumDisjointPathCount = 1,
	requireFallbackEscapeReachability = false,
	checkCaptureZoneEdgeBlocking = false,
}

local function makeDescriptor(nodes: { NamedNode }, edges: { RouteEdge }, controlZones: { NamedZone }): RealmDescriptor
	return {
		spawns = {},
		escapeRoutes = {},
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = controlZones,
		captureZones = {},
		props = {},
		routeGraph = { nodes = nodes, edges = edges },
	}
end

local function run()
	-- ============================================================
	-- BLOCK 1: No zones — 2 paths (N and K) survive → PASS (min=2)
	-- Baseline regression confirming the diamond graph is correct.
	-- ============================================================
	local r1 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {}),
		STANDARD_CONFIG
	)
	assertEqual(r1.passed, true, "block1 overall")
	assertCheckPassed(
		requireResult(r1.results, "choke_point_escape_reachability", "block1"),
		"block1 no zones → 2 paths survive"
	)

	-- ============================================================
	-- BLOCK 2: Node-point blocked still fails (regression)
	-- Zone placed directly on waypoint N at (0,0,100), radius=5.
	-- N is blocked by the existing point-containment rule.
	-- All edges incident on N are removed; only K path survives.
	-- 1 path < min=2 → FAIL
	-- ============================================================
	local r2 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {
			{ name = "Zone_OnN", position = { x = 0, y = 0, z = 100 }, radius = 5, tag = "GiantControl" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r2.passed, false, "block2 overall")
	assertCheckFailed(
		requireResult(r2.results, "choke_point_escape_reachability", "block2"),
		"block2 zone on N → 1 path < min=2"
	)

	-- ============================================================
	-- BLOCK 3: Edge crosses zone — both endpoints outside (KEY NEW CASE)
	-- Zone at (0,0,150) radius=10.
	--   N(0,0,100) dist=50 > 10 → outside ✓
	--   E(0,0,200) dist=50 > 10 → outside ✓
	--   Segment N→E closest point at (0,0,150): dist=0 < 10 → BLOCKED
	-- K→E not blocked (closest≈22.4 > 10).
	-- 1 path (via K) survives → FAIL (min=2)
	-- ============================================================
	local r3 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {
			{ name = "Zone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r3.passed, false, "block3 overall")
	assertCheckFailed(
		requireResult(r3.results, "choke_point_escape_reachability", "block3"),
		"block3 edge N→E crosses zone (endpoints outside) → 1 path < min=2"
	)

	-- ============================================================
	-- BLOCK 4: Zone near but misses all edges → PASS (min=2)
	-- Zone at (100,0,50) radius=5.
	-- All segments have closest points ≥ 70 studs away → no edge crossed.
	-- 2 paths survive.
	-- ============================================================
	local r4 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {
			{ name = "Zone_Miss", position = { x = 100, y = 0, z = 50 }, radius = 5, tag = "GiantControl" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r4.passed, true, "block4 overall")
	assertCheckPassed(
		requireResult(r4.results, "choke_point_escape_reachability", "block4"),
		"block4 zone misses all edges → 2 paths survive"
	)

	-- ============================================================
	-- BLOCK 5: Edge tangent to zone → BLOCKED (documented convention)
	-- Zone at (0,10,150) radius=10.
	--   N→E segment closest to (0,10,150): closest=(0,0,150), dist=10 = radius.
	--   Convention: tangent counts as blocked (using <= matches node-point rule).
	-- N→E blocked; K→E unaffected.
	-- 1 path (via K) survives → FAIL (min=2)
	-- ============================================================
	local r5 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {
			{ name = "Zone_Tangent", position = { x = 0, y = 10, z = 150 }, radius = 10, tag = "GiantControl" },
		}),
		STANDARD_CONFIG
	)
	assertEqual(r5.passed, false, "block5 overall")
	assertCheckFailed(
		requireResult(r5.results, "choke_point_escape_reachability", "block5"),
		"block5 tangent contact counts as blocked → 1 path < min=2"
	)

	-- ============================================================
	-- BLOCK 6: One path edge-crossed, alternate survives → PASS (min=1)
	-- Same zone at (0,0,150) radius=10 as block3, but relaxed config (min=1).
	-- K path survives; 1 path >= min=1 → PASS
	-- ============================================================
	local r6 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {
			{ name = "Zone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r6.passed, true, "block6 overall")
	assertCheckPassed(
		requireResult(r6.results, "choke_point_escape_reachability", "block6"),
		"block6 one path edge-crossed, K path survives → 1 >= min=1"
	)

	-- ============================================================
	-- BLOCK 7: Both paths blocked by edge crossing → FAIL (min=1)
	-- Zone at (10,0,150) radius=20 crosses both N→E and K→E:
	--   N→E: closest=(0,0,150), dist to (10,0,150)=10 < 20 → BLOCKED
	--   K→E: closest≈(22,0,156), dist≈13.4 < 20 → BLOCKED
	-- Neither N, K, nor E are inside zone:
	--   N(0,0,100): dist≈51 > 20 ✓  K(50,0,100): dist≈64 > 20 ✓  E(0,0,200): dist≈51 > 20 ✓
	-- 0 paths → FAIL (min=1)
	-- ============================================================
	local r7 = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {
			{ name = "Zone_BothPaths", position = { x = 10, y = 0, z = 150 }, radius = 20, tag = "GiantControl" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r7.passed, false, "block7 overall")
	assertCheckFailed(
		requireResult(r7.results, "choke_point_escape_reachability", "block7"),
		"block7 both N→E and K→E blocked → 0 paths < min=1"
	)

	-- ============================================================
	-- BLOCK 8: 3D crossing case
	-- Graph: single path S(0,0,0) → E(100,100,100) [escape primary].
	-- Zone at (50,50,50) radius=10.
	--   S and E both outside zone (dist≈86.6 each, >> 10).
	--   Segment midpoint exactly (50,50,50): dist=0 < 10 → BLOCKED (3D).
	-- 0 paths → FAIL (min=1).
	-- Then verify that a laterally offset zone misses the same edge.
	-- Zone at (100,50,50) radius=10: closest≈(66.7,66.7,66.7), dist≈41 > 10 → PASS (min=1).
	-- ============================================================
	local nodes3D: { NamedNode } = {
		{ name = "S3D", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn" },
		{ name = "E3D", position = { x = 100, y = 100, z = 100 }, nodeType = "escape", tier = "primary" },
	}
	local edges3D: { RouteEdge } = {
		{ from = "S3D", to = "E3D", distance = 173 },
		{ from = "E3D", to = "S3D", distance = 173 },
	}

	local r8a = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(nodes3D, edges3D, {
			{ name = "Zone_3D", position = { x = 50, y = 50, z = 50 }, radius = 10, tag = "GiantControl" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r8a.passed, false, "block8a overall")
	assertCheckFailed(
		requireResult(r8a.results, "choke_point_escape_reachability", "block8a"),
		"block8a zone at 3D midpoint (50,50,50) r=10 blocks S→E"
	)

	local r8b = RealmChokepointValidator.ValidateChokepoints(
		makeDescriptor(nodes3D, edges3D, {
			{ name = "Zone_3D_Miss", position = { x = 100, y = 50, z = 50 }, radius = 10, tag = "GiantControl" },
		}),
		RELAXED_CONFIG
	)
	assertEqual(r8b.passed, true, "block8b overall")
	assertCheckPassed(
		requireResult(r8b.results, "choke_point_escape_reachability", "block8b"),
		"block8b offset zone (100,50,50) r=10 misses S→E in 3D → PASS"
	)

	-- ============================================================
	-- BLOCK 9: Deterministic result stability
	-- Run same descriptor twice; both results must agree.
	-- ============================================================
	local desc9 = makeDescriptor(EDGE_CROSSING_NODES, EDGE_CROSSING_EDGES, {
		{ name = "Zone_CrossNE", position = { x = 0, y = 0, z = 150 }, radius = 10, tag = "GiantControl" },
	})
	local r9a = RealmChokepointValidator.ValidateChokepoints(desc9, STANDARD_CONFIG)
	local r9b = RealmChokepointValidator.ValidateChokepoints(desc9, STANDARD_CONFIG)
	assertEqual(r9a.passed, r9b.passed, "block9 pass stability")
	local check9a = requireResult(r9a.results, "choke_point_escape_reachability", "block9a")
	local check9b = requireResult(r9b.results, "choke_point_escape_reachability", "block9b")
	assertEqual(check9a.passed, check9b.passed, "block9 check passed stability")
	assertEqual(check9a.reason, check9b.reason, "block9 reason stability")

	print("realm_choke_point_edge_crossing: all checks passed")
end

run()
