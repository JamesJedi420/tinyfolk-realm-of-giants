--!strict

local EscapeConfig = require("../Config/EscapeConfig")

local SafeLocationProfileState: any = {}

local PROFILE_KEY = "safeLocation"
local RETURN_POINT_NAME_KEY = "returnPointName"
local RETURNED_AT_KEY = "returnedAt"
local RETURN_REASON_KEY = "returnReason"
local REALM_ID_KEY = "realmId"
local REALM_OWNER_USER_ID_KEY = "realmOwnerUserId"
local SOURCE_ID_KEY = "sourceId"

export type SafeLocationSnapshot = {
	returnPointName: string,
	returnedAt: number,
	returnReason: string,
	realmId: string?,
	realmOwnerUserId: number?,
	sourceId: string?,
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

local validReturnReasonSet: { [string]: boolean } = {
	escape_success = true,
	safe_return = true,
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

local function normalizeReturnPointName(value: any): string?
	local normalized = nonEmptyString(value)
	if normalized == nil then
		return nil
	end
	if normalized ~= EscapeConfig.TinyfolkReturnPointName then
		return nil
	end
	return normalized
end

local function normalizeReturnedAt(value: any): number?
	if not isFiniteNumber(value) or value < 0 then
		return nil
	end
	return value
end

local function normalizeReturnReason(value: any): string?
	local normalized = nonEmptyString(value)
	if normalized == nil then
		return nil
	end
	if validReturnReasonSet[normalized] ~= true then
		return nil
	end
	return normalized
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

local function normalizeSnapshot(value: any): SafeLocationSnapshot?
	if type(value) ~= "table" then
		return nil
	end

	local returnPointName = normalizeReturnPointName(value[RETURN_POINT_NAME_KEY])
	local returnedAt = normalizeReturnedAt(value[RETURNED_AT_KEY])
	local returnReason = normalizeReturnReason(value[RETURN_REASON_KEY])
	if returnPointName == nil or returnedAt == nil or returnReason == nil then
		return nil
	end

	return {
		returnPointName = returnPointName,
		returnedAt = returnedAt,
		returnReason = returnReason,
		realmId = normalizeOptionalString(value[REALM_ID_KEY]),
		realmOwnerUserId = normalizeOptionalRealmOwnerUserId(value[REALM_OWNER_USER_ID_KEY]),
		sourceId = normalizeOptionalString(value[SOURCE_ID_KEY]),
	}
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end
	return nextProfile
end

local function buildPersistedSnapshot(snapshot: SafeLocationSnapshot): any
	local persisted: any = {}
	persisted[RETURN_POINT_NAME_KEY] = snapshot.returnPointName
	persisted[RETURNED_AT_KEY] = snapshot.returnedAt
	persisted[RETURN_REASON_KEY] = snapshot.returnReason

	if snapshot.realmId ~= nil then
		persisted[REALM_ID_KEY] = snapshot.realmId
	end
	if snapshot.realmOwnerUserId ~= nil then
		persisted[REALM_OWNER_USER_ID_KEY] = snapshot.realmOwnerUserId
	end
	if snapshot.sourceId ~= nil then
		persisted[SOURCE_ID_KEY] = snapshot.sourceId
	end

	return persisted
end

function SafeLocationProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local safeLocation = profileData[PROFILE_KEY]
	if type(safeLocation) ~= "table" then
		return false
	end

	return normalizeSnapshot(safeLocation) ~= nil
end

function SafeLocationProfileState.GetLocation(profileData: any): SafeLocationSnapshot?
	if not SafeLocationProfileState.HasPersistedState(profileData) then
		return nil
	end

	return normalizeSnapshot(profileData[PROFILE_KEY])
end

function SafeLocationProfileState.CopyProfileField(profileData: any): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local snapshot = normalizeSnapshot(profileData[PROFILE_KEY])
	if snapshot == nil then
		return nil
	end

	return buildPersistedSnapshot(snapshot)
end

function SafeLocationProfileState.ApplySafeReturn(profileData: any, input: any): PersistResult
	local nextProfile = ensureProfileState(profileData)
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "safe_location_input_invalid",
			profileData = nextProfile,
		}
	end

	local returnPointName = normalizeReturnPointName(input.returnPointName) or EscapeConfig.TinyfolkReturnPointName
	local returnedAt = normalizeReturnedAt(input.returnedAt)
	local returnReason = normalizeReturnReason(input.returnReason)
	if returnedAt == nil or returnReason == nil then
		return {
			accepted = false,
			reason = "safe_location_input_invalid",
			profileData = nextProfile,
		}
	end

	local snapshot: SafeLocationSnapshot = {
		returnPointName = returnPointName,
		returnedAt = returnedAt,
		returnReason = returnReason,
		realmId = normalizeOptionalString(input.realmId),
		realmOwnerUserId = normalizeOptionalRealmOwnerUserId(input.realmOwnerUserId),
		sourceId = normalizeOptionalString(input.sourceId),
	}

	nextProfile[PROFILE_KEY] = buildPersistedSnapshot(snapshot)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

return SafeLocationProfileState
