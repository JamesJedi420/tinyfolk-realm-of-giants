--!strict

local SnareTrapState: any = {}

export type Vector3Data = { x: number, y: number, z: number }
export type TrapRecord = {
	structureId: string,
	placedByUserId: number,
	placedAt: number,
	center: Vector3Data,
	triggerRadiusStuds: number,
	expiresAt: number,
	triggeredAt: number?,
	triggeredByUserId: number?,
}

local function cloneCenter(center: Vector3Data): Vector3Data
	return { x = center.x, y = center.y, z = center.z }
end

local function cloneRecord(record: TrapRecord): TrapRecord
	return {
		structureId = record.structureId,
		placedByUserId = record.placedByUserId,
		placedAt = record.placedAt,
		center = cloneCenter(record.center),
		triggerRadiusStuds = record.triggerRadiusStuds,
		expiresAt = record.expiresAt,
		triggeredAt = record.triggeredAt,
		triggeredByUserId = record.triggeredByUserId,
	}
end

local function vectorDistance(a: Vector3Data, b: Vector3Data): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function SnareTrapState.NewRecord(
	structureId: string,
	placedByUserId: number,
	placedAt: number,
	center: Vector3Data,
	triggerRadiusStuds: number,
	durationSeconds: number
): TrapRecord
	return {
		structureId = structureId,
		placedByUserId = placedByUserId,
		placedAt = placedAt,
		center = cloneCenter(center),
		triggerRadiusStuds = triggerRadiusStuds,
		expiresAt = placedAt + math.max(0, durationSeconds),
		triggeredAt = nil,
		triggeredByUserId = nil,
	}
end

function SnareTrapState.IsActive(record: TrapRecord?, now: number): boolean
	if record == nil then
		return false
	end
	if type(now) ~= "number" then
		return false
	end
	if record.triggeredAt ~= nil then
		return false
	end
	return now < record.expiresAt
end

function SnareTrapState.ResolveContact(
	record: TrapRecord?,
	triggeredByUserId: number,
	contactPosition: Vector3Data,
	now: number
): (boolean, string, TrapRecord?)
	if record == nil then
		return false, "snare_trap_missing", nil
	end
	if type(triggeredByUserId) ~= "number" then
		return false, "snare_trap_invalid_triggering_user", cloneRecord(record)
	end
	if type(contactPosition) ~= "table" then
		return false, "snare_trap_invalid_contact_position", cloneRecord(record)
	end
	if
		type(contactPosition.x) ~= "number"
		or type(contactPosition.y) ~= "number"
		or type(contactPosition.z) ~= "number"
	then
		return false, "snare_trap_invalid_contact_position", cloneRecord(record)
	end
	if type(now) ~= "number" then
		return false, "invalid_now", cloneRecord(record)
	end
	if not SnareTrapState.IsActive(record, now) then
		return false, "snare_trap_inactive", cloneRecord(record)
	end
	if vectorDistance(record.center, contactPosition) > record.triggerRadiusStuds then
		return false, "snare_trap_out_of_range", cloneRecord(record)
	end

	local nextRecord = cloneRecord(record)
	nextRecord.triggeredAt = now
	nextRecord.triggeredByUserId = triggeredByUserId
	return true, "triggered", nextRecord
end

function SnareTrapState.BuildSnapshot(record: TrapRecord?, now: number): any
	if record == nil then
		return nil
	end

	local armed = SnareTrapState.IsActive(record, now)
	return {
		structureId = record.structureId,
		placedByUserId = record.placedByUserId,
		placedAt = record.placedAt,
		center = cloneCenter(record.center),
		triggerRadiusStuds = record.triggerRadiusStuds,
		expiresAt = record.expiresAt,
		triggeredAt = record.triggeredAt,
		triggeredByUserId = record.triggeredByUserId,
		armed = armed,
		active = armed,
	}
end

return SnareTrapState
