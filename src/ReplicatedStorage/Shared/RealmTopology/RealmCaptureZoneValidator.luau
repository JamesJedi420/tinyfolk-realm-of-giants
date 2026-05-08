--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor
export type Vector3Data = RealmTopologyValidator.Vector3Data

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type CaptureZoneConfig = {
	minimumSpawnSeparationStuds: number,
	minimumEscapeSeparationStuds: number,
	minimumCaptureRadiusStuds: number,
	maximumCaptureRadiusStuds: number,
	minimumCaptureZoneGapStuds: number,
	captureZoneClusterRadiusStuds: number,
	maximumCaptureZoneNeighborsInClusterRadius: number,
	maximumCaptureZonesPerRealm: number,
}

local function distance(pos1: Vector3Data, pos2: Vector3Data): number
	local dx = pos1.x - pos2.x
	local dy = pos1.y - pos2.y
	local dz = pos1.z - pos2.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function captureZoneSpawnSeparation(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	if #descriptor.captureZones == 0 then
		return {
			id = "capture_zone_spawn_separation",
			passed = true,
			reason = nil,
		}
	end

	if #descriptor.spawns == 0 then
		return {
			id = "capture_zone_spawn_separation",
			passed = true,
			reason = nil,
		}
	end

	for _, captureZone in ipairs(descriptor.captureZones) do
		for _, spawn in ipairs(descriptor.spawns) do
			local d = distance(captureZone.position, spawn.position)
			if d < config.minimumSpawnSeparationStuds then
				return {
					id = "capture_zone_spawn_separation",
					passed = false,
					reason = "Capture zone '"
						.. captureZone.name
						.. "' is "
						.. string.format("%.1f", d)
						.. " studs from spawn '"
						.. spawn.name
						.. "' (minimum: "
						.. tostring(config.minimumSpawnSeparationStuds)
						.. " studs)",
				}
			end
		end
	end

	return {
		id = "capture_zone_spawn_separation",
		passed = true,
		reason = nil,
	}
end

local function captureZoneEscapeSeparation(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	if #descriptor.captureZones == 0 then
		return {
			id = "capture_zone_escape_separation",
			passed = true,
			reason = nil,
		}
	end

	if #descriptor.escapeRoutes == 0 then
		return {
			id = "capture_zone_escape_separation",
			passed = true,
			reason = nil,
		}
	end

	for _, captureZone in ipairs(descriptor.captureZones) do
		for _, escapeRoute in ipairs(descriptor.escapeRoutes) do
			local d = distance(captureZone.position, escapeRoute.position)
			if d < config.minimumEscapeSeparationStuds then
				return {
					id = "capture_zone_escape_separation",
					passed = false,
					reason = "Capture zone '"
						.. captureZone.name
						.. "' is "
						.. string.format("%.1f", d)
						.. " studs from escape route '"
						.. escapeRoute.name
						.. "' (minimum: "
						.. tostring(config.minimumEscapeSeparationStuds)
						.. " studs)",
				}
			end
		end
	end

	return {
		id = "capture_zone_escape_separation",
		passed = true,
		reason = nil,
	}
end

local function captureZoneRadiusBounds(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	if #descriptor.captureZones == 0 then
		return {
			id = "capture_zone_radius_bounds",
			passed = true,
			reason = nil,
		}
	end

	for _, captureZone in ipairs(descriptor.captureZones) do
		if captureZone.tag ~= "GiantCapture" then
			continue
		end
		if captureZone.radius < config.minimumCaptureRadiusStuds then
			return {
				id = "capture_zone_radius_bounds",
				passed = false,
				reason = "Capture zone '"
					.. captureZone.name
					.. "' radius "
					.. tostring(captureZone.radius)
					.. " is below minimum "
					.. tostring(config.minimumCaptureRadiusStuds)
					.. " studs",
			}
		elseif captureZone.radius > config.maximumCaptureRadiusStuds then
			return {
				id = "capture_zone_radius_bounds",
				passed = false,
				reason = "Capture zone '"
					.. captureZone.name
					.. "' radius "
					.. tostring(captureZone.radius)
					.. " exceeds maximum "
					.. tostring(config.maximumCaptureRadiusStuds)
					.. " studs",
			}
		end
	end

	return {
		id = "capture_zone_radius_bounds",
		passed = true,
		reason = nil,
	}
end

-- Slice 14: spawn perimeter clearance
-- Convention: vacuous pass when captureZones or spawns is empty, matching spawn-separation rule.
-- Non-GiantCapture tags are skipped (matching captureZoneRadiusBounds convention).
local function captureZoneSpawnPerimeterClearance(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	if #descriptor.captureZones == 0 then
		return {
			id = "capture_zone_spawn_perimeter_clearance",
			passed = true,
			reason = nil,
		}
	end

	if #descriptor.spawns == 0 then
		return {
			id = "capture_zone_spawn_perimeter_clearance",
			passed = true,
			reason = nil,
		}
	end

	for _, captureZone in ipairs(descriptor.captureZones) do
		if captureZone.tag ~= "GiantCapture" then
			continue
		end
		for _, spawn in ipairs(descriptor.spawns) do
			local d = distance(captureZone.position, spawn.position)
			if d - captureZone.radius <= 0 then
				return {
					id = "capture_zone_spawn_perimeter_clearance",
					passed = false,
					reason = "Spawn '"
						.. spawn.name
						.. "' lies inside or on the perimeter of capture zone '"
						.. captureZone.name
						.. "' (dist="
						.. string.format("%.2f", d)
						.. ", radius="
						.. tostring(captureZone.radius)
						.. ")",
				}
			end
		end
	end

	return {
		id = "capture_zone_spawn_perimeter_clearance",
		passed = true,
		reason = nil,
	}
end

-- Slice 15: escape perimeter clearance
-- Convention: vacuous pass when captureZones or escapeRoutes is empty, matching escape-separation rule.
-- Non-GiantCapture tags are skipped.
local function captureZoneEscapePerimeterClearance(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	if #descriptor.captureZones == 0 then
		return {
			id = "capture_zone_escape_perimeter_clearance",
			passed = true,
			reason = nil,
		}
	end

	if #descriptor.escapeRoutes == 0 then
		return {
			id = "capture_zone_escape_perimeter_clearance",
			passed = true,
			reason = nil,
		}
	end

	for _, captureZone in ipairs(descriptor.captureZones) do
		if captureZone.tag ~= "GiantCapture" then
			continue
		end
		for _, escapeRoute in ipairs(descriptor.escapeRoutes) do
			local d = distance(captureZone.position, escapeRoute.position)
			if d - captureZone.radius <= 0 then
				return {
					id = "capture_zone_escape_perimeter_clearance",
					passed = false,
					reason = "Escape route '"
						.. escapeRoute.name
						.. "' lies inside or on the perimeter of capture zone '"
						.. captureZone.name
						.. "' (dist="
						.. string.format("%.2f", d)
						.. ", radius="
						.. tostring(captureZone.radius)
						.. ")",
				}
			end
		end
	end

	return {
		id = "capture_zone_escape_perimeter_clearance",
		passed = true,
		reason = nil,
	}
end

-- Slice 16: capture_zone_overlap
-- Rule: for each unique pair of GiantCapture zones, fail if dist < r1 + r2.
-- Touching at exactly one point (dist == r1 + r2) is allowed.
-- Non-GiantCapture zones are ignored, matching the convention used by
-- captureZoneRadiusBounds, captureZoneSpawnPerimeterClearance, and
-- captureZoneEscapePerimeterClearance.
-- Vacuous pass when fewer than two GiantCapture zones exist.
local function captureZoneOverlap(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	-- Collect only GiantCapture zones so pair indices are stable and deterministic.
	local giantZones: { RealmTopologyValidator.NamedZone } = {}
	for _, zone in ipairs(descriptor.captureZones) do
		if zone.tag == "GiantCapture" then
			table.insert(giantZones, zone)
		end
	end

	if #giantZones < 2 then
		return {
			id = "capture_zone_overlap",
			passed = true,
			reason = nil,
		}
	end

	for i = 1, #giantZones - 1 do
		for j = i + 1, #giantZones do
			local a = giantZones[i]
			local b = giantZones[j]
			local d = distance(a.position, b.position)
			if d < a.radius + b.radius then
				return {
					id = "capture_zone_overlap",
					passed = false,
					reason = "Capture zones '" .. a.name .. "' and '" .. b.name .. "' overlap (dist=" .. string.format(
						"%.2f",
						d
					) .. ", r1+r2=" .. tostring(a.radius + b.radius) .. ")",
				}
			end
		end
	end

	return {
		id = "capture_zone_overlap",
		passed = true,
		reason = nil,
	}
end

-- Slice 17: capture_zone_minimum_spacing
-- Rule: for each unique pair of GiantCapture zones, compute
-- perimeterGap = dist - (r1 + r2), then fail if perimeterGap is below
-- config.minimumCaptureZoneGapStuds.
-- Non-GiantCapture zones are ignored.
-- Vacuous pass when fewer than two GiantCapture zones exist.
local function captureZoneMinimumSpacing(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	local giantZones: { RealmTopologyValidator.NamedZone } = {}
	for _, zone in ipairs(descriptor.captureZones) do
		if zone.tag == "GiantCapture" then
			table.insert(giantZones, zone)
		end
	end

	if #giantZones < 2 then
		return {
			id = "capture_zone_minimum_spacing",
			passed = true,
			reason = nil,
		}
	end

	for i = 1, #giantZones - 1 do
		for j = i + 1, #giantZones do
			local a = giantZones[i]
			local b = giantZones[j]
			local d = distance(a.position, b.position)
			local perimeterGap = d - (a.radius + b.radius)
			if perimeterGap < config.minimumCaptureZoneGapStuds then
				return {
					id = "capture_zone_minimum_spacing",
					passed = false,
					reason = "Capture zones '"
						.. a.name
						.. "' and '"
						.. b.name
						.. "' have perimeter gap "
						.. string.format("%.2f", perimeterGap)
						.. " studs (minimum: "
						.. tostring(config.minimumCaptureZoneGapStuds)
						.. " studs)",
				}
			end
		end
	end

	return {
		id = "capture_zone_minimum_spacing",
		passed = true,
		reason = nil,
	}
end

-- Slice 21: capture_zone_cluster_density_cap
-- Rule: for each GiantCapture zone, count how many other GiantCapture zone
-- centers are within config.captureZoneClusterRadiusStuds.
-- Fail when count exceeds config.maximumCaptureZoneNeighborsInClusterRadius.
-- Boundary pass when count equals the configured maximum.
-- Non-GiantCapture zones are ignored.
-- Vacuous pass when fewer than two GiantCapture zones exist.
local function captureZoneClusterDensityCap(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	local giantZones: { RealmTopologyValidator.NamedZone } = {}
	for _, zone in ipairs(descriptor.captureZones) do
		if zone.tag == "GiantCapture" then
			table.insert(giantZones, zone)
		end
	end

	if #giantZones < 2 then
		return {
			id = "capture_zone_cluster_density_cap",
			passed = true,
			reason = nil,
		}
	end

	for i = 1, #giantZones do
		local centerZone = giantZones[i]
		local neighborCount = 0
		for j = 1, #giantZones do
			if i == j then
				continue
			end
			local d = distance(centerZone.position, giantZones[j].position)
			if d <= config.captureZoneClusterRadiusStuds then
				neighborCount += 1
			end
		end

		if neighborCount > config.maximumCaptureZoneNeighborsInClusterRadius then
			return {
				id = "capture_zone_cluster_density_cap",
				passed = false,
				reason = "Capture zone '"
					.. centerZone.name
					.. "' has "
					.. tostring(neighborCount)
					.. " neighboring GiantCapture zone center(s) within "
					.. tostring(config.captureZoneClusterRadiusStuds)
					.. " studs (maximum allowed: "
					.. tostring(config.maximumCaptureZoneNeighborsInClusterRadius)
					.. ")",
			}
		end
	end

	return {
		id = "capture_zone_cluster_density_cap",
		passed = true,
		reason = nil,
	}
end

-- Slice 22: capture_zone_total_cap
-- Rule: count total GiantCapture zones in descriptor.captureZones and fail when
-- the filtered total exceeds config.maximumCaptureZonesPerRealm.
-- Boundary pass at exact maximum.
-- Non-GiantCapture zones are ignored.
local function captureZoneTotalCap(descriptor: RealmDescriptor, config: CaptureZoneConfig): CheckResult
	local giantCaptureCount = 0
	for _, zone in ipairs(descriptor.captureZones) do
		if zone.tag == "GiantCapture" then
			giantCaptureCount += 1
		end
	end

	if giantCaptureCount > config.maximumCaptureZonesPerRealm then
		return {
			id = "capture_zone_total_cap",
			passed = false,
			reason = "Total GiantCapture zone count "
				.. tostring(giantCaptureCount)
				.. " exceeds maximumCaptureZonesPerRealm "
				.. tostring(config.maximumCaptureZonesPerRealm),
		}
	end

	return {
		id = "capture_zone_total_cap",
		passed = true,
		reason = nil,
	}
end

return {
	captureZoneSpawnSeparation = captureZoneSpawnSeparation,
	captureZoneEscapeSeparation = captureZoneEscapeSeparation,
	captureZoneRadiusBounds = captureZoneRadiusBounds,
	captureZoneSpawnPerimeterClearance = captureZoneSpawnPerimeterClearance,
	captureZoneEscapePerimeterClearance = captureZoneEscapePerimeterClearance,
	captureZoneOverlap = captureZoneOverlap,
	captureZoneMinimumSpacing = captureZoneMinimumSpacing,
	captureZoneClusterDensityCap = captureZoneClusterDensityCap,
	captureZoneTotalCap = captureZoneTotalCap,
}
