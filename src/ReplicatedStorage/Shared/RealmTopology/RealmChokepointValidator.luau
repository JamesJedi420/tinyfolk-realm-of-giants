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

-- Returns a set of node names whose positions fall within any matching zone's radius.
local function buildBlockedNodeSet(
	nodes: { NamedNode },
	zones: { NamedZone }
): { [string]: boolean }
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

	-- Keep only edges where both endpoints are unblocked.
	local unlockedEdges: { RouteEdge } = {}
	for _, edge in edges do
		if not blocked[edge.from] and not blocked[edge.to] then
			table.insert(unlockedEdges, edge)
		end
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

function RealmChokepointValidator.ValidateChokepoints(
	descriptor: RealmDescriptor,
	config: RealmChokepointConfig
): ChokepointValidationResult
	local results: { CheckResult } = {
		checkChokepointEscapeReachability(descriptor, config),
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
