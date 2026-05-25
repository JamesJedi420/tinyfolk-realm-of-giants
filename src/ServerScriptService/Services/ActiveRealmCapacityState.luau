--!strict

local ActiveRealmCapacityState: any = {}

export type Entry = {
	realmId: string,
	currentTinyfolk: number,
	currentGiants: number,
	reservedSlots: number,
	maxTinyfolk: number,
	maxGiants: number,
	updatedAt: number,
}

export type EntryResult = {
	accepted: boolean,
	reason: string,
	entry: Entry?,
	snapshot: Entry?,
}

export type ValidationResult = {
	ok: boolean,
	reason: string?,
	entry: Entry?,
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
	return type(value) == "string" and string.len(value) > 0
end

local function isNonNegativeInteger(value: any): boolean
	return isFiniteNumber(value) and value >= 0 and value % 1 == 0
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value % 1 == 0
end

local function isValidTimestamp(value: any): boolean
	return isFiniteNumber(value) and value >= 0
end

local function cloneEntry(entry: Entry): Entry
	return {
		realmId = entry.realmId,
		currentTinyfolk = entry.currentTinyfolk,
		currentGiants = entry.currentGiants,
		reservedSlots = entry.reservedSlots,
		maxTinyfolk = entry.maxTinyfolk,
		maxGiants = entry.maxGiants,
		updatedAt = entry.updatedAt,
	}
end

local function validateCount(count: any): (number?, string?)
	if not isPositiveInteger(count) then
		return nil, "count_invalid"
	end
	return count, nil
end

local function transition(entry: Entry?, accepted: boolean, reason: string): EntryResult
	return {
		accepted = accepted,
		reason = reason,
		entry = if entry ~= nil then cloneEntry(entry) else nil,
		snapshot = if entry ~= nil then cloneEntry(entry) else nil,
	}
end

function ActiveRealmCapacityState.ValidateEntry(entry: any): ValidationResult
	if type(entry) ~= "table" then
		return { ok = false, reason = "entry_invalid", entry = nil }
	end
	if not isNonEmptyString(entry.realmId) then
		return { ok = false, reason = "realm_id_invalid", entry = nil }
	end
	if not isNonNegativeInteger(entry.currentTinyfolk) then
		return { ok = false, reason = "current_tinyfolk_invalid", entry = nil }
	end
	if not isNonNegativeInteger(entry.currentGiants) then
		return { ok = false, reason = "current_giants_invalid", entry = nil }
	end
	if not isNonNegativeInteger(entry.reservedSlots) then
		return { ok = false, reason = "reserved_slots_invalid", entry = nil }
	end
	if not isNonNegativeInteger(entry.maxTinyfolk) then
		return { ok = false, reason = "max_tinyfolk_invalid", entry = nil }
	end
	if not isNonNegativeInteger(entry.maxGiants) then
		return { ok = false, reason = "max_giants_invalid", entry = nil }
	end
	if not isValidTimestamp(entry.updatedAt) then
		return { ok = false, reason = "updated_at_invalid", entry = nil }
	end
	if entry.currentTinyfolk > entry.maxTinyfolk then
		return { ok = false, reason = "current_tinyfolk_exceeds_max", entry = nil }
	end
	if entry.currentGiants > entry.maxGiants then
		return { ok = false, reason = "current_giants_exceeds_max", entry = nil }
	end
	if entry.currentTinyfolk + entry.reservedSlots > entry.maxTinyfolk then
		return { ok = false, reason = "reserved_slots_exceed_capacity", entry = nil }
	end

	return {
		ok = true,
		reason = nil,
		entry = cloneEntry(entry :: Entry),
	}
end

function ActiveRealmCapacityState.NewEntry(input: any): EntryResult
	local validation = ActiveRealmCapacityState.ValidateEntry(input)
	if not validation.ok then
		return transition(nil, false, validation.reason or "entry_invalid")
	end
	return transition(validation.entry, true, "accepted")
end

function ActiveRealmCapacityState.GetSnapshot(entry: Entry): Entry?
	local validation = ActiveRealmCapacityState.ValidateEntry(entry)
	if not validation.ok then
		return nil
	end
	return validation.entry
end

function ActiveRealmCapacityState.Refresh(entry: Entry, now: number): EntryResult
	local validation = ActiveRealmCapacityState.ValidateEntry(entry)
	if not validation.ok then
		return transition(nil, false, validation.reason or "entry_invalid")
	end
	if not isValidTimestamp(now) then
		return transition(validation.entry, false, "updated_at_invalid")
	end

	local nextEntry = cloneEntry(validation.entry :: Entry)
	nextEntry.updatedAt = now
	return transition(nextEntry, true, "accepted")
end

function ActiveRealmCapacityState.ReserveTinyfolkSlots(entry: Entry, count: number, now: number): EntryResult
	local validation = ActiveRealmCapacityState.ValidateEntry(entry)
	if not validation.ok then
		return transition(nil, false, validation.reason or "entry_invalid")
	end
	local resolvedCount, countReason = validateCount(count)
	if resolvedCount == nil then
		return transition(validation.entry, false, countReason or "count_invalid")
	end
	if not isValidTimestamp(now) then
		return transition(validation.entry, false, "updated_at_invalid")
	end

	local nextEntry = cloneEntry(validation.entry :: Entry)
	if nextEntry.currentTinyfolk + nextEntry.reservedSlots + resolvedCount > nextEntry.maxTinyfolk then
		return transition(nextEntry, false, "tinyfolk_capacity_unavailable")
	end

	nextEntry.reservedSlots += resolvedCount
	nextEntry.updatedAt = now
	return transition(nextEntry, true, "accepted")
end

function ActiveRealmCapacityState.CommitTinyfolkArrival(entry: Entry, count: number, now: number): EntryResult
	local validation = ActiveRealmCapacityState.ValidateEntry(entry)
	if not validation.ok then
		return transition(nil, false, validation.reason or "entry_invalid")
	end
	local resolvedCount, countReason = validateCount(count)
	if resolvedCount == nil then
		return transition(validation.entry, false, countReason or "count_invalid")
	end
	if not isValidTimestamp(now) then
		return transition(validation.entry, false, "updated_at_invalid")
	end

	local nextEntry = cloneEntry(validation.entry :: Entry)
	if resolvedCount > nextEntry.reservedSlots then
		return transition(nextEntry, false, "reserved_slots_insufficient")
	end
	if nextEntry.currentTinyfolk + resolvedCount > nextEntry.maxTinyfolk then
		return transition(nextEntry, false, "current_tinyfolk_exceeds_max")
	end

	nextEntry.reservedSlots -= resolvedCount
	nextEntry.currentTinyfolk += resolvedCount
	nextEntry.updatedAt = now
	return transition(nextEntry, true, "accepted")
end

function ActiveRealmCapacityState.ReleaseReservedSlots(entry: Entry, count: number, now: number): EntryResult
	local validation = ActiveRealmCapacityState.ValidateEntry(entry)
	if not validation.ok then
		return transition(nil, false, validation.reason or "entry_invalid")
	end
	local resolvedCount, countReason = validateCount(count)
	if resolvedCount == nil then
		return transition(validation.entry, false, countReason or "count_invalid")
	end
	if not isValidTimestamp(now) then
		return transition(validation.entry, false, "updated_at_invalid")
	end

	local nextEntry = cloneEntry(validation.entry :: Entry)
	if resolvedCount > nextEntry.reservedSlots then
		return transition(nextEntry, false, "reserved_slots_insufficient")
	end

	nextEntry.reservedSlots -= resolvedCount
	nextEntry.updatedAt = now
	return transition(nextEntry, true, "accepted")
end

function ActiveRealmCapacityState.IsStale(entry: Entry, now: number, ttlSeconds: number): boolean
	local validation = ActiveRealmCapacityState.ValidateEntry(entry)
	if not validation.ok then
		return true
	end
	if not isValidTimestamp(now) or not isPositiveInteger(ttlSeconds) then
		return true
	end
	return now >= (validation.entry :: Entry).updatedAt + ttlSeconds
end

return ActiveRealmCapacityState
