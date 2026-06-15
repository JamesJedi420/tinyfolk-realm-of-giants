--!strict

local RealmAssignmentProfileState: any = {}

RealmAssignmentProfileState.PROFILE_KEY = "realmAssignment"

RealmAssignmentProfileState.LocationCategory = {
	SharedHub = "shared_hub",
	GiantRealm = "giant_realm",
	TransferInFlight = "transfer_in_flight",
}

RealmAssignmentProfileState.AssignmentReason = {
	Capture = "capture",
	Rescue = "rescue",
	EscapeReturn = "escape_return",
	Trade = "trade",
	PartyAdmission = "party_admission",
}

local PROFILE_KEY = RealmAssignmentProfileState.PROFILE_KEY
local LOCATION_CATEGORY_KEY = "locationCategory"
local REALM_ID_KEY = "realmId"
local REALM_OWNER_USER_ID_KEY = "realmOwnerUserId"
local ASSIGNMENT_REASON_KEY = "assignmentReason"
local UPDATED_AT_KEY = "updatedAt"

export type AssignmentSnapshot = {
	locationCategory: string,
	realmId: string?,
	realmOwnerUserId: number?,
	assignmentReason: string?,
	updatedAt: number,
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

local validLocationCategorySet: { [string]: boolean } = {
	[RealmAssignmentProfileState.LocationCategory.SharedHub] = true,
	[RealmAssignmentProfileState.LocationCategory.GiantRealm] = true,
	[RealmAssignmentProfileState.LocationCategory.TransferInFlight] = true,
}

local validAssignmentReasonSet: { [string]: boolean } = {
	[RealmAssignmentProfileState.AssignmentReason.Capture] = true,
	[RealmAssignmentProfileState.AssignmentReason.Rescue] = true,
	[RealmAssignmentProfileState.AssignmentReason.EscapeReturn] = true,
	[RealmAssignmentProfileState.AssignmentReason.Trade] = true,
	[RealmAssignmentProfileState.AssignmentReason.PartyAdmission] = true,
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

local function normalizeUpdatedAt(value: any): number?
	if not isFiniteNumber(value) or value < 0 then
		return nil
	end
	return value
end

local function normalizeLocationCategory(value: any): string?
	local normalized = nonEmptyString(value)
	if normalized == nil then
		return nil
	end
	if validLocationCategorySet[normalized] ~= true then
		return nil
	end
	return normalized
end

local function normalizeAssignmentReason(value: any): string?
	if value == nil then
		return nil
	end
	local normalized = nonEmptyString(value)
	if normalized == nil then
		return nil
	end
	if validAssignmentReasonSet[normalized] ~= true then
		return nil
	end
	return normalized
end

local function normalizeRealmOwnerUserId(value: any): number?
	if value == nil then
		return nil
	end
	if isPositiveInteger(value) then
		return value
	end
	return nil
end

local function normalizeRealmId(value: any): string?
	if value == nil then
		return nil
	end
	return nonEmptyString(value)
end

local function realmIdMatchesOwner(realmId: string, realmOwnerUserId: number): boolean
	return realmId == string.format("giant_realm_%d", realmOwnerUserId)
end

local function normalizeSnapshot(value: any): AssignmentSnapshot?
	if type(value) ~= "table" then
		return nil
	end

	local locationCategory = normalizeLocationCategory(value[LOCATION_CATEGORY_KEY])
	local updatedAt = normalizeUpdatedAt(value[UPDATED_AT_KEY])
	if locationCategory == nil or updatedAt == nil then
		return nil
	end

	local realmId = normalizeRealmId(value[REALM_ID_KEY])
	local realmOwnerUserId = normalizeRealmOwnerUserId(value[REALM_OWNER_USER_ID_KEY])
	local assignmentReason = normalizeAssignmentReason(value[ASSIGNMENT_REASON_KEY])

	if locationCategory == RealmAssignmentProfileState.LocationCategory.SharedHub then
		if realmId ~= nil or realmOwnerUserId ~= nil or assignmentReason ~= nil then
			return nil
		end
		return {
			locationCategory = locationCategory,
			realmId = nil,
			realmOwnerUserId = nil,
			assignmentReason = nil,
			updatedAt = updatedAt,
		}
	end

	if locationCategory == RealmAssignmentProfileState.LocationCategory.GiantRealm then
		if realmId == nil or realmOwnerUserId == nil or assignmentReason ~= nil then
			return nil
		end
		if not realmIdMatchesOwner(realmId, realmOwnerUserId) then
			return nil
		end
		return {
			locationCategory = locationCategory,
			realmId = realmId,
			realmOwnerUserId = realmOwnerUserId,
			assignmentReason = nil,
			updatedAt = updatedAt,
		}
	end

	if realmId == nil or realmOwnerUserId == nil or assignmentReason == nil then
		return nil
	end
	if not realmIdMatchesOwner(realmId, realmOwnerUserId) then
		return nil
	end

	return {
		locationCategory = locationCategory,
		realmId = realmId,
		realmOwnerUserId = realmOwnerUserId,
		assignmentReason = assignmentReason,
		updatedAt = updatedAt,
	}
end

local function buildPersistedSnapshot(snapshot: AssignmentSnapshot): any
	local persisted: any = {}
	persisted[LOCATION_CATEGORY_KEY] = snapshot.locationCategory
	persisted[UPDATED_AT_KEY] = snapshot.updatedAt

	if snapshot.realmId ~= nil then
		persisted[REALM_ID_KEY] = snapshot.realmId
	end
	if snapshot.realmOwnerUserId ~= nil then
		persisted[REALM_OWNER_USER_ID_KEY] = snapshot.realmOwnerUserId
	end
	if snapshot.assignmentReason ~= nil then
		persisted[ASSIGNMENT_REASON_KEY] = snapshot.assignmentReason
	end

	return persisted
end

local function ensureProfileState(profileData: any): any
	return if type(profileData) == "table" then cloneTable(profileData) else {}
end

function RealmAssignmentProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local realmAssignment = profileData[PROFILE_KEY]
	if type(realmAssignment) ~= "table" then
		return false
	end

	return normalizeSnapshot(realmAssignment) ~= nil
end

function RealmAssignmentProfileState.GetAssignment(profileData: any): AssignmentSnapshot?
	if not RealmAssignmentProfileState.HasPersistedState(profileData) then
		return nil
	end

	return normalizeSnapshot(profileData[PROFILE_KEY])
end

function RealmAssignmentProfileState.CopyProfileField(profileData: any): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local snapshot = normalizeSnapshot(profileData[PROFILE_KEY])
	if snapshot == nil then
		return nil
	end

	return buildPersistedSnapshot(snapshot)
end

function RealmAssignmentProfileState.ApplyAssignment(profileData: any, snapshot: any): PersistResult
	local nextProfile = ensureProfileState(profileData)
	local normalized = normalizeSnapshot(snapshot)
	if normalized == nil then
		return {
			accepted = false,
			reason = "realm_assignment_snapshot_invalid",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY] = buildPersistedSnapshot(normalized)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

function RealmAssignmentProfileState.ClearAssignment(profileData: any): PersistResult
	local nextProfile = ensureProfileState(profileData)
	nextProfile[PROFILE_KEY] = nil
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

return RealmAssignmentProfileState
