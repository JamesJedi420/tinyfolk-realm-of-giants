--!strict

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferState"))
	else (require :: any)("./RealmTransferState")

local LiveRealmRegistryState: any = {}

LiveRealmRegistryState.DEFAULT_CAPACITY = 8
LiveRealmRegistryState.DEFAULT_DANGER_RATING = 0.5
LiveRealmRegistryState.ENCODE_VERSION = "v1"

LiveRealmRegistryState.Lifecycle = {
	NoLiveServer = "no_live_server",
	Starting = "starting",
	Active = "active",
	Expired = "expired",
}

LiveRealmRegistryState.AccessMode = {
	Public = "public",
	Private = "private",
	InviteOnly = "invite_only",
	RaidEnabled = "raid_enabled",
	FriendsOnly = "friends_only",
}

export type Entry = {
	realmId: string,
	ownerUserId: number,
	privateServerId: string,
	jobId: string,
	accessMode: string,
	playerCount: number,
	capacity: number,
	dangerRating: number,
	updatedAt: number,
	lifecycle: string,
}

export type AvailabilitySnapshot = {
	realmId: string,
	ownerUserId: number,
	privateServerId: string,
	accessMode: string,
	playerCount: number,
	capacity: number,
	dangerRating: number,
	lifecycle: string,
	isAvailable: boolean,
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

local VALID_LIFECYCLE: { [string]: boolean } = {
	[LiveRealmRegistryState.Lifecycle.NoLiveServer] = true,
	[LiveRealmRegistryState.Lifecycle.Starting] = true,
	[LiveRealmRegistryState.Lifecycle.Active] = true,
	[LiveRealmRegistryState.Lifecycle.Expired] = true,
}

local VALID_ACCESS_MODE: { [string]: boolean } = {
	[LiveRealmRegistryState.AccessMode.Public] = true,
	[LiveRealmRegistryState.AccessMode.Private] = true,
	[LiveRealmRegistryState.AccessMode.InviteOnly] = true,
	[LiveRealmRegistryState.AccessMode.RaidEnabled] = true,
	[LiveRealmRegistryState.AccessMode.FriendsOnly] = true,
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

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value % 1 == 0
end

local function isNonNegativeInteger(value: any): boolean
	return isFiniteNumber(value) and value >= 0 and value % 1 == 0
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and string.len(value) > 0
end

local function isSafeEncodedSegment(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	if string.len(value) > 96 then
		return false
	end
	return string.match(value, "^[%w_%.%-]*$") ~= nil
end

local function isValidTimestamp(value: any): boolean
	return isFiniteNumber(value) and value >= 0
end

local function isValidDangerRating(value: any): boolean
	return isFiniteNumber(value) and value >= 0 and value <= 1
end

local function cloneEntry(entry: Entry): Entry
	return {
		realmId = entry.realmId,
		ownerUserId = entry.ownerUserId,
		privateServerId = entry.privateServerId,
		jobId = entry.jobId,
		accessMode = entry.accessMode,
		playerCount = entry.playerCount,
		capacity = entry.capacity,
		dangerRating = entry.dangerRating,
		updatedAt = entry.updatedAt,
		lifecycle = entry.lifecycle,
	}
end

local function transition(entry: Entry?, accepted: boolean, reason: string): EntryResult
	return {
		accepted = accepted,
		reason = reason,
		entry = if entry ~= nil then cloneEntry(entry) else nil,
		snapshot = if entry ~= nil then cloneEntry(entry) else nil,
	}
end

local function realmIdMatchesOwner(realmId: string, ownerUserId: number): boolean
	return realmId == RealmTransferState.FormatRealmId(ownerUserId)
end

function LiveRealmRegistryState.FormatRealmId(ownerUserId: number): string
	return RealmTransferState.FormatRealmId(ownerUserId)
end

function LiveRealmRegistryState.ResolveStablePrivateServerId(ownerUserId: number, runtimePrivateServerId: any): string
	if isSafeEncodedSegment(runtimePrivateServerId) and runtimePrivateServerId ~= "" then
		return runtimePrivateServerId
	end
	return string.format("giant_realm_ps_%d", ownerUserId)
end

function LiveRealmRegistryState.ResolveAccessMode(runtimePrivateServerId: any): string
	if isSafeEncodedSegment(runtimePrivateServerId) and runtimePrivateServerId ~= "" then
		return LiveRealmRegistryState.AccessMode.Private
	end
	return LiveRealmRegistryState.AccessMode.Public
end

function LiveRealmRegistryState.ValidateEntry(entry: any): ValidationResult
	if type(entry) ~= "table" then
		return { ok = false, reason = "entry_invalid", entry = nil }
	end
	if not isNonEmptyString(entry.realmId) then
		return { ok = false, reason = "realm_id_invalid", entry = nil }
	end
	if not isPositiveInteger(entry.ownerUserId) then
		return { ok = false, reason = "owner_user_id_invalid", entry = nil }
	end
	if not realmIdMatchesOwner(entry.realmId, entry.ownerUserId) then
		return { ok = false, reason = "realm_owner_mismatch", entry = nil }
	end
	if type(entry.privateServerId) ~= "string" or not isSafeEncodedSegment(entry.privateServerId) then
		return { ok = false, reason = "private_server_id_invalid", entry = nil }
	end
	if not isSafeEncodedSegment(entry.jobId) then
		return { ok = false, reason = "job_id_invalid", entry = nil }
	end
	if type(entry.accessMode) ~= "string" or VALID_ACCESS_MODE[entry.accessMode] ~= true then
		return { ok = false, reason = "access_mode_invalid", entry = nil }
	end
	if not isNonNegativeInteger(entry.playerCount) then
		return { ok = false, reason = "player_count_invalid", entry = nil }
	end
	if not isPositiveInteger(entry.capacity) then
		return { ok = false, reason = "capacity_invalid", entry = nil }
	end
	if entry.playerCount > entry.capacity then
		return { ok = false, reason = "player_count_exceeds_capacity", entry = nil }
	end
	if not isValidDangerRating(entry.dangerRating) then
		return { ok = false, reason = "danger_rating_invalid", entry = nil }
	end
	if not isValidTimestamp(entry.updatedAt) then
		return { ok = false, reason = "updated_at_invalid", entry = nil }
	end
	if type(entry.lifecycle) ~= "string" or VALID_LIFECYCLE[entry.lifecycle] ~= true then
		return { ok = false, reason = "lifecycle_invalid", entry = nil }
	end

	return {
		ok = true,
		reason = nil,
		entry = cloneEntry(entry :: Entry),
	}
end

function LiveRealmRegistryState.NewEntry(input: any): EntryResult
	local validation = LiveRealmRegistryState.ValidateEntry(input)
	if not validation.ok then
		return transition(nil, false, validation.reason or "entry_invalid")
	end
	return transition(validation.entry, true, "accepted")
end

function LiveRealmRegistryState.GetSnapshot(entry: Entry): Entry?
	local validation = LiveRealmRegistryState.ValidateEntry(entry)
	if not validation.ok then
		return nil
	end
	return validation.entry
end

function LiveRealmRegistryState.RefreshEntry(entry: Entry, patch: any, now: number): EntryResult
	local validation = LiveRealmRegistryState.ValidateEntry(entry)
	if not validation.ok then
		return transition(nil, false, validation.reason or "entry_invalid")
	end
	if not isValidTimestamp(now) then
		return transition(validation.entry, false, "updated_at_invalid")
	end
	if type(patch) ~= "table" then
		return transition(validation.entry, false, "patch_invalid")
	end

	local nextEntry = cloneEntry(validation.entry :: Entry)
	if patch.privateServerId ~= nil then
		nextEntry.privateServerId = patch.privateServerId
	end
	if patch.jobId ~= nil then
		nextEntry.jobId = patch.jobId
	end
	if patch.accessMode ~= nil then
		nextEntry.accessMode = patch.accessMode
	end
	if patch.playerCount ~= nil then
		nextEntry.playerCount = patch.playerCount
	end
	if patch.capacity ~= nil then
		nextEntry.capacity = patch.capacity
	end
	if patch.dangerRating ~= nil then
		nextEntry.dangerRating = patch.dangerRating
	end
	if patch.lifecycle ~= nil then
		nextEntry.lifecycle = patch.lifecycle
	end
	nextEntry.updatedAt = now

	local refreshed = LiveRealmRegistryState.ValidateEntry(nextEntry)
	if not refreshed.ok then
		return transition(validation.entry, false, refreshed.reason or "entry_invalid")
	end
	return transition(refreshed.entry, true, "accepted")
end

function LiveRealmRegistryState.MarkLifecycle(entry: Entry, lifecycle: string, now: number): EntryResult
	return LiveRealmRegistryState.RefreshEntry(entry, { lifecycle = lifecycle }, now)
end

function LiveRealmRegistryState.ResolveSortKey(entry: Entry): number?
	local validation = LiveRealmRegistryState.ValidateEntry(entry)
	if not validation.ok or validation.entry == nil then
		return nil
	end
	return math.floor((validation.entry :: Entry).updatedAt)
end

function LiveRealmRegistryState.IsStale(entry: Entry, now: number, ttlSeconds: number): boolean
	local validation = LiveRealmRegistryState.ValidateEntry(entry)
	if not validation.ok then
		return true
	end
	if not isValidTimestamp(now) or not isPositiveInteger(ttlSeconds) then
		return true
	end
	return now >= (validation.entry :: Entry).updatedAt + ttlSeconds
end

function LiveRealmRegistryState.IsAvailable(entry: Entry, now: number, ttlSeconds: number): boolean
	local validation = LiveRealmRegistryState.ValidateEntry(entry)
	if not validation.ok or validation.entry == nil then
		return false
	end
	local validatedEntry = validation.entry :: Entry
	if validatedEntry.lifecycle ~= LiveRealmRegistryState.Lifecycle.Active then
		return false
	end
	if LiveRealmRegistryState.IsStale(validatedEntry, now, ttlSeconds) then
		return false
	end
	return true
end

function LiveRealmRegistryState.BuildAvailabilitySnapshot(
	entry: Entry,
	now: number,
	ttlSeconds: number
): AvailabilitySnapshot?
	local validation = LiveRealmRegistryState.ValidateEntry(entry)
	if not validation.ok or validation.entry == nil then
		return nil
	end
	local validatedEntry = validation.entry :: Entry
	return {
		realmId = validatedEntry.realmId,
		ownerUserId = validatedEntry.ownerUserId,
		privateServerId = validatedEntry.privateServerId,
		accessMode = validatedEntry.accessMode,
		playerCount = validatedEntry.playerCount,
		capacity = validatedEntry.capacity,
		dangerRating = validatedEntry.dangerRating,
		lifecycle = validatedEntry.lifecycle,
		isAvailable = LiveRealmRegistryState.IsAvailable(validatedEntry, now, ttlSeconds),
		updatedAt = validatedEntry.updatedAt,
	}
end

function LiveRealmRegistryState.BuildPublishInput(input: any): (any?, string?)
	if type(input) ~= "table" then
		return nil, "input_invalid"
	end
	if not isPositiveInteger(input.ownerUserId) then
		return nil, "owner_user_id_invalid"
	end
	if not isValidTimestamp(input.now) then
		return nil, "updated_at_invalid"
	end

	local ownerUserId = math.floor(input.ownerUserId)
	local realmId = RealmTransferState.FormatRealmId(ownerUserId)
	local privateServerId = LiveRealmRegistryState.ResolveStablePrivateServerId(ownerUserId, input.privateServerId)
	local accessMode = if type(input.accessMode) == "string"
		then input.accessMode
		else LiveRealmRegistryState.ResolveAccessMode(input.privateServerId)
	local jobId = if isSafeEncodedSegment(input.jobId) then input.jobId else ""
	local playerCount = if isNonNegativeInteger(input.playerCount) then input.playerCount else 0
	local capacity = if isPositiveInteger(input.capacity)
		then input.capacity
		else LiveRealmRegistryState.DEFAULT_CAPACITY
	local dangerRating = if isValidDangerRating(input.dangerRating)
		then input.dangerRating
		else LiveRealmRegistryState.DEFAULT_DANGER_RATING
	local lifecycle = if type(input.lifecycle) == "string"
		then input.lifecycle
		else LiveRealmRegistryState.Lifecycle.Starting

	return {
		realmId = realmId,
		ownerUserId = ownerUserId,
		privateServerId = privateServerId,
		jobId = jobId,
		accessMode = accessMode,
		playerCount = playerCount,
		capacity = capacity,
		dangerRating = dangerRating,
		updatedAt = input.now,
		lifecycle = lifecycle,
	},
		nil
end

function LiveRealmRegistryState.EncodeRegistryEntry(entry: Entry): (string?, string?)
	local validation = LiveRealmRegistryState.ValidateEntry(entry)
	if not validation.ok or validation.entry == nil then
		return nil, validation.reason or "entry_invalid"
	end
	local validatedEntry = validation.entry :: Entry
	local encoded = table.concat({
		LiveRealmRegistryState.ENCODE_VERSION,
		validatedEntry.realmId,
		tostring(validatedEntry.ownerUserId),
		validatedEntry.privateServerId,
		validatedEntry.jobId,
		validatedEntry.accessMode,
		tostring(validatedEntry.playerCount),
		tostring(validatedEntry.capacity),
		tostring(validatedEntry.dangerRating),
		tostring(validatedEntry.updatedAt),
		validatedEntry.lifecycle,
	}, "|")
	return encoded, nil
end

function LiveRealmRegistryState.DecodeRegistryEntry(encoded: any): (Entry?, string?)
	if type(encoded) ~= "string" or encoded == "" then
		return nil, "stored_payload_invalid"
	end

	local parts = string.split(encoded, "|")
	if #parts ~= 11 then
		return nil, "stored_payload_invalid"
	end
	if parts[1] ~= LiveRealmRegistryState.ENCODE_VERSION then
		return nil, "stored_payload_version_invalid"
	end

	local ownerUserId = tonumber(parts[3])
	local playerCount = tonumber(parts[7])
	local capacity = tonumber(parts[8])
	local dangerRating = tonumber(parts[9])
	local updatedAt = tonumber(parts[10])
	if ownerUserId == nil or playerCount == nil or capacity == nil or dangerRating == nil or updatedAt == nil then
		return nil, "stored_payload_invalid"
	end

	local validation = LiveRealmRegistryState.ValidateEntry({
		realmId = parts[2],
		ownerUserId = ownerUserId,
		privateServerId = parts[4],
		jobId = parts[5],
		accessMode = parts[6],
		playerCount = playerCount,
		capacity = capacity,
		dangerRating = dangerRating,
		updatedAt = updatedAt,
		lifecycle = parts[11],
	})
	if not validation.ok then
		return nil, validation.reason or "stored_entry_invalid"
	end
	return validation.entry, nil
end

return LiveRealmRegistryState
