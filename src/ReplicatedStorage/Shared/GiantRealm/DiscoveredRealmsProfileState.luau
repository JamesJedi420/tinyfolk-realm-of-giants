--!strict

local DiscoveredRealmsProfileState: any = {}

DiscoveredRealmsProfileState.PROFILE_KEY = "discoveredRealms"

local PROFILE_KEY = DiscoveredRealmsProfileState.PROFILE_KEY
local REALM_ID_KEY = "realmId"
local FIRST_DISCOVERED_AT_KEY = "firstDiscoveredAt"
local DEFAULT_DISCOVERY_LIMIT = 50

export type DiscoveredRealmEntry = {
	realmId: string,
	firstDiscoveredAt: number,
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
	recorded: boolean?,
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

local function normalizeFirstDiscoveredAt(value: any): number?
	if not isFiniteNumber(value) or value < 0 then
		return nil
	end
	return value
end

local function normalizeEntry(value: any): DiscoveredRealmEntry?
	if type(value) ~= "table" then
		return nil
	end

	local realmId = nonEmptyString(value[REALM_ID_KEY])
	local firstDiscoveredAt = normalizeFirstDiscoveredAt(value[FIRST_DISCOVERED_AT_KEY])
	if realmId == nil or firstDiscoveredAt == nil then
		return nil
	end

	return {
		realmId = realmId,
		firstDiscoveredAt = firstDiscoveredAt,
	}
end

local function normalizeDiscoveryList(value: any, limit: number): { DiscoveredRealmEntry }
	local normalized: { DiscoveredRealmEntry } = {}
	if type(value) ~= "table" then
		return normalized
	end

	local seenRealmIds: { [string]: boolean } = {}
	for _, rawEntry in ipairs(value) do
		local entry = normalizeEntry(rawEntry)
		if entry ~= nil and seenRealmIds[entry.realmId] ~= true then
			seenRealmIds[entry.realmId] = true
			table.insert(normalized, entry)
		end
	end

	table.sort(normalized, function(left: DiscoveredRealmEntry, right: DiscoveredRealmEntry): boolean
		if left.firstDiscoveredAt ~= right.firstDiscoveredAt then
			return left.firstDiscoveredAt < right.firstDiscoveredAt
		end
		return left.realmId < right.realmId
	end)

	while #normalized > limit do
		table.remove(normalized, 1)
	end

	return normalized
end

local function buildPersistedEntry(entry: DiscoveredRealmEntry): any
	local persisted: any = {}
	persisted[REALM_ID_KEY] = entry.realmId
	persisted[FIRST_DISCOVERED_AT_KEY] = entry.firstDiscoveredAt
	return persisted
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end
	return nextProfile
end

function DiscoveredRealmsProfileState.GetDefaultDiscoveryLimit(): number
	return DEFAULT_DISCOVERY_LIMIT
end

function DiscoveredRealmsProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local discoveries = profileData[PROFILE_KEY]
	if type(discoveries) ~= "table" then
		return false
	end

	return #normalizeDiscoveryList(discoveries, DEFAULT_DISCOVERY_LIMIT) > 0
end

function DiscoveredRealmsProfileState.GetDiscoveries(profileData: any, limit: number?): { DiscoveredRealmEntry }
	local discoveryLimit = if type(limit) == "number" and limit > 0 then math.floor(limit) else DEFAULT_DISCOVERY_LIMIT
	if not DiscoveredRealmsProfileState.HasPersistedState(profileData) then
		return {}
	end

	return normalizeDiscoveryList(profileData[PROFILE_KEY], discoveryLimit)
end

function DiscoveredRealmsProfileState.IsDiscovered(profileData: any, realmId: any): boolean
	local normalizedRealmId = nonEmptyString(realmId)
	if normalizedRealmId == nil then
		return false
	end

	for _, entry in ipairs(DiscoveredRealmsProfileState.GetDiscoveries(profileData)) do
		if entry.realmId == normalizedRealmId then
			return true
		end
	end

	return false
end

function DiscoveredRealmsProfileState.CopyProfileField(profileData: any, limit: number?): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local discoveries = normalizeDiscoveryList(
		profileData[PROFILE_KEY],
		if type(limit) == "number" then limit else DEFAULT_DISCOVERY_LIMIT
	)
	if #discoveries == 0 then
		return nil
	end

	local copied = {}
	for _, entry in ipairs(discoveries) do
		table.insert(copied, buildPersistedEntry(entry))
	end
	return copied
end

function DiscoveredRealmsProfileState.RecordDiscovery(profileData: any, input: any, limit: number?): PersistResult
	local discoveryLimit = if type(limit) == "number" and limit > 0 then math.floor(limit) else DEFAULT_DISCOVERY_LIMIT
	local nextProfile = ensureProfileState(profileData)
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "discovered_realms_input_invalid",
			profileData = nextProfile,
			recorded = false,
		}
	end

	local realmId = nonEmptyString(input.realmId)
	local firstDiscoveredAt = normalizeFirstDiscoveredAt(input.firstDiscoveredAt)
	if realmId == nil or firstDiscoveredAt == nil then
		return {
			accepted = false,
			reason = "discovered_realms_input_invalid",
			profileData = nextProfile,
			recorded = false,
		}
	end

	local discoveries = normalizeDiscoveryList(nextProfile[PROFILE_KEY], discoveryLimit)
	for _, existing in ipairs(discoveries) do
		if existing.realmId == realmId then
			nextProfile[PROFILE_KEY] = discoveries
			return {
				accepted = true,
				reason = "already_discovered",
				profileData = nextProfile,
				recorded = false,
			}
		end
	end

	table.insert(discoveries, {
		realmId = realmId,
		firstDiscoveredAt = firstDiscoveredAt,
	})
	discoveries = normalizeDiscoveryList(discoveries, discoveryLimit)
	nextProfile[PROFILE_KEY] = discoveries

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		recorded = true,
	}
end

return DiscoveredRealmsProfileState
