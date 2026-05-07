--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmContainmentValidator = {}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type Vector3Data = RealmTopologyValidator.Vector3Data
export type NamedZone = RealmTopologyValidator.NamedZone
export type NamedNode = RealmTopologyValidator.NamedNode
export type RouteEdge = RealmTopologyValidator.RouteEdge

export type RealmContainmentConfig = {
	-- Zone tag used to identify capture zones (e.g. "GiantCapture")
	captureZoneTagFilter: string,
	-- Zone tag used to identify control zones that block route nodes (e.g. "GiantControl")
	controlZoneTagFilter: string,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type ContainmentValidationResult = {
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

-- BFS reachability from a single seed node through unblocked edges.
-- Returns the set of all node names reachable from the seed.
local function bfsReachable(seed: string, unlockedEdges: { RouteEdge }): { [string]: boolean }
	local adj: { [string]: { string } } = {}
	for _, edge in unlockedEdges do
		if not adj[edge.from] then
			adj[edge.from] = {}
		end
		table.insert(adj[edge.from], edge.to)
	end

	local visited: { [string]: boolean } = {}
	local queue: { string } = { seed }
	visited[seed] = true

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

-- Check: for each capture zone, after applying control-zone blocking to the
-- route graph, there must exist at least one path from that zone's nearest
-- unblocked route node to any escape-typed node.
--
-- Vacuous pass when no capture zones match the tag filter.
-- Per-zone fail when no unblocked route node exists, or no escape node is
-- reachable via BFS through the unblocked adjacency list.
--
-- Slice 8 simplifications:
--   captureZone.radius is stored but not used in routing.
--   No disjoint path count — reachability only.
--   No snap-radius threshold on nearest-node search.
local function checkCaptureEscapeReachability(descriptor: RealmDescriptor, config: RealmContainmentConfig): CheckResult
	local captureZones = getZonesByTag(descriptor.captureZones, config.captureZoneTagFilter)

	-- Vacuous pass: no capture zones of this type defined.
	if #captureZones == 0 then
		return { id = "containment_capture_escape_reachability", passed = true }
	end

	local controlZones = getZonesByTag(descriptor.controlZones, config.controlZoneTagFilter)
	local nodes = descriptor.routeGraph.nodes
	local edges = descriptor.routeGraph.edges

	local blocked = buildBlockedNodeSet(nodes, controlZones)

	-- Build unlocked edge list.
	local unlockedEdges: { RouteEdge } = {}
	for _, edge in edges do
		if not blocked[edge.from] and not blocked[edge.to] then
			table.insert(unlockedEdges, edge)
		end
	end

	-- Collect unblocked nodes for nearest-node lookup.
	local unblockedNodes: { NamedNode } = {}
	for _, node in nodes do
		if not blocked[node.name] then
			table.insert(unblockedNodes, node)
		end
	end

	-- Evaluate each capture zone independently.
	local failedZones: { string } = {}

	for _, zone in captureZones do
		-- Find the nearest unblocked route-graph node to this capture zone.
		local nearestName: string? = nil
		local nearestDist = math.huge
		for _, node in unblockedNodes do
			local d = dist3(node.position, zone.position)
			if d < nearestDist then
				nearestDist = d
				nearestName = node.name
			end
		end

		-- No unblocked nodes in the graph at all — zone fails.
		if nearestName == nil then
			table.insert(failedZones, zone.name)
			continue
		end

		-- BFS from nearest unblocked node and check for any escape-typed node.
		local reachable = bfsReachable(nearestName, unlockedEdges)

		local escapeReached = false
		for _, node in nodes do
			if node.nodeType == "escape" and reachable[node.name] then
				escapeReached = true
				break
			end
		end

		if not escapeReached then
			table.insert(failedZones, zone.name)
		end
	end

	if #failedZones == 0 then
		return { id = "containment_capture_escape_reachability", passed = true }
	end

	return {
		id = "containment_capture_escape_reachability",
		passed = false,
		reason = string.format("no escape route reachable from capture zone(s): %s", table.concat(failedZones, ", ")),
	}
end

function RealmContainmentValidator.ValidateContainment(
	descriptor: RealmDescriptor,
	config: RealmContainmentConfig
): ContainmentValidationResult
	local results: { CheckResult } = {
		checkCaptureEscapeReachability(descriptor, config),
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

return RealmContainmentValidator
