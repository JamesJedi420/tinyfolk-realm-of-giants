--!strict

local EscapeHistoryProfileState: any = {}

local PROFILE_KEY = "escapeHistory"
local DEFAULT_HISTORY_LIMIT = 25

export type EscapeHistoryEntry = {
	operationId: string,
	escapedAt: number,
	sourceKind: string,
	sourceId: string,
	routeId: string?,
	realmId: string?,
	realmOwnerUserId: number?,
	difficulty: number,
	reward: any,
	loot: any,
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

local function makeEmptyLoot(): any
	return {
		items = {},
		wood = 0,
		stone = 0,
		value = 0,
	}
end

local function normalizeLoot(value: any): any
	if type(value) ~= "table" then
		return makeEmptyLoot()
	end

	local items = {}
	if type(value.items) == "table" then
		for _, item in ipairs(value.items) do
			table.insert(items, cloneTable(item))
		end
	end

	return {
		items = items,
		wood = if isFiniteNumber(value.wood) and value.wood > 0 then value.wood else 0,
		stone = if isFiniteNumber(value.stone) and value.stone > 0 then value.stone else 0,
		value = if isFiniteNumber(value.value) and value.value > 0 then value.value else 0,
	}
end

local function normalizeDifficulty(value: any): number
	if isFiniteNumber(value) and value > 0 then
		return value
	end
	return 1
end

local function normalizeReward(value: any, difficulty: number, loot: any): any
	if type(value) ~= "table" then
		return {
			points = 0,
			basePoints = 0,
			difficulty = difficulty,
			lootValue = loot.value,
		}
	end

	return {
		points = if isFiniteNumber(value.points) and value.points >= 0 then value.points else 0,
		basePoints = if isFiniteNumber(value.basePoints) and value.basePoints >= 0 then value.basePoints else 0,
		difficulty = normalizeDifficulty(value.difficulty),
		lootValue = if isFiniteNumber(value.lootValue) and value.lootValue >= 0
			then value.lootValue
			else loot.value,
	}
end

local function normalizeOptionalString(value: any): string?
	if value == nil then
		return nil
	end
	return nonEmptyString(value)
end

local function normalizeOptionalRealmOwnerUserId(value: any): number?
	if value == nil then
		return nil
	end
	if isPositiveInteger(value) then
		return value
	end
	return nil
end

local function normalizeHistoryEntry(value: any): EscapeHistoryEntry?
	if type(value) ~= "table" then
		return nil
	end

	local operationId = nonEmptyString(value.operationId)
	local sourceKind = nonEmptyString(value.sourceKind)
	local sourceId = nonEmptyString(value.sourceId)
	local escapedAt = if isFiniteNumber(value.escapedAt) and value.escapedAt >= 0 then value.escapedAt else nil
	if operationId == nil or sourceKind == nil or sourceId == nil or escapedAt == nil then
		return nil
	end

	local loot = normalizeLoot(value.loot)
	local difficulty = normalizeDifficulty(value.difficulty)

	return {
		operationId = operationId,
		escapedAt = escapedAt,
		sourceKind = sourceKind,
		sourceId = sourceId,
		routeId = normalizeOptionalString(value.routeId),
		realmId = normalizeOptionalString(value.realmId),
		realmOwnerUserId = normalizeOptionalRealmOwnerUserId(value.realmOwnerUserId),
		difficulty = difficulty,
		reward = normalizeReward(value.reward, difficulty, loot),
		loot = loot,
	}
end

local function normalizeHistoryList(value: any, limit: number): { EscapeHistoryEntry }
	local normalized: { EscapeHistoryEntry } = {}
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

function EscapeHistoryProfileState.GetDefaultHistoryLimit(): number
	return DEFAULT_HISTORY_LIMIT
end

function EscapeHistoryProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local history = profileData[PROFILE_KEY]
	if type(history) ~= "table" then
		return false
	end

	return #normalizeHistoryList(history, DEFAULT_HISTORY_LIMIT) > 0
end

function EscapeHistoryProfileState.GetHistory(profileData: any, limit: number?): { EscapeHistoryEntry }
	local historyLimit = if type(limit) == "number" and limit > 0 then math.floor(limit) else DEFAULT_HISTORY_LIMIT
	if not EscapeHistoryProfileState.HasPersistedState(profileData) then
		return {}
	end

	return normalizeHistoryList(profileData[PROFILE_KEY], historyLimit)
end

function EscapeHistoryProfileState.CopyProfileField(profileData: any, limit: number?): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local history = normalizeHistoryList(profileData[PROFILE_KEY], if type(limit) == "number" then limit else DEFAULT_HISTORY_LIMIT)
	if #history == 0 then
		return nil
	end

	local copied = {}
	for _, entry in ipairs(history) do
		table.insert(copied, cloneTable(entry))
	end
	return copied
end

function EscapeHistoryProfileState.AppendEntry(profileData: any, entry: any, limit: number?): PersistResult
	local historyLimit = if type(limit) == "number" and limit > 0 then math.floor(limit) else DEFAULT_HISTORY_LIMIT
	local normalizedEntry = normalizeHistoryEntry(entry)
	if normalizedEntry == nil then
		return {
			accepted = false,
			reason = "escape_history_entry_invalid",
			profileData = ensureProfileState(profileData),
		}
	end

	local nextProfile = ensureProfileState(profileData)
	local history = normalizeHistoryList(nextProfile[PROFILE_KEY], historyLimit)

	local filtered: { EscapeHistoryEntry } = {}
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

return EscapeHistoryProfileState
