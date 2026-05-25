--!strict

local RealmAdmissionQueueState: any = {}

export type EntryType = "standard" | "rescue_contract" | "direct_invite"

export type QueueEntry = {
	operationId: string,
	partyId: string,
	targetRealmId: string,
	entryType: EntryType,
	priority: number,
	createdAt: number,
	expiration: number,
	partySize: number,
	retryCount: number,
}

export type ValidationResult = {
	ok: boolean,
	reason: string?,
	entry: QueueEntry?,
}

local PRIORITY_BY_ENTRY_TYPE: { [EntryType]: number } = {
	standard = 100,
	direct_invite = 200,
	rescue_contract = 300,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return string.len(value) > 0
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonNegativeInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value < 0 then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return true
end

local function cloneEntry(entry: QueueEntry): QueueEntry
	return {
		operationId = entry.operationId,
		partyId = entry.partyId,
		targetRealmId = entry.targetRealmId,
		entryType = entry.entryType,
		priority = entry.priority,
		createdAt = entry.createdAt,
		expiration = entry.expiration,
		partySize = entry.partySize,
		retryCount = entry.retryCount,
	}
end

function RealmAdmissionQueueState.ResolvePriority(entryType: any, requestedPriority: any?): (number?, string?)
	if type(entryType) ~= "string" then
		return nil, "entry_type_invalid"
	end

	local baseline = PRIORITY_BY_ENTRY_TYPE[entryType :: EntryType]
	if type(baseline) ~= "number" then
		return nil, "entry_type_invalid"
	end

	if requestedPriority == nil then
		return baseline, nil
	end
	if not isNonNegativeInteger(requestedPriority) then
		return nil, "priority_invalid"
	end

	local resolvedPriority = requestedPriority :: number
	if resolvedPriority < baseline then
		resolvedPriority = baseline
	end
	return resolvedPriority, nil
end

function RealmAdmissionQueueState.ValidateEntry(input: any): ValidationResult
	if type(input) ~= "table" then
		return { ok = false, reason = "entry_invalid", entry = nil }
	end
	if not isNonEmptyString(input.operationId) then
		return { ok = false, reason = "operation_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.partyId) then
		return { ok = false, reason = "party_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.targetRealmId) then
		return { ok = false, reason = "target_realm_id_invalid", entry = nil }
	end

	local priority, priorityReason = RealmAdmissionQueueState.ResolvePriority(input.entryType, input.priority)
	if priority == nil then
		return { ok = false, reason = priorityReason or "priority_invalid", entry = nil }
	end

	if not isFiniteNumber(input.createdAt) or input.createdAt < 0 then
		return { ok = false, reason = "created_at_invalid", entry = nil }
	end
	if not isFiniteNumber(input.expiration) or input.expiration <= input.createdAt then
		return { ok = false, reason = "expiration_invalid", entry = nil }
	end

	local partySize = if input.partySize == nil then 1 else input.partySize
	if not isPositiveInteger(partySize) then
		return { ok = false, reason = "party_size_invalid", entry = nil }
	end

	local retryCount = if input.retryCount == nil then 0 else input.retryCount
	if not isNonNegativeInteger(retryCount) then
		return { ok = false, reason = "retry_count_invalid", entry = nil }
	end

	local entry: QueueEntry = {
		operationId = input.operationId,
		partyId = input.partyId,
		targetRealmId = input.targetRealmId,
		entryType = input.entryType,
		priority = priority,
		createdAt = input.createdAt,
		expiration = input.expiration,
		partySize = partySize,
		retryCount = retryCount,
	}

	return {
		ok = true,
		reason = nil,
		entry = entry,
	}
end

function RealmAdmissionQueueState.NewEntry(input: any): ValidationResult
	return RealmAdmissionQueueState.ValidateEntry(input)
end

function RealmAdmissionQueueState.GetSnapshot(entry: QueueEntry): QueueEntry?
	local validation = RealmAdmissionQueueState.ValidateEntry(entry)
	if not validation.ok then
		return nil
	end
	return cloneEntry(validation.entry :: QueueEntry)
end

function RealmAdmissionQueueState.IsExpired(entry: QueueEntry, nowAt: number): boolean
	local validation = RealmAdmissionQueueState.ValidateEntry(entry)
	if not validation.ok then
		return true
	end
	if not isFiniteNumber(nowAt) or nowAt < 0 then
		return true
	end

	return nowAt >= (validation.entry :: QueueEntry).expiration
end

function RealmAdmissionQueueState.WithRetryIncrement(entry: QueueEntry): ValidationResult
	local validation = RealmAdmissionQueueState.ValidateEntry(entry)
	if not validation.ok then
		return { ok = false, reason = validation.reason or "entry_invalid", entry = nil }
	end

	local nextEntry = cloneEntry(validation.entry :: QueueEntry)
	nextEntry.retryCount += 1

	return {
		ok = true,
		reason = nil,
		entry = nextEntry,
	}
end

return RealmAdmissionQueueState
