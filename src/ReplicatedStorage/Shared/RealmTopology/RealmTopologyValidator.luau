--!strict

local RealmTopologyValidator = {}

export type Vector3Data = {
	x: number,
	y: number,
	z: number,
}

export type NamedPart = {
	name: string,
	position: Vector3Data,
}

export type NamedZone = {
	name: string,
	position: Vector3Data,
	radius: number,
	tag: string,
}

export type NamedProp = {
	name: string,
	position: Vector3Data,
	propType: string,
}

export type NamedNode = {
	name: string,
	position: Vector3Data,
	nodeType: "spawn" | "waypoint" | "escape" | "station",
	tier: ("primary" | "fallback")?,
}

export type RouteEdge = {
	from: string,
	to: string,
	distance: number,
}

export type RealmDescriptor = {
	spawns: { NamedPart },
	escapeRoutes: { NamedPart },
	returnPoints: { NamedPart },
	stations: { NamedPart },
	constructionSites: { NamedPart },
	upgradeBoards: { NamedPart },
	controlZones: { NamedZone },
	captureZones: { NamedZone },
	props: { NamedProp },
	routeGraph: {
		nodes: { NamedNode },
		edges: { RouteEdge },
	},
}

export type RealmValidationConfig = {
	escapeTriggerRadiusStuds: number,
	boardInteractionRangeStuds: number,
	stationActivationRangeStuds: number,
	constructionInteractionRangeStuds: number,
	requiredSpecialistStationIds: { string },
	constructionSiteIds: { string },
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type ValidationResult = {
	passed: boolean,
	results: { CheckResult },
}

local function dist3(a: Vector3Data, b: Vector3Data): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function findByName(parts: { NamedPart }, name: string): NamedPart?
	for _, part in parts do
		if part.name == name then
			return part
		end
	end
	return nil
end

local function hasNamePrefix(parts: { NamedPart }, prefix: string): boolean
	for _, part in parts do
		if string.sub(part.name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
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

-- Check 1: At least one TinyfolkSpawn registered.
local function checkTinyfolkSpawnExists(descriptor: RealmDescriptor): CheckResult
	if hasNamePrefix(descriptor.spawns, "TinyfolkSpawn") then
		return { id = "spawn_tinyfolk_exists", passed = true }
	end
	return {
		id = "spawn_tinyfolk_exists",
		passed = false,
		reason = "no TinyfolkSpawn registered in spawns",
	}
end

-- Check 2: At least one GiantSpawn registered.
local function checkGiantSpawnExists(descriptor: RealmDescriptor): CheckResult
	if hasNamePrefix(descriptor.spawns, "GiantSpawn") then
		return { id = "spawn_giant_exists", passed = true }
	end
	return {
		id = "spawn_giant_exists",
		passed = false,
		reason = "no GiantSpawn registered in spawns",
	}
end

-- Check 3: At least one escape route registered.
local function checkEscapeRouteExists(descriptor: RealmDescriptor): CheckResult
	if #descriptor.escapeRoutes > 0 then
		return { id = "escape_route_exists", passed = true }
	end
	return {
		id = "escape_route_exists",
		passed = false,
		reason = "no escape routes registered",
	}
end

-- Check 4: At least one Tinyfolk return point registered.
local function checkReturnPointExists(descriptor: RealmDescriptor): CheckResult
	if #descriptor.returnPoints > 0 then
		return { id = "return_point_exists", passed = true }
	end
	return {
		id = "return_point_exists",
		passed = false,
		reason = "no Tinyfolk return points registered",
	}
end

-- Check 5: Every required specialist station ID has a registered part.
local function checkStationCoverage(descriptor: RealmDescriptor, config: RealmValidationConfig): CheckResult
	local missing: { string } = {}
	for _, stationId in config.requiredSpecialistStationIds do
		if not findByName(descriptor.stations, stationId) then
			table.insert(missing, stationId)
		end
	end
	if #missing == 0 then
		return { id = "station_coverage", passed = true }
	end
	return {
		id = "station_coverage",
		passed = false,
		reason = string.format("missing required specialist stations: %s", table.concat(missing, ", ")),
	}
end

-- Check 6: Every construction site ID in config has a registered part.
local function checkConstructionSiteCoverage(descriptor: RealmDescriptor, config: RealmValidationConfig): CheckResult
	local missing: { string } = {}
	for _, siteId in config.constructionSiteIds do
		if not findByName(descriptor.constructionSites, siteId) then
			table.insert(missing, siteId)
		end
	end
	if #missing == 0 then
		return { id = "construction_site_coverage", passed = true }
	end
	return {
		id = "construction_site_coverage",
		passed = false,
		reason = string.format("missing construction sites: %s", table.concat(missing, ", ")),
	}
end

-- Check 7: Every upgrade board center is within (boardInteractionRangeStuds * 2)
-- studs of at least one GiantSpawn. Uses 2x the interaction range as a loose
-- "player can walk to the board from spawn" bound.
local function checkUpgradeBoardReachability(descriptor: RealmDescriptor, config: RealmValidationConfig): CheckResult
	local giantSpawns = getByPrefix(descriptor.spawns, "GiantSpawn")
	local maxDist = config.boardInteractionRangeStuds * 2
	local tooFar: { string } = {}

	for _, board in descriptor.upgradeBoards do
		local reachable = false
		for _, spawn in giantSpawns do
			if dist3(board.position, spawn.position) <= maxDist then
				reachable = true
				break
			end
		end
		if not reachable then
			table.insert(tooFar, string.format("%s (no GiantSpawn within %.1f studs)", board.name, maxDist))
		end
	end

	if #tooFar == 0 then
		return { id = "upgrade_board_reachability", passed = true }
	end
	return {
		id = "upgrade_board_reachability",
		passed = false,
		reason = string.format("unreachable upgrade boards: %s", table.concat(tooFar, "; ")),
	}
end

-- Check 8: No escape route center is within (escapeTriggerRadiusStuds + 5) studs
-- of any spawn. Prevents an escape route from being triggerable from spawn.
local function checkEscapeRouteSpawnSeparation(descriptor: RealmDescriptor, config: RealmValidationConfig): CheckResult
	local minDist = config.escapeTriggerRadiusStuds + 5
	local violations: { string } = {}

	for _, route in descriptor.escapeRoutes do
		for _, spawn in descriptor.spawns do
			local d = dist3(route.position, spawn.position)
			if d < minDist then
				table.insert(
					violations,
					string.format("%s is %.1f studs from %s (min %.1f)", route.name, d, spawn.name, minDist)
				)
			end
		end
	end

	if #violations == 0 then
		return { id = "escape_route_spawn_separation", passed = true }
	end
	return {
		id = "escape_route_spawn_separation",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

function RealmTopologyValidator.ValidateRealm(
	descriptor: RealmDescriptor,
	config: RealmValidationConfig
): ValidationResult
	local results: { CheckResult } = {
		checkTinyfolkSpawnExists(descriptor),
		checkGiantSpawnExists(descriptor),
		checkEscapeRouteExists(descriptor),
		checkReturnPointExists(descriptor),
		checkStationCoverage(descriptor, config),
		checkConstructionSiteCoverage(descriptor, config),
		checkUpgradeBoardReachability(descriptor, config),
		checkEscapeRouteSpawnSeparation(descriptor, config),
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

return RealmTopologyValidator
