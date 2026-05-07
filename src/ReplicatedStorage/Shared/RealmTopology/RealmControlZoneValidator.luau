--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmControlZoneValidator = {}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type Vector3Data = RealmTopologyValidator.Vector3Data
export type NamedZone = RealmTopologyValidator.NamedZone

export type RealmControlZoneConfig = {
	-- Zone tag to filter and validate (e.g., "GiantControl")
	zoneTagFilter: string,
	-- Minimum distance (studs) from any TinyfolkSpawn to nearest zone center
	minimumSpawnZoneSeparationStuds: number,
	-- Minimum distance (studs) from station to zone perimeter
	-- Negative if inside; must be >= this threshold (e.g., 5 studs buffer)
	minimumStationZonePerimeterStuds: number,
	-- Minimum distance (studs) from escape route to zone perimeter
	minimumEscapeRouteZonePerimeterStuds: number,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type ControlZoneValidationResult = {
	passed: boolean,
	results: { CheckResult },
}

local function dist3(a: Vector3Data, b: Vector3Data): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getByPrefix(parts: { any }, prefix: string): { any }
	local result: { any } = {}
	for _, part in parts do
		if string.sub(part.name, 1, #prefix) == prefix then
			table.insert(result, part)
		end
	end
	return result
end

local function getByAnyPrefix(parts: { any }, prefixes: { string }): { any }
	local result: { any } = {}
	for _, part in parts do
		for _, prefix in prefixes do
			if string.sub(part.name, 1, #prefix) == prefix then
				table.insert(result, part)
				break
			end
		end
	end
	return result
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

local function nearestDistToZoneCenter(position: Vector3Data, zones: { NamedZone }): number
	local best = math.huge
	for _, zone in zones do
		local d = dist3(position, zone.position)
		if d < best then
			best = d
		end
	end
	return best
end

-- Check 1: At least one TinyfolkSpawn is outside all control zones with safe separation.
-- Prevents Giant from spawning with control zones covering all Tinyfolk spawns.
local function checkGiantZoneSpawnSafety(
	descriptor: RealmDescriptor,
	config: RealmControlZoneConfig
): CheckResult
	local tinyfolkSpawns = getByPrefix(descriptor.spawns, "TinyfolkSpawn")
	local zones = getZonesByTag(descriptor.controlZones, config.zoneTagFilter)
	local minDist = config.minimumSpawnZoneSeparationStuds

	if #zones == 0 then
		return { id = "giant_zone_spawn_safety", passed = true }
	end

	local safeSpawns: { string } = {}
	for _, spawn in tinyfolkSpawns do
		local d = nearestDistToZoneCenter(spawn.position, zones)
		if d >= minDist then
			table.insert(safeSpawns, spawn.name)
		end
	end

	if #safeSpawns > 0 then
		return { id = "giant_zone_spawn_safety", passed = true }
	end

	local violations: { string } = {}
	for _, spawn in tinyfolkSpawns do
		local d = nearestDistToZoneCenter(spawn.position, zones)
		table.insert(
			violations,
			string.format("%s is %.1f studs from nearest zone (min %.1f)", spawn.name, d, minDist)
		)
	end

	return {
		id = "giant_zone_spawn_safety",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

-- Check 2: Each specialist station is outside zones with safe perimeter clearance.
-- Prevents zones from engulfing work areas where Tinyfolk must approach and interact.
local function checkGiantZoneStationAccess(
	descriptor: RealmDescriptor,
	config: RealmControlZoneConfig
): CheckResult
	local stations = getByAnyPrefix(descriptor.stations, { "WorkStation_", "MiningStation_", "Shrine_" })
	local zones = getZonesByTag(descriptor.controlZones, config.zoneTagFilter)
	local minPerimeterDist = config.minimumStationZonePerimeterStuds

	if #zones == 0 then
		return { id = "giant_zone_station_access", passed = true }
	end

	local violations: { string } = {}
	for _, station in stations do
		local centerDist = nearestDistToZoneCenter(station.position, zones)
		-- Find the zone with nearest center to compute perimeter distance
		local perimeterDist = math.huge
		for _, zone in zones do
			local d = dist3(station.position, zone.position)
			local perimeter = d - zone.radius
			if perimeter < perimeterDist then
				perimeterDist = perimeter
			end
		end

		if perimeterDist < minPerimeterDist then
			if perimeterDist < 0 then
				table.insert(
					violations,
					string.format("%s is inside zone (perimeter %.1f)", station.name, perimeterDist)
				)
			else
				table.insert(
					violations,
					string.format(
						"%s is %.1f studs from zone perimeter (min %.1f)",
						station.name,
						perimeterDist,
						minPerimeterDist
					)
				)
			end
		end
	end

	if #violations == 0 then
		return { id = "giant_zone_station_access", passed = true }
	end

	return {
		id = "giant_zone_station_access",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

-- Check 3: Each escape route is outside zones with safe perimeter clearance.
-- Prevents zones from blocking the primary endgame mechanic.
local function checkGiantZoneEscapeRouteSafety(
	descriptor: RealmDescriptor,
	config: RealmControlZoneConfig
): CheckResult
	local routes = descriptor.escapeRoutes
	local zones = getZonesByTag(descriptor.controlZones, config.zoneTagFilter)
	local minPerimeterDist = config.minimumEscapeRouteZonePerimeterStuds

	if #zones == 0 then
		return { id = "giant_zone_escape_route_safety", passed = true }
	end

	local violations: { string } = {}
	for _, route in routes do
		local perimeterDist = math.huge
		for _, zone in zones do
			local d = dist3(route.position, zone.position)
			local perimeter = d - zone.radius
			if perimeter < perimeterDist then
				perimeterDist = perimeter
			end
		end

		if perimeterDist < minPerimeterDist then
			if perimeterDist < 0 then
				table.insert(
					violations,
					string.format("%s is inside zone (perimeter %.1f)", route.name, perimeterDist)
				)
			else
				table.insert(
					violations,
					string.format(
						"%s is %.1f studs from zone perimeter (min %.1f)",
						route.name,
						perimeterDist,
						minPerimeterDist
					)
				)
			end
		end
	end

	if #violations == 0 then
		return { id = "giant_zone_escape_route_safety", passed = true }
	end

	return {
		id = "giant_zone_escape_route_safety",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

function RealmControlZoneValidator.ValidateControlZones(
	descriptor: RealmDescriptor,
	config: RealmControlZoneConfig
): ControlZoneValidationResult
	local results: { CheckResult } = {
		checkGiantZoneSpawnSafety(descriptor, config),
		checkGiantZoneStationAccess(descriptor, config),
		checkGiantZoneEscapeRouteSafety(descriptor, config),
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

return RealmControlZoneValidator
