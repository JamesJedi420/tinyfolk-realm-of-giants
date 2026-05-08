--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmChokepointValidator = {}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type Vector3Data = RealmTopologyValidator.Vector3Data
export type NamedZone = RealmTopologyValidator.NamedZone
export type NamedNode = RealmTopologyValidator.NamedNode
export type RouteEdge = RealmTopologyValidator.RouteEdge

export type RealmChokepointConfig = {
	-- Zone tag to filter (e.g. "GiantControl")
	zoneTagFilter: string,
	-- Minimum number of edge-disjoint spawn-to-escape paths that must survive zone blocking
	minimumDisjointPathCount: number,
	-- When true, asserts at least one tier=fallback escape node is reachable after zone blocking
	requireFallbackEscapeReachability: boolean,
	-- When true, also blocks route nodes and edges that intersect GiantCapture zones
	-- (reads from descriptor.captureZones). Uses the same minimumDisjointPathCount threshold.
	checkCaptureZoneEdgeBlocking: boolean,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type ChokepointValidationResult = {
	passed: boolean,
	results: { CheckResult },
}

local function dist3(a: Vector3Data, b: Vector3Data): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getZonesByTag(zones: { NamedZone }, tag: string): { NamedZone }
	local result: { NamedZone } = {}
	for _, zone in zones do
		if zone.tag == tag then
			table.insert(result, zone)
		end
	end
	return result
end

-- Returns true when the line segment from p to q intersects or is tangent to the
-- sphere at `center` with the given `radius`.
-- Convention: tangent (closest-point distance == radius) counts as blocked,
-- matching the node-point rule which uses dist3 <= radius.
local function segmentIntersectsSphere(p: Vector3Data, q: Vector3Data, center: Vector3Data, radius: number): boolean
	local dx = q.x - p.x
	local dy = q.y - p.y
	local dz = q.z - p.z
	local len2 = dx * dx + dy * dy + dz * dz
	local t: number
	if len2 == 0 then
		-- Degenerate segment (zero-length): treat as a point.
		t = 0
	else
		local cx = center.x - p.x
		local cy = center.y - p.y
		local cz = center.z - p.z
		t = (cx * dx + cy * dy + cz * dz) / len2
		if t < 0 then
			t = 0
		end
		if t > 1 then
			t = 1
		end
	end
	-- Closest point on segment to sphere center.
	local ex = (p.x + t * dx) - center.x
	local ey = (p.y + t * dy) - center.y
	local ez = (p.z + t * dz) - center.z
	-- Using <= so that tangent contact is blocked (matches node-point convention).
	return (ex * ex + ey * ey + ez * ez) <= radius * radius
end

-- Returns a set of node names whose positions fall within any matching zone's radius.
local function buildBlockedNodeSet(nodes: { NamedNode }, zones: { NamedZone }): { [string]: boolean }
	local blocked: { [string]: boolean } = {}
	for _, node in nodes do
		for _, zone in zones do
			if dist3(node.position, zone.position) <= zone.radius then
				blocked[node.name] = true
				break
			end
		end
	end
	return blocked
end

-- Flow edge entry for Edmonds-Karp implementation.
-- `rev` is the index of the paired reverse edge in the shared edge list.
type FlowEdge = { to: string, cap: number, rev: number }

-- Count edge-disjoint paths from the combined spawn-node set to the combined
-- escape-node set using Edmonds-Karp max-flow (BFS augmenting paths).
-- Returns -1 as a vacuous signal when no spawn or no escape nodes are present.
local function countDisjointPaths(
	nodes: { NamedNode },
	unlockedEdges: { RouteEdge },
	blocked: { [string]: boolean }
): number
	-- Collect unblocked spawn and escape nodes.
	local spawnSet: { [string]: boolean } = {}
	local escapeSet: { [string]: boolean } = {}
	for _, node in nodes do
		if not blocked[node.name] then
			if node.nodeType == "spawn" then
				spawnSet[node.name] = true
			elseif node.nodeType == "escape" then
				escapeSet[node.name] = true
			end
		end
	end

	local hasSpawn, hasEscape = false, false
	for _ in pairs(spawnSet) do
		hasSpawn = true
		break
	end
	for _ in pairs(escapeSet) do
		hasEscape = true
		break
	end
	if not hasSpawn or not hasEscape then
		return -1
	end

	-- Build residual flow network with a super-source S and super-sink T.
	local SOURCE = "__S__"
	local SINK = "__T__"
	local INF = 1000

	local edgeList: { FlowEdge } = {}
	local adj: { [string]: { number } } = {}

	local function ensureAdj(name: string)
		if not adj[name] then
			adj[name] = {}
		end
	end

	-- Adds a directed edge u→v (cap) and its residual reverse edge v→u (cap 0).
	local function addFlowEdge(u: string, v: string, cap: number)
		ensureAdj(u)
		ensureAdj(v)
		local fwdIdx = #edgeList + 1
		local revIdx = #edgeList + 2
		edgeList[fwdIdx] = { to = v, cap = cap, rev = revIdx }
		edgeList[revIdx] = { to = u, cap = 0, rev = fwdIdx }
		table.insert(adj[u], fwdIdx)
		table.insert(adj[v], revIdx)
	end

	-- Super-source connects to every spawn node.
	for name in pairs(spawnSet) do
		addFlowEdge(SOURCE, name, INF)
	end
	-- Every escape node connects to super-sink.
	for name in pairs(escapeSet) do
		addFlowEdge(name, SINK, INF)
	end
	-- Route edges (unblocked only), each with capacity 1.
	for _, edge in unlockedEdges do
		addFlowEdge(edge.from, edge.to, 1)
	end

	-- Edmonds-Karp: repeatedly find shortest augmenting path via BFS.
	local totalFlow = 0
	while true do
		-- BFS from SOURCE to SINK.
		local prev: { [string]: number } = {}
		local visited: { [string]: boolean } = { [SOURCE] = true }
		local queue: { string } = { SOURCE }
		local head = 1
		local found = false

		while head <= #queue do
			local u = queue[head]
			head += 1
			if u == SINK then
				found = true
				break
			end
			local neighbors = adj[u]
			if neighbors ~= nil then
				for _, eIdx in neighbors do
					local e = edgeList[eIdx]
					if not visited[e.to] and e.cap > 0 then
						visited[e.to] = true
						prev[e.to] = eIdx
						table.insert(queue, e.to)
					end
				end
			end
		end

		if not found then
			break
		end

		-- Augment by 1 along the path (all route edges have capacity 1).
		local cur = SINK
		while cur ~= SOURCE do
			local eIdx = prev[cur]
			if eIdx == nil then
				break
			end
			local fwdEdge = edgeList[eIdx]
			fwdEdge.cap -= 1
			local revEdge = edgeList[fwdEdge.rev]
			revEdge.cap += 1
			cur = revEdge.to
		end
		totalFlow += 1
	end

	return totalFlow
end

-- Check: after blocking edges whose endpoints lie inside any matching Giant
-- control zone, at least minimumDisjointPathCount independent paths must
-- remain from any spawn-typed node to any escape-typed node in the route graph.
local function checkChokepointEscapeReachability(
	descriptor: RealmDescriptor,
	config: RealmChokepointConfig
): CheckResult
	local zones = getZonesByTag(descriptor.controlZones, config.zoneTagFilter)
	local nodes = descriptor.routeGraph.nodes
	local edges = descriptor.routeGraph.edges

	local blocked = buildBlockedNodeSet(nodes, zones)

	-- Build a name→position lookup for the segment-sphere crossing check.
	local nodePositions: { [string]: Vector3Data } = {}
	for _, node in nodes do
		nodePositions[node.name] = node.position
	end

	-- Keep only edges where both endpoints are unblocked AND the edge segment
	-- does not cross through any zone sphere.
	local unlockedEdges: { RouteEdge } = {}
	for _, edge in edges do
		if blocked[edge.from] or blocked[edge.to] then
			continue
		end
		local fromPos = nodePositions[edge.from]
		local toPos = nodePositions[edge.to]
		if fromPos ~= nil and toPos ~= nil then
			local crosses = false
			for _, zone in zones do
				if segmentIntersectsSphere(fromPos, toPos, zone.position, zone.radius) then
					crosses = true
					break
				end
			end
			if crosses then
				continue
			end
		end
		table.insert(unlockedEdges, edge)
	end

	local pathCount = countDisjointPaths(nodes, unlockedEdges, blocked)

	-- Vacuous pass: no spawn or escape nodes registered in route graph.
	if pathCount == -1 then
		return { id = "choke_point_escape_reachability", passed = true }
	end

	if pathCount >= config.minimumDisjointPathCount then
		return { id = "choke_point_escape_reachability", passed = true }
	end

	return {
		id = "choke_point_escape_reachability",
		passed = false,
		reason = string.format(
			"only %d edge-disjoint spawn-to-escape path(s) survive zone blocking (minimum %d required)",
			pathCount,
			config.minimumDisjointPathCount
		),
	}
end

-- BFS reachability from a seed set through unblocked edges.
-- Returns the set of all node names reachable from any seed node.
local function bfsReachable(seedSet: { [string]: boolean }, unlockedEdges: { RouteEdge }): { [string]: boolean }
	-- Build adjacency list from unlocked edges.
	local adj: { [string]: { string } } = {}
	for _, edge in unlockedEdges do
		if not adj[edge.from] then
			adj[edge.from] = {}
		end
		table.insert(adj[edge.from], edge.to)
	end

	local visited: { [string]: boolean } = {}
	local queue: { string } = {}
	for name in pairs(seedSet) do
		visited[name] = true
		table.insert(queue, name)
	end

	local head = 1
	while head <= #queue do
		local u = queue[head]
		head += 1
		local neighbors = adj[u]
		if neighbors ~= nil then
			for _, v in neighbors do
				if not visited[v] then
					visited[v] = true
					table.insert(queue, v)
				end
			end
		end
	end

	return visited
end

-- Check: after blocking edges whose endpoints lie inside any matching Giant
-- control zone, at least one tier=fallback escape node must remain both
-- unblocked and reachable from any unblocked spawn node.
local function checkChokepointFallbackReachability(
	descriptor: RealmDescriptor,
	config: RealmChokepointConfig
): CheckResult
	if not config.requireFallbackEscapeReachability then
		return { id = "choke_point_fallback_reachability", passed = true }
	end

	local zones = getZonesByTag(descriptor.controlZones, config.zoneTagFilter)
	local nodes = descriptor.routeGraph.nodes
	local edges = descriptor.routeGraph.edges

	local blocked = buildBlockedNodeSet(nodes, zones)

	-- Build a name→position lookup for the segment-sphere crossing check.
	local nodePositions: { [string]: Vector3Data } = {}
	for _, node in nodes do
		nodePositions[node.name] = node.position
	end

	-- Keep only edges where both endpoints are unblocked AND the edge segment
	-- does not cross through any zone sphere.
	local unlockedEdges: { RouteEdge } = {}
	for _, edge in edges do
		if blocked[edge.from] or blocked[edge.to] then
			continue
		end
		local fromPos = nodePositions[edge.from]
		local toPos = nodePositions[edge.to]
		if fromPos ~= nil and toPos ~= nil then
			local crosses = false
			for _, zone in zones do
				if segmentIntersectsSphere(fromPos, toPos, zone.position, zone.radius) then
					crosses = true
					break
				end
			end
			if crosses then
				continue
			end
		end
		table.insert(unlockedEdges, edge)
	end

	-- Collect unblocked fallback escape nodes.
	local fallbackEscapes: { string } = {}
	for _, node in nodes do
		if node.nodeType == "escape" and node.tier == "fallback" and not blocked[node.name] then
			table.insert(fallbackEscapes, node.name)
		end
	end

	-- Vacuous pass: no fallback escape nodes registered or all blocked.
	if #fallbackEscapes == 0 then
		return { id = "choke_point_fallback_reachability", passed = true }
	end

	-- Seed BFS from all unblocked spawn nodes.
	local spawnSeed: { [string]: boolean } = {}
	for _, node in nodes do
		if node.nodeType == "spawn" and not blocked[node.name] then
			spawnSeed[node.name] = true
		end
	end

	local reachable = bfsReachable(spawnSeed, unlockedEdges)

	-- Pass if at least one fallback escape is reachable.
	for _, name in fallbackEscapes do
		if reachable[name] then
			return { id = "choke_point_fallback_reachability", passed = true }
		end
	end

	return {
		id = "choke_point_fallback_reachability",
		passed = false,
		reason = string.format(
			"no fallback escape node is reachable from any spawn after zone blocking (unreached: %s)",
			table.concat(fallbackEscapes, ", ")
		),
	}
end

-- Slice 19: capture_zone_route_edge_blocking
-- Check: after blocking route nodes and edges that intersect any GiantCapture zone
-- (point-containment AND segment-sphere), at least minimumDisjointPathCount independent
-- spawn-to-escape paths must survive.
-- Reads from descriptor.captureZones (not controlZones).
-- Tag is always "GiantCapture" — no tag-filter config needed here.
-- Vacuous pass when disabled, or when there are no GiantCapture zones,
-- or when the route graph has no spawn or escape nodes.
local function checkCaptureZoneRouteEdgeBlocking(
	descriptor: RealmDescriptor,
	config: RealmChokepointConfig
): CheckResult
	if not config.checkCaptureZoneEdgeBlocking then
		return { id = "capture_zone_route_edge_blocking", passed = true, reason = nil }
	end

	local zones = getZonesByTag(descriptor.captureZones, "GiantCapture")

	-- Vacuous pass: no GiantCapture zones present.
	if #zones == 0 then
		return { id = "capture_zone_route_edge_blocking", passed = true, reason = nil }
	end

	local nodes = descriptor.routeGraph.nodes
	local edges = descriptor.routeGraph.edges

	local blocked = buildBlockedNodeSet(nodes, zones)

	local nodePositions: { [string]: Vector3Data } = {}
	for _, node in nodes do
		nodePositions[node.name] = node.position
	end

	local unlockedEdges: { RouteEdge } = {}
	for _, edge in edges do
		if blocked[edge.from] or blocked[edge.to] then
			continue
		end
		local fromPos = nodePositions[edge.from]
		local toPos = nodePositions[edge.to]
		if fromPos ~= nil and toPos ~= nil then
			local crosses = false
			for _, zone in zones do
				if segmentIntersectsSphere(fromPos, toPos, zone.position, zone.radius) then
					crosses = true
					break
				end
			end
			if crosses then
				continue
			end
		end
		table.insert(unlockedEdges, edge)
	end

	local pathCount = countDisjointPaths(nodes, unlockedEdges, blocked)

	-- Vacuous pass: no spawn or escape nodes in route graph.
	if pathCount == -1 then
		return { id = "capture_zone_route_edge_blocking", passed = true, reason = nil }
	end

	if pathCount >= config.minimumDisjointPathCount then
		return { id = "capture_zone_route_edge_blocking", passed = true, reason = nil }
	end

	return {
		id = "capture_zone_route_edge_blocking",
		passed = false,
		reason = string.format(
			"only %d edge-disjoint spawn-to-escape path(s) survive GiantCapture zone blocking (minimum %d required)",
			pathCount,
			config.minimumDisjointPathCount
		),
	}
end

function RealmChokepointValidator.ValidateChokepoints(
	descriptor: RealmDescriptor,
	config: RealmChokepointConfig
): ChokepointValidationResult
	local results: { CheckResult } = {
		checkChokepointEscapeReachability(descriptor, config),
		checkChokepointFallbackReachability(descriptor, config),
		checkCaptureZoneRouteEdgeBlocking(descriptor, config),
	}

	local allPassed = true
	for _, result in results do
		if not result.passed then
			allPassed = false
			break
		end
	end

	return { passed = allPassed, results = results }
end

return RealmChokepointValidator
