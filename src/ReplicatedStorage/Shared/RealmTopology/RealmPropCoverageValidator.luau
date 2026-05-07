--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmPropCoverageValidator = {}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type Vector3Data = RealmTopologyValidator.Vector3Data
export type NamedPart = RealmTopologyValidator.NamedPart
export type NamedProp = RealmTopologyValidator.NamedProp

export type RealmPropCoverageConfig = {
	coverPropType: string,
	tinyfolkSpawnPrefix: string,
	coverObjectiveMaxStuds: number,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type PropCoverageValidationResult = {
	passed: boolean,
	results: { CheckResult },
}

local function dist3(a: Vector3Data, b: Vector3Data): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getByPrefix(parts: { NamedPart }, prefix: string): { NamedPart }
	local result: { NamedPart } = {}
	for _, part in parts do
		if string.sub(part.name, 1, #prefix) == prefix then
			table.insert(result, part)
		end
	end
	return result
end

local function getPropsByType(props: { NamedProp }, propType: string): { NamedProp }
	local result: { NamedProp } = {}
	for _, prop in props do
		if prop.propType == propType then
			table.insert(result, prop)
		end
	end
	return result
end

local function nearestCoverDistance(position: Vector3Data, coverProps: { NamedProp }): number
	local best = math.huge
	for _, prop in coverProps do
		local d = dist3(position, prop.position)
		if d < best then
			best = d
		end
	end
	return best
end

local function sortStrings(values: { string })
	table.sort(values, function(a, b)
		return a < b
	end)
end

local function checkPropCoverObjectiveProximity(
	descriptor: RealmDescriptor,
	config: RealmPropCoverageConfig
): CheckResult
	local requiredObjectives: { NamedPart } = {}
	local tinyfolkSpawns = getByPrefix(descriptor.spawns, config.tinyfolkSpawnPrefix)
	for _, spawn in tinyfolkSpawns do
		table.insert(requiredObjectives, spawn)
	end
	for _, escapeRoute in descriptor.escapeRoutes do
		table.insert(requiredObjectives, escapeRoute)
	end

	if #requiredObjectives == 0 then
		return { id = "prop_cover_objective_proximity", passed = true }
	end

	local coverProps = getPropsByType(descriptor.props, config.coverPropType)
	local maxDist = config.coverObjectiveMaxStuds
	local uncoveredNames: { string } = {}

	for _, objective in requiredObjectives do
		local d = nearestCoverDistance(objective.position, coverProps)
		if d > maxDist then
			table.insert(uncoveredNames, objective.name)
		end
	end

	if #uncoveredNames == 0 then
		return { id = "prop_cover_objective_proximity", passed = true }
	end

	sortStrings(uncoveredNames)
	return {
		id = "prop_cover_objective_proximity",
		passed = false,
		reason = string.format(
			"objectives without nearby %s cover (max %.1f): %s",
			config.coverPropType,
			maxDist,
			table.concat(uncoveredNames, ", ")
		),
	}
end

function RealmPropCoverageValidator.ValidatePropCoverage(
	descriptor: RealmDescriptor,
	config: RealmPropCoverageConfig
): PropCoverageValidationResult
	local results: { CheckResult } = {
		checkPropCoverObjectiveProximity(descriptor, config),
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

return RealmPropCoverageValidator
