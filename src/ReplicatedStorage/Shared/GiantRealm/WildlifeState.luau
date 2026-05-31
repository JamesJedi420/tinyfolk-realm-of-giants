--!strict

local WildlifeState: any = {}

WildlifeState.Status = {
	Active = "active",
	Disturbed = "disturbed",
	Expired = "expired",
	Despawned = "despawned",
}

export type WildlifeRecord = {
	wildlifeId: string,
	realmTemplateId: string,
	habitatGroupId: string,
	speciesId: string,
	spawnedAt: number,
	expiresAt: number,
	status: string,
	disturbedAt: number?,
	despawnedAt: number?,
	lastReason: string,
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

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function cloneRecord(record: WildlifeRecord): WildlifeRecord
	return {
		wildlifeId = record.wildlifeId,
		realmTemplateId = record.realmTemplateId,
		habitatGroupId = record.habitatGroupId,
		speciesId = record.speciesId,
		spawnedAt = record.spawnedAt,
		expiresAt = record.expiresAt,
		status = record.status,
		disturbedAt = record.disturbedAt,
		despawnedAt = record.despawnedAt,
		lastReason = record.lastReason,
	}
end

function WildlifeState.IsTerminalStatus(status: any): boolean
	return status == WildlifeState.Status.Expired or status == WildlifeState.Status.Despawned
end

function WildlifeState.IsActive(record: WildlifeRecord?, now: number): boolean
	if record == nil or not validNumber(now) then
		return false
	end
	if WildlifeState.IsTerminalStatus(record.status) then
		return false
	end
	return now < record.expiresAt
end

function WildlifeState.NewRecord(input: any): (boolean, string, WildlifeRecord?)
	if type(input) ~= "table" then
		return false, "wildlife_record_invalid", nil
	end
	if not isNonEmptyString(input.wildlifeId) then
		return false, "wildlife_id_invalid", nil
	end
	if not isNonEmptyString(input.realmTemplateId) then
		return false, "realm_template_id_invalid", nil
	end
	if not isNonEmptyString(input.habitatGroupId) then
		return false, "habitat_group_id_invalid", nil
	end
	if not isNonEmptyString(input.speciesId) then
		return false, "species_id_invalid", nil
	end
	if not validNumber(input.spawnedAt) or input.spawnedAt < 0 then
		return false, "spawned_at_invalid", nil
	end
	if not validNumber(input.expiresAt) or input.expiresAt <= input.spawnedAt then
		return false, "expires_at_invalid", nil
	end

	local record: WildlifeRecord = {
		wildlifeId = input.wildlifeId,
		realmTemplateId = input.realmTemplateId,
		habitatGroupId = input.habitatGroupId,
		speciesId = input.speciesId,
		spawnedAt = input.spawnedAt,
		expiresAt = input.expiresAt,
		status = WildlifeState.Status.Active,
		disturbedAt = nil,
		despawnedAt = nil,
		lastReason = "spawned",
	}
	return true, "accepted", record
end

function WildlifeState.ResolveDisturbance(record: WildlifeRecord?, now: number): (boolean, string, WildlifeRecord?)
	if record == nil then
		return false, "wildlife_not_found", nil
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if WildlifeState.IsTerminalStatus(record.status) then
		return false, "wildlife_terminal", cloneRecord(record)
	end
	if now >= record.expiresAt then
		local expired = cloneRecord(record)
		expired.status = WildlifeState.Status.Expired
		expired.lastReason = "expired"
		expired.despawnedAt = now
		return false, "wildlife_inactive", expired
	end

	local nextRecord = cloneRecord(record)
	nextRecord.status = WildlifeState.Status.Disturbed
	nextRecord.disturbedAt = now
	nextRecord.lastReason = "disturbed"
	return true, "disturbed", nextRecord
end

function WildlifeState.ResolveExpiry(record: WildlifeRecord?, now: number): (boolean, string, WildlifeRecord?)
	if record == nil then
		return false, "wildlife_not_found", nil
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if WildlifeState.IsTerminalStatus(record.status) then
		return false, "wildlife_terminal", cloneRecord(record)
	end
	if now < record.expiresAt then
		return false, "wildlife_not_expired", cloneRecord(record)
	end

	local nextRecord = cloneRecord(record)
	nextRecord.status = WildlifeState.Status.Expired
	nextRecord.despawnedAt = now
	nextRecord.lastReason = "expired"
	return true, "expired", nextRecord
end

function WildlifeState.ResolveDespawn(
	record: WildlifeRecord?,
	reason: string,
	now: number
): (boolean, string, WildlifeRecord?)
	if record == nil then
		return false, "wildlife_not_found", nil
	end
	if not isNonEmptyString(reason) then
		return false, "despawn_reason_invalid", cloneRecord(record)
	end
	if not validNumber(now) then
		return false, "invalid_now", cloneRecord(record)
	end
	if WildlifeState.IsTerminalStatus(record.status) then
		return false, "wildlife_terminal", cloneRecord(record)
	end

	local nextRecord = cloneRecord(record)
	nextRecord.status = WildlifeState.Status.Despawned
	nextRecord.despawnedAt = now
	nextRecord.lastReason = reason
	return true, reason, nextRecord
end

function WildlifeState.BuildSnapshot(record: WildlifeRecord?, now: number): any
	if record == nil then
		return nil
	end
	return {
		wildlifeId = record.wildlifeId,
		realmTemplateId = record.realmTemplateId,
		habitatGroupId = record.habitatGroupId,
		speciesId = record.speciesId,
		spawnedAt = record.spawnedAt,
		expiresAt = record.expiresAt,
		status = record.status,
		disturbedAt = record.disturbedAt,
		despawnedAt = record.despawnedAt,
		lastReason = record.lastReason,
		active = WildlifeState.IsActive(record, now),
	}
end

return WildlifeState
