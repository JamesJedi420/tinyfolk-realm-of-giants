--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmStationAccessValidator = {}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type Vector3Data = RealmTopologyValidator.Vector3Data
export type NamedPart = RealmTopologyValidator.NamedPart

export type RealmStationAccessConfig = {
	-- Name prefixes identifying stations Tinyfolk must walk to and activate.
	-- Typically: {"WorkStation_", "MiningStation_", "Shrine_"}
	specialistStationPrefixes: { string },
	-- Subset of specialistStationPrefixes that produce goods requiring hauling.
	-- Excludes Shrine (Essence goes directly to Giant pool; no haul path).
	-- Typically: {"WorkStation_", "MiningStation_"}
	productionStationPrefixes: { string },
	-- Name prefix for warehouse/storage delivery points.
	warehousePrefix: string,
	-- Maximum straight-line distance (studs) from any TinyfolkSpawn to each specialist station.
	specialistStationMaxPathStuds: number,
	-- Maximum straight-line distance (studs) from any TinyfolkSpawn to each warehouse.
	warehouseMaxPathStuds: number,
	-- Maximum straight-line distance (studs) from each production station to its nearest warehouse.
	haulMaxStuds: number,
	-- Maximum straight-line distance (studs) from any TinyfolkSpawn to each construction site.
	constructionSiteMaxPathStuds: number,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type StationAccessValidationResult = {
	passed: boolean,
	results: { CheckResult },
}

local function dist3(a: Vector3Data, b: Vector3Data): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getByAnyPrefix(parts: { NamedPart }, prefixes: { string }): { NamedPart }
	local result: { NamedPart } = {}
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

local function getByPrefix(parts: { NamedPart }, prefix: string): { NamedPart }
	local result: { NamedPart } = {}
	for _, part in parts do
		if string.sub(part.name, 1, #prefix) == prefix then
			table.insert(result, part)
		end
	end
	return result
end

local function nearestDistToSet(part: NamedPart, candidates: { NamedPart }): number
	local best = math.huge
	for _, candidate in candidates do
		local d = dist3(part.position, candidate.position)
		if d < best then
			best = d
		end
	end
	return best
end

-- Check 1: Every specialist station is within specialistStationMaxPathStuds of a TinyfolkSpawn.
-- Catches: specialist stations placed out of practical Tinyfolk reach.
local function checkSpecialistStationTinyfolkAccess(
	descriptor: RealmDescriptor,
	config: RealmStationAccessConfig
): CheckResult
	local tinyfolkSpawns = getByPrefix(descriptor.spawns, "TinyfolkSpawn")
	local stations = getByAnyPrefix(descriptor.stations, config.specialistStationPrefixes)
	local maxDist = config.specialistStationMaxPathStuds
	local violations: { string } = {}

	for _, station in stations do
		local d = nearestDistToSet(station, tinyfolkSpawns)
		if d > maxDist then
			table.insert(
				violations,
				string.format(
					"%s is %.1f studs from nearest TinyfolkSpawn (max %.1f)",
					station.name,
					d,
					maxDist
				)
			)
		end
	end

	if #violations == 0 then
		return { id = "specialist_station_tinyfolk_access", passed = true }
	end
	return {
		id = "specialist_station_tinyfolk_access",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

-- Check 2: Every warehouse is within warehouseMaxPathStuds of a TinyfolkSpawn.
-- Catches: warehouse placed so far that haulers cannot deliver.
local function checkWarehouseTinyfolkAccess(
	descriptor: RealmDescriptor,
	config: RealmStationAccessConfig
): CheckResult
	local tinyfolkSpawns = getByPrefix(descriptor.spawns, "TinyfolkSpawn")
	local warehouses = getByPrefix(descriptor.stations, config.warehousePrefix)
	local maxDist = config.warehouseMaxPathStuds
	local violations: { string } = {}

	for _, warehouse in warehouses do
		local d = nearestDistToSet(warehouse, tinyfolkSpawns)
		if d > maxDist then
			table.insert(
				violations,
				string.format(
					"%s is %.1f studs from nearest TinyfolkSpawn (max %.1f)",
					warehouse.name,
					d,
					maxDist
				)
			)
		end
	end

	if #violations == 0 then
		return { id = "warehouse_tinyfolk_access", passed = true }
	end
	return {
		id = "warehouse_tinyfolk_access",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

-- Check 3: Every production station has a warehouse within haulMaxStuds.
-- Catches: production station and warehouse on opposite ends of the map.
-- Shrine is excluded (Essence has no haul path; goes directly to Giant pool).
local function checkProductionWarehouseHaulLoop(
	descriptor: RealmDescriptor,
	config: RealmStationAccessConfig
): CheckResult
	local productionStations = getByAnyPrefix(descriptor.stations, config.productionStationPrefixes)
	local warehouses = getByPrefix(descriptor.stations, config.warehousePrefix)
	local maxDist = config.haulMaxStuds
	local violations: { string } = {}

	for _, station in productionStations do
		local d = nearestDistToSet(station, warehouses)
		if d > maxDist then
			table.insert(
				violations,
				string.format(
					"%s is %.1f studs from nearest warehouse (max %.1f)",
					station.name,
					d,
					maxDist
				)
			)
		end
	end

	if #violations == 0 then
		return { id = "production_warehouse_haul_loop", passed = true }
	end
	return {
		id = "production_warehouse_haul_loop",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

-- Check 4: Every construction site is within constructionSiteMaxPathStuds of a TinyfolkSpawn.
-- Catches: construction sites placed out of Tinyfolk reach.
local function checkConstructionSiteTinyfolkAccess(
	descriptor: RealmDescriptor,
	config: RealmStationAccessConfig
): CheckResult
	local tinyfolkSpawns = getByPrefix(descriptor.spawns, "TinyfolkSpawn")
	local maxDist = config.constructionSiteMaxPathStuds
	local violations: { string } = {}

	for _, site in descriptor.constructionSites do
		local d = nearestDistToSet(site, tinyfolkSpawns)
		if d > maxDist then
			table.insert(
				violations,
				string.format(
					"%s is %.1f studs from nearest TinyfolkSpawn (max %.1f)",
					site.name,
					d,
					maxDist
				)
			)
		end
	end

	if #violations == 0 then
		return { id = "construction_site_tinyfolk_access", passed = true }
	end
	return {
		id = "construction_site_tinyfolk_access",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

function RealmStationAccessValidator.ValidateStationAccess(
	descriptor: RealmDescriptor,
	config: RealmStationAccessConfig
): StationAccessValidationResult
	local results: { CheckResult } = {
		checkSpecialistStationTinyfolkAccess(descriptor, config),
		checkWarehouseTinyfolkAccess(descriptor, config),
		checkProductionWarehouseHaulLoop(descriptor, config),
		checkConstructionSiteTinyfolkAccess(descriptor, config),
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

return RealmStationAccessValidator
