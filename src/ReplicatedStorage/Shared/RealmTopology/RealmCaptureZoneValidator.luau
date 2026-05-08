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

return {
	captureZoneSpawnSeparation = captureZoneSpawnSeparation,
}
