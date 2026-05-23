--!strict

local SnareTrapState: any = {}

SnareTrapState.Status = {
	Armed = "armed",
	Triggered = "triggered",
	Disarmed = "disarmed",
	Expired = "expired",
	Destroyed = "destroyed",
	Rescued = "rescued",
	Invalidated = "invalidated",
}

export type Vector3Data = { x: number, y: number, z: number }
export type TrapRecord = {
	trapId: string,
	structureId: string,
	placedByUserId: number,
	placedAt: number,
	center: Vector3Data,
	triggerRadiusStuds: number,
	expiresAt: number,
	status: string,
	triggeredAt: number?,
	triggeredByUserId: number?,
	resolvedAt: number?,
	resolvedByUserId: number?,
	lastReason: string?,
}

local function validNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function validVector(value: any): boolean
	return type(value) == "table" and validNumber(value.x) and validNumber(value.y) and validNumber(value.z)
end

local function cloneCenter(center: Vector3Data): Vector3Data
	return { x = center.x, y = center.y, z = center.z }
end

local function cloneRecord(record: TrapRecord): TrapRecord
	return {
		trapId = record.trapId,
		structureId = record.structureId,
		placedByUserId = record.placedByUserId,
		placedAt = record.placedAt,
		center = cloneCenter(record.center),
		triggerRadiusStuds = record.triggerRadiusStuds,
		expiresAt = record.expiresAt,
		status = record.status,
		triggeredAt = record.triggeredAt,
		triggeredByUserId = record.triggeredByUserId,
		resolvedAt = record.resolvedAt,
		resolvedByUserId = record.resolvedByUserId,
		lastReason = record.lastReason,
	}
end

local function transition(
	record: TrapRecord,
	status: string,
	reason: string,
	resolvedByUserId: number?,
	now: number
): TrapRecord
	local nextRecord = cloneRecord(record)
	nextRecord.status = status
	nextRecord.lastReason = reason
	nextRecord.resolvedAt = now
	nextRecord.resolvedByUserId = resolvedByUserId
	return nextRecord
end

local function vectorDistance(a: Vector3Data, b: Vector3Data): number
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function SnareTrapState.NewRecord(
	trapId: string,
	structureId: string,
	placedByUserId: number,
	placedAt: number,
	center: Vector3Data,
	triggerRadiusStuds: number,
	durationSeconds: number
): TrapRecord
	return {
		trapId = trapId,
		structureId = structureId,
		placedByUserId = placedByUserId,
		placedAt = placedAt,
		center = cloneCenter(center),
		triggerRadiusStuds = triggerRadiusStuds,
		expiresAt = placedAt + math.max(0, durationSeconds),
		status = SnareTrapState.Status.Armed,
		triggeredAt = nil,
		triggeredByUserId = nil,
		resolvedAt = nil,
		resolvedByUserId = nil,
		lastReason = "armed",
	}
end

function SnareTrapState.IsTerminalStatus(status: any): boolean
	return status == SnareTrapState.Status.Disarmed
		or status == SnareTrapState.Status.Expired
		or status == SnareTrapState.Status.Destroyed
		or status == SnareTrapState.Status.Rescued
		or status == SnareTrapState.Status.Invalidated
end

function SnareTrapState.IsActive(record: TrapRecord?, now: number): boolean
	if record == nil or not validNumber(now) then
		return false
	end
	return record.status == SnareTrapState.Status.Armed and now < record.expiresAt
end

function SnareTrapState.IsInteractionInRange(record: TrapRecord?, position: any, radiusStuds: any): boolean
	if record == nil or not validVector(position) or not validNumber(radiusStuds) then
		return false
	end
	return vectorDistance(record.center, position) <= radiusStuds
end

function SnareTrapState.ResolveExpiry(record: TrapRecord?, now: number): (boolean, string, TrapRecord?)
	if record == nil then
		return false, "snare_trap_missing", nil
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if SnareTrapState.IsTerminalStatus(record.status) then
		return false, "snare_trap_terminal", cloneRecord(record)
	end
	if now < record.expiresAt then
		return false, "snare_trap_not_expired", cloneRecord(record)
	end
	return true, "expired", transition(record, SnareTrapState.Status.Expired, "expired", nil, now)
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
	if not validNumber(triggeredByUserId) then
		return false, "snare_trap_invalid_triggering_user", cloneRecord(record)
	end
	if not validVector(contactPosition) then
		return false, "snare_trap_invalid_contact_position", cloneRecord(record)
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	local expired, _, expiredRecord = SnareTrapState.ResolveExpiry(record, now)
	if expired then
		return false, "snare_trap_inactive", expiredRecord
	end
	if not SnareTrapState.IsActive(record, now) then
		return false, "snare_trap_inactive", cloneRecord(record)
	end
	if vectorDistance(record.center, contactPosition) > record.triggerRadiusStuds then
		return false, "snare_trap_out_of_range", cloneRecord(record)
	end

	local nextRecord = cloneRecord(record)
	nextRecord.status = SnareTrapState.Status.Triggered
	nextRecord.triggeredAt = now
	nextRecord.triggeredByUserId = triggeredByUserId
	nextRecord.lastReason = "triggered"
	return true, "triggered", nextRecord
end

function SnareTrapState.ResolveDisarm(
	record: TrapRecord?,
	disarmedByUserId: number,
	now: number
): (boolean, string, TrapRecord?)
	if record == nil then
		return false, "snare_trap_missing", nil
	end
	if not validNumber(disarmedByUserId) then
		return false, "snare_trap_invalid_disarming_user", cloneRecord(record)
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if SnareTrapState.IsTerminalStatus(record.status) then
		return false, "snare_trap_terminal", cloneRecord(record)
	end
	local expired, _, expiredRecord = SnareTrapState.ResolveExpiry(record, now)
	if expired then
		return false, "snare_trap_inactive", expiredRecord
	end
	if not SnareTrapState.IsActive(record, now) then
		return false, "snare_trap_inactive", cloneRecord(record)
	end
	return true, "disarmed", transition(record, SnareTrapState.Status.Disarmed, "disarmed", disarmedByUserId, now)
end

function SnareTrapState.ResolveRescue(
	record: TrapRecord?,
	rescuerUserId: number,
	now: number
): (boolean, string, TrapRecord?)
	if record == nil then
		return false, "snare_trap_missing", nil
	end
	if not validNumber(rescuerUserId) then
		return false, "snare_trap_invalid_rescuer", cloneRecord(record)
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if SnareTrapState.IsTerminalStatus(record.status) then
		return false, "snare_trap_terminal", cloneRecord(record)
	end
	local expired, _, expiredRecord = SnareTrapState.ResolveExpiry(record, now)
	if expired then
		return false, "snare_trap_inactive", expiredRecord
	end
	if record.status ~= SnareTrapState.Status.Triggered then
		return false, "snare_trap_not_triggered", cloneRecord(record)
	end
	return true, "rescued", transition(record, SnareTrapState.Status.Rescued, "rescued", rescuerUserId, now)
end

function SnareTrapState.ResolveDestroyed(record: TrapRecord?, now: number): (boolean, string, TrapRecord?)
	if record == nil then
		return false, "snare_trap_missing", nil
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if SnareTrapState.IsTerminalStatus(record.status) then
		return false, "snare_trap_terminal", cloneRecord(record)
	end
	return true, "destroyed", transition(record, SnareTrapState.Status.Destroyed, "destroyed", nil, now)
end

function SnareTrapState.ResolveInvalidated(record: TrapRecord?, now: number): (boolean, string, TrapRecord?)
	if record == nil then
		return false, "snare_trap_missing", nil
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if SnareTrapState.IsTerminalStatus(record.status) then
		return false, "snare_trap_terminal", cloneRecord(record)
	end
	return true, "invalidated", transition(record, SnareTrapState.Status.Invalidated, "invalidated", nil, now)
end

function SnareTrapState.BuildSnapshot(record: TrapRecord?, now: number): any
	if record == nil then
		return nil
	end

	local active = SnareTrapState.IsActive(record, now)
	return {
		trapId = record.trapId,
		structureId = record.structureId,
		placedByUserId = record.placedByUserId,
		placedAt = record.placedAt,
		center = cloneCenter(record.center),
		triggerRadiusStuds = record.triggerRadiusStuds,
		expiresAt = record.expiresAt,
		status = record.status,
		triggeredAt = record.triggeredAt,
		triggeredByUserId = record.triggeredByUserId,
		resolvedAt = record.resolvedAt,
		resolvedByUserId = record.resolvedByUserId,
		lastReason = record.lastReason,
		armed = active,
		active = active,
	}
end

return SnareTrapState
