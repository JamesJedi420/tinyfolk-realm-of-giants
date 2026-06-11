--!strict

local PendingRecoveryProfileState: any = {}

PendingRecoveryProfileState.PROFILE_KEY = "pendingRecovery"

PendingRecoveryProfileState.Status = {
	AwaitingDestination = "awaiting_destination",
}

local PROFILE_KEY = PendingRecoveryProfileState.PROFILE_KEY
local HANDOFF_TOKEN_KEY = "handoffToken"
local TARGET_REALM_ID_KEY = "targetRealmId"
local STARTED_AT_KEY = "startedAt"
local STATUS_KEY = "status"

export type RecoverySnapshot = {
	handoffToken: string,
	targetRealmId: string,
	startedAt: number,
	status: string,
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

local validStatusSet: { [string]: boolean } = {
	[PendingRecoveryProfileState.Status.AwaitingDestination] = true,
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

local function normalizeStatus(value: any): string?
	local normalized = nonEmptyString(value)
	if normalized == nil then
		return nil
	end
	if validStatusSet[normalized] ~= true then
		return nil
	end
	return normalized
end

local function normalizeStartedAt(value: any): number?
	if not isFiniteNumber(value) or value < 0 then
		return nil
	end
	return value
end

local function normalizeSnapshot(value: any): RecoverySnapshot?
	if type(value) ~= "table" then
		return nil
	end

	local handoffToken = nonEmptyString(value[HANDOFF_TOKEN_KEY])
	local targetRealmId = nonEmptyString(value[TARGET_REALM_ID_KEY])
	local startedAt = normalizeStartedAt(value[STARTED_AT_KEY])
	local status = normalizeStatus(value[STATUS_KEY])
	if handoffToken == nil or targetRealmId == nil or startedAt == nil or status == nil then
		return nil
	end

	return {
		handoffToken = handoffToken,
		targetRealmId = targetRealmId,
		startedAt = startedAt,
		status = status,
	}
end

local function buildPersistedSnapshot(snapshot: RecoverySnapshot): any
	local persisted: any = {}
	persisted[HANDOFF_TOKEN_KEY] = snapshot.handoffToken
	persisted[TARGET_REALM_ID_KEY] = snapshot.targetRealmId
	persisted[STARTED_AT_KEY] = snapshot.startedAt
	persisted[STATUS_KEY] = snapshot.status
	return persisted
end

local function ensureProfileState(profileData: any): any
	return if type(profileData) == "table" then cloneTable(profileData) else {}
end

function PendingRecoveryProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local pendingRecovery = profileData[PROFILE_KEY]
	if type(pendingRecovery) ~= "table" then
		return false
	end

	return normalizeSnapshot(pendingRecovery) ~= nil
end

function PendingRecoveryProfileState.GetRecovery(profileData: any): RecoverySnapshot?
	if not PendingRecoveryProfileState.HasPersistedState(profileData) then
		return nil
	end

	return normalizeSnapshot(profileData[PROFILE_KEY])
end

function PendingRecoveryProfileState.CopyProfileField(profileData: any): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local snapshot = normalizeSnapshot(profileData[PROFILE_KEY])
	if snapshot == nil then
		return nil
	end

	return buildPersistedSnapshot(snapshot)
end

function PendingRecoveryProfileState.ApplyPendingHandoff(profileData: any, input: any): PersistResult
	local nextProfile = ensureProfileState(profileData)
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "pending_recovery_input_invalid",
			profileData = nextProfile,
		}
	end

	local handoffToken = nonEmptyString(input.handoffToken)
	local targetRealmId = nonEmptyString(input.targetRealmId)
	local startedAt = normalizeStartedAt(input.startedAt)
	local status = normalizeStatus(input.status) or PendingRecoveryProfileState.Status.AwaitingDestination
	if handoffToken == nil or targetRealmId == nil or startedAt == nil then
		return {
			accepted = false,
			reason = "pending_recovery_input_invalid",
			profileData = nextProfile,
		}
	end

	local snapshot: RecoverySnapshot = {
		handoffToken = handoffToken,
		targetRealmId = targetRealmId,
		startedAt = startedAt,
		status = status,
	}

	nextProfile[PROFILE_KEY] = buildPersistedSnapshot(snapshot)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

function PendingRecoveryProfileState.ClearRecovery(profileData: any): PersistResult
	local nextProfile = ensureProfileState(profileData)
	nextProfile[PROFILE_KEY] = nil
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

return PendingRecoveryProfileState
