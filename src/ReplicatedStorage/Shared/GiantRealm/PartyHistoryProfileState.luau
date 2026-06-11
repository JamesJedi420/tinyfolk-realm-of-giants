--!strict

local PartyHistoryProfileState: any = {}

PartyHistoryProfileState.PROFILE_KEY = "partyHistory"

local PROFILE_KEY = PartyHistoryProfileState.PROFILE_KEY
local DEFAULT_HISTORY_LIMIT = 25

local VALID_ENTRY_TYPES: { [string]: boolean } = {
	standard = true,
	rescue_contract = true,
	direct_invite = true,
}

export type PartyHistoryEntry = {
	operationId: string,
	partyId: string,
	targetRealmId: string,
	entryType: string,
	formedAt: number,
	partySize: number,
	partyMemberUserIds: { number },
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
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
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local cloneTable: (value: any) -> any
cloneTable = function(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local cloned = {}
	for key, child in pairs(value) do
		cloned[key] = cloneTable(child)
	end
	return cloned
end

local function normalizePartyMemberUserIds(values: any, partySize: number): { number }?
	if type(values) ~= "table" then
		return nil
	end

	local seen: { [number]: boolean } = {}
	local normalized: { number } = {}
	for _, value in ipairs(values) do
		if not isPositiveInteger(value) then
			return nil
		end
		local userId = value :: number
		if seen[userId] ~= true then
			seen[userId] = true
			table.insert(normalized, userId)
		end
	end

	table.sort(normalized)

	if #normalized <= 0 or #normalized ~= partySize then
		return nil
	end

	return normalized
end

local function normalizeEntryType(value: any): string?
	local entryType = nonEmptyString(value)
	if entryType == nil or VALID_ENTRY_TYPES[entryType] ~= true then
		return nil
	end
	return entryType
end

local function normalizeHistoryEntry(value: any): PartyHistoryEntry?
	if type(value) ~= "table" then
		return nil
	end

	local operationId = nonEmptyString(value.operationId)
	local partyId = nonEmptyString(value.partyId)
	local targetRealmId = nonEmptyString(value.targetRealmId)
	local entryType = normalizeEntryType(value.entryType)
	local formedAt = if isFiniteNumber(value.formedAt) and value.formedAt >= 0 then value.formedAt else nil
	local partySize = if isPositiveInteger(value.partySize) then value.partySize else nil
	if
		operationId == nil
		or partyId == nil
		or targetRealmId == nil
		or entryType == nil
		or formedAt == nil
		or partySize == nil
	then
		return nil
	end

	local partyMemberUserIds = normalizePartyMemberUserIds(value.partyMemberUserIds, partySize)
	if partyMemberUserIds == nil then
		return nil
	end

	return {
		operationId = operationId,
		partyId = partyId,
		targetRealmId = targetRealmId,
		entryType = entryType,
		formedAt = formedAt,
		partySize = partySize,
		partyMemberUserIds = partyMemberUserIds,
	}
end

local function normalizeHistoryList(value: any, limit: number): { PartyHistoryEntry }
	local normalized: { PartyHistoryEntry } = {}
	if type(value) ~= "table" then
		return normalized
	end

	local seenOperationIds: { [string]: boolean } = {}
	for _, rawEntry in ipairs(value) do
		local entry = normalizeHistoryEntry(rawEntry)
		if entry ~= nil and seenOperationIds[entry.operationId] ~= true then
			seenOperationIds[entry.operationId] = true
			table.insert(normalized, entry)
		end
	end

	while #normalized > limit do
		table.remove(normalized, 1)
	end

	return normalized
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end
	return nextProfile
end

function PartyHistoryProfileState.GetDefaultHistoryLimit(): number
	return DEFAULT_HISTORY_LIMIT
end

function PartyHistoryProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local history = profileData[PROFILE_KEY]
	if type(history) ~= "table" then
		return false
	end

	return #normalizeHistoryList(history, DEFAULT_HISTORY_LIMIT) > 0
end

function PartyHistoryProfileState.GetHistory(profileData: any, limit: number?): { PartyHistoryEntry }
	local historyLimit = if type(limit) == "number" and limit > 0 then math.floor(limit) else DEFAULT_HISTORY_LIMIT
	if not PartyHistoryProfileState.HasPersistedState(profileData) then
		return {}
	end

	return normalizeHistoryList(profileData[PROFILE_KEY], historyLimit)
end

function PartyHistoryProfileState.CopyProfileField(profileData: any, limit: number?): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local history =
		normalizeHistoryList(profileData[PROFILE_KEY], if type(limit) == "number" then limit else DEFAULT_HISTORY_LIMIT)
	if #history == 0 then
		return nil
	end

	local copied = {}
	for _, entry in ipairs(history) do
		table.insert(copied, cloneTable(entry))
	end
	return copied
end

function PartyHistoryProfileState.AppendEntry(profileData: any, entry: any, limit: number?): PersistResult
	local historyLimit = if type(limit) == "number" and limit > 0 then math.floor(limit) else DEFAULT_HISTORY_LIMIT
	local normalizedEntry = normalizeHistoryEntry(entry)
	if normalizedEntry == nil then
		return {
			accepted = false,
			reason = "party_history_entry_invalid",
			profileData = ensureProfileState(profileData),
		}
	end

	local nextProfile = ensureProfileState(profileData)
	local history = normalizeHistoryList(nextProfile[PROFILE_KEY], historyLimit)

	local filtered: { PartyHistoryEntry } = {}
	for _, existing in ipairs(history) do
		if existing.operationId ~= normalizedEntry.operationId then
			table.insert(filtered, existing)
		end
	end
	table.insert(filtered, normalizedEntry)

	while #filtered > historyLimit do
		table.remove(filtered, 1)
	end

	nextProfile[PROFILE_KEY] = filtered
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

return PartyHistoryProfileState
