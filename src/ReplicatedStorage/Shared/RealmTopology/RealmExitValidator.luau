--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmExitValidator = {}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type Vector3Data = RealmTopologyValidator.Vector3Data
export type NamedPart = RealmTopologyValidator.NamedPart

export type RealmExitConfig = {
	-- Minimum number of distinct escape routes for a viable realm.
	exitCountMinimum: number,
	-- Minimum distance (studs) between any escape route and any GiantSpawn.
	exitGiantSpawnMinSeparationStuds: number,
	-- Minimum distance (studs) between any two escape routes.
	exitClusteringMinSeparationStuds: number,
	-- Maximum distance (studs) from a TinyfolkReturnPoint to its nearest escape route.
	returnPointExitMaxStuds: number,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type ExitValidationResult = {
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

-- Check 1: At least exitCountMinimum escape routes are registered.
-- Addresses: "at least two viable endgame exits in normal realms."
local function checkExitCountMinimum(
	descriptor: RealmDescriptor,
	config: RealmExitConfig
): CheckResult
	local count = #descriptor.escapeRoutes
	if count >= config.exitCountMinimum then
		return { id = "exit_count_minimum", passed = true }
	end
	return {
		id = "exit_count_minimum",
		passed = false,
		reason = string.format(
			"only %d escape route(s) registered; minimum is %d",
			count,
			config.exitCountMinimum
		),
	}
end

-- Check 2: No escape route is within exitGiantSpawnMinSeparationStuds of any GiantSpawn.
-- Addresses: Giant at spawn must not be able to camp every exit without moving.
local function checkExitGiantSpawnSeparation(
	descriptor: RealmDescriptor,
	config: RealmExitConfig
): CheckResult
	local giantSpawns = getByPrefix(descriptor.spawns, "GiantSpawn")
	local minDist = config.exitGiantSpawnMinSeparationStuds
	local violations: { string } = {}

	for _, route in descriptor.escapeRoutes do
		for _, spawn in giantSpawns do
			local d = dist3(route.position, spawn.position)
			if d < minDist then
				table.insert(
					violations,
					string.format(
						"%s is %.1f studs from %s (min %.1f)",
						route.name,
						d,
						spawn.name,
						minDist
					)
				)
			end
		end
	end

	if #violations == 0 then
		return { id = "exit_giant_spawn_separation", passed = true }
	end
	return {
		id = "exit_giant_spawn_separation",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

-- Check 3: No two escape routes are within exitClusteringMinSeparationStuds of each other.
-- Addresses: exits must not share a single defended zone.
local function checkExitClustering(
	descriptor: RealmDescriptor,
	config: RealmExitConfig
): CheckResult
	local routes = descriptor.escapeRoutes
	local minDist = config.exitClusteringMinSeparationStuds
	local violations: { string } = {}

	for i = 1, #routes do
		for j = i + 1, #routes do
			local d = dist3(routes[i].position, routes[j].position)
			if d < minDist then
				table.insert(
					violations,
					string.format(
						"%s and %s are %.1f studs apart (min %.1f)",
						routes[i].name,
						routes[j].name,
						d,
						minDist
					)
				)
			end
		end
	end

	if #violations == 0 then
		return { id = "exit_clustering", passed = true }
	end
	return {
		id = "exit_clustering",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

-- Check 4: Every TinyfolkReturnPoint has at least one escape route within
-- returnPointExitMaxStuds. Ensures a viable escape → return path physically exists.
local function checkReturnPointExitProximity(
	descriptor: RealmDescriptor,
	config: RealmExitConfig
): CheckResult
	local maxDist = config.returnPointExitMaxStuds
	local isolated: { string } = {}

	for _, returnPoint in descriptor.returnPoints do
		local hasNearbyExit = false
		for _, route in descriptor.escapeRoutes do
			if dist3(returnPoint.position, route.position) <= maxDist then
				hasNearbyExit = true
				break
			end
		end
		if not hasNearbyExit then
			table.insert(
				isolated,
				string.format(
					"%s has no escape route within %.1f studs",
					returnPoint.name,
					maxDist
				)
			)
		end
	end

	if #isolated == 0 then
		return { id = "return_point_exit_proximity", passed = true }
	end
	return {
		id = "return_point_exit_proximity",
		passed = false,
		reason = table.concat(isolated, "; "),
	}
end

function RealmExitValidator.ValidateExits(
	descriptor: RealmDescriptor,
	config: RealmExitConfig
): ExitValidationResult
	local results: { CheckResult } = {
		checkExitCountMinimum(descriptor, config),
		checkExitGiantSpawnSeparation(descriptor, config),
		checkExitClustering(descriptor, config),
		checkReturnPointExitProximity(descriptor, config),
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

return RealmExitValidator
