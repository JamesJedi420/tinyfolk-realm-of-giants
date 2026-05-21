--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmRouteGraphValidator = {}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type NamedPart = RealmTopologyValidator.NamedPart
export type NamedNode = RealmTopologyValidator.NamedNode
export type RouteEdge = RealmTopologyValidator.RouteEdge

export type RealmRouteGraphConfig = {
	-- Prefix used to identify tinyfolk spawn parts in descriptor.spawns.
	tinyfolkSpawnPrefix: string,
	requireTinyfolkOnlyRouteMetadata: boolean?,
	tinyfolkOnlyRouteAttribute: string?,
	routeEnabledAttribute: string?,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type RouteGraphValidationResult = {
	passed: boolean,
	results: { CheckResult },
}

local function startsWith(value: string, prefix: string): boolean
	if #prefix == 0 then
		return true
	end
	return string.sub(value, 1, #prefix) == prefix
end

local function buildNameSetByNodeType(nodes: { NamedNode }, nodeType: "spawn" | "escape"): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, node in nodes do
		if node.nodeType == nodeType then
			result[node.name] = true
		end
	end
	return result
end

local function checkSpawnRegistration(descriptor: RealmDescriptor, config: RealmRouteGraphConfig): CheckResult
	local spawnNodeNames = buildNameSetByNodeType(descriptor.routeGraph.nodes, "spawn")

	local missing: { string } = {}
	for _, spawn in descriptor.spawns do
		if startsWith(spawn.name, config.tinyfolkSpawnPrefix) and not spawnNodeNames[spawn.name] then
			table.insert(missing, spawn.name)
		end
	end

	if #missing == 0 then
		return { id = "route_graph_spawn_registration", passed = true }
	end

	return {
		id = "route_graph_spawn_registration",
		passed = false,
		reason = string.format("missing spawn node registration(s) in route graph: %s", table.concat(missing, ", ")),
	}
end

local function checkEscapeRegistration(descriptor: RealmDescriptor): CheckResult
	local escapeNodeNames = buildNameSetByNodeType(descriptor.routeGraph.nodes, "escape")

	local missing: { string } = {}
	for _, escapeRoute in descriptor.escapeRoutes do
		if not escapeNodeNames[escapeRoute.name] then
			table.insert(missing, escapeRoute.name)
		end
	end

	if #missing == 0 then
		return { id = "route_graph_escape_registration", passed = true }
	end

	return {
		id = "route_graph_escape_registration",
		passed = false,
		reason = string.format("missing escape node registration(s) in route graph: %s", table.concat(missing, ", ")),
	}
end

local function sortedDanglingEndpointNames(nodeNameSet: { [string]: boolean }, edges: { RouteEdge }): { string }
	local missingSet: { [string]: boolean } = {}

	for _, edge in edges do
		if not nodeNameSet[edge.from] then
			missingSet[edge.from] = true
		end
		if not nodeNameSet[edge.to] then
			missingSet[edge.to] = true
		end
	end

	local missing: { string } = {}
	for name in pairs(missingSet) do
		table.insert(missing, name)
	end
	table.sort(missing)
	return missing
end

local function checkEdgeConsistency(descriptor: RealmDescriptor): CheckResult
	local edges = descriptor.routeGraph.edges

	-- Vacuous pass: no edges to validate.
	if #edges == 0 then
		return { id = "route_graph_edge_consistency", passed = true }
	end

	local nodeNameSet: { [string]: boolean } = {}
	for _, node in descriptor.routeGraph.nodes do
		nodeNameSet[node.name] = true
	end

	local missing = sortedDanglingEndpointNames(nodeNameSet, edges)
	if #missing == 0 then
		return { id = "route_graph_edge_consistency", passed = true }
	end

	return {
		id = "route_graph_edge_consistency",
		passed = false,
		reason = string.format("dangling route-graph edge endpoint(s): %s", table.concat(missing, ", ")),
	}
end

local function getRouteAttribute(route: any, attributeName: string): any
	local attributes = route.attributes
	if type(attributes) == "table" then
		local attributeValue = attributes[attributeName]
		if attributeValue ~= nil then
			return attributeValue
		end
	end
	return route[attributeName]
end

local function nonEmptyStringOrFallback(value: any, fallback: string): string
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function checkTinyfolkOnlyRouteMetadata(descriptor: RealmDescriptor, config: RealmRouteGraphConfig): CheckResult
	if config.requireTinyfolkOnlyRouteMetadata ~= true then
		return { id = "route_graph_tinyfolk_only_metadata", passed = true }
	end

	local tinyfolkOnlyAttribute = nonEmptyStringOrFallback(config.tinyfolkOnlyRouteAttribute, "TinyfolkOnlyRoute")
	local routeEnabledAttribute = nonEmptyStringOrFallback(config.routeEnabledAttribute, "RouteEnabled")
	local seenByName: { [string]: boolean } = {}
	local violations: { string } = {}

	for _, route in descriptor.escapeRoutes do
		local routeAny: any = route
		local routeName = routeAny.name
		if type(routeName) ~= "string" or routeName == "" then
			table.insert(violations, "route id missing")
			routeName = "<missing>"
		end

		if seenByName[routeName] == true then
			table.insert(violations, string.format("%s duplicate route id", routeName))
		end
		seenByName[routeName] = true

		if getRouteAttribute(routeAny, tinyfolkOnlyAttribute) ~= true then
			table.insert(violations, string.format("%s missing %s=true", routeName, tinyfolkOnlyAttribute))
		end
		if getRouteAttribute(routeAny, routeEnabledAttribute) == false then
			table.insert(violations, string.format("%s is disabled", routeName))
		end
	end

	if #violations == 0 then
		return { id = "route_graph_tinyfolk_only_metadata", passed = true }
	end

	return {
		id = "route_graph_tinyfolk_only_metadata",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

function RealmRouteGraphValidator.ValidateRouteGraph(
	descriptor: RealmDescriptor,
	config: RealmRouteGraphConfig
): RouteGraphValidationResult
	local results: { CheckResult } = {
		checkSpawnRegistration(descriptor, config),
		checkEscapeRegistration(descriptor),
		checkEdgeConsistency(descriptor),
		checkTinyfolkOnlyRouteMetadata(descriptor, config),
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

return RealmRouteGraphValidator
