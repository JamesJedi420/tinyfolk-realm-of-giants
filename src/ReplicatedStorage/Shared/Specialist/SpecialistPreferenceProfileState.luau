--!strict

local SpecialistConfig = require("../Config/SpecialistConfig")
local StationConfig = require("../Config/StationConfig")
local ShrineConfig = require("../Config/ShrineConfig")

local SpecialistPreferenceProfileState: any = {}

local PROFILE_KEY = "specialistPreference"
local SPECIALIST_ROLE_KEY = "specialistRole"
local ASSIGNED_STATION_ID_KEY = "assignedStationId"
local LAST_ASSIGNED_AT_KEY = "lastAssignedAt"

export type PreferenceSnapshot = {
	specialistRole: string?,
	assignedStationId: string?,
	lastAssignedAt: number?,
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

local validPersistedSpecialistRoleSet: { [string]: boolean } = {
	[SpecialistConfig.SpecialistRoles.None] = true,
	[SpecialistConfig.SpecialistRoles.Woodcutter] = true,
	[SpecialistConfig.SpecialistRoles.Miner] = true,
	[SpecialistConfig.SpecialistRoles.Farmer] = true,
	[SpecialistConfig.SpecialistRoles.Worshipper] = true,
}

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

local function startsWithPrefix(name: string, prefix: string): boolean
	return string.match(name, "^" .. prefix) ~= nil
end

local function normalizeSpecialistRole(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	if validPersistedSpecialistRoleSet[value] ~= true then
		return nil
	end
	return value
end

local function normalizeLastAssignedAt(value: any): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return nil
	end
	return value
end

local function validateAssignedStationForRole(specialistRole: string, assignedStationId: string?): (boolean, string)
	if specialistRole == SpecialistConfig.SpecialistRoles.Worshipper then
		if type(assignedStationId) ~= "string" then
			return false, "assigned_station_required_for_worshipper"
		end

		if not startsWithPrefix(assignedStationId, ShrineConfig.ShrineNamePrefix) then
			return false, "assigned_station_mismatch_for_worshipper"
		end

		return true, ""
	end

	if
		specialistRole == SpecialistConfig.SpecialistRoles.Woodcutter
		or specialistRole == SpecialistConfig.SpecialistRoles.Miner
		or specialistRole == SpecialistConfig.SpecialistRoles.Farmer
	then
		if type(assignedStationId) ~= "string" then
			return false, "assigned_station_required_for_material_specialist"
		end

		local requiredRole = StationConfig.RequiredSpecialistRoleByStationId[assignedStationId]
		if type(requiredRole) ~= "string" then
			return false, "assigned_station_not_specialist_mapped"
		end

		if requiredRole ~= specialistRole then
			return false, "assigned_station_role_mismatch"
		end

		return true, ""
	end

	if specialistRole == SpecialistConfig.SpecialistRoles.None then
		return true, ""
	end

	return false, "unsupported_specialist_role"
end

local function normalizeAssignedStationId(specialistRole: string, value: any): string?
	if specialistRole == SpecialistConfig.SpecialistRoles.None then
		return nil
	end

	if value == nil then
		return nil
	end

	if type(value) ~= "string" then
		return nil
	end

	local stationValid = validateAssignedStationForRole(specialistRole, value)
	if stationValid then
		return value
	end

	return nil
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end
	return nextProfile
end

local function normalizePreferenceTable(rawPreference: any): PreferenceSnapshot
	local snapshot: PreferenceSnapshot = {
		specialistRole = nil,
		assignedStationId = nil,
		lastAssignedAt = nil,
	}

	if type(rawPreference) ~= "table" then
		return snapshot
	end

	local specialistRole = normalizeSpecialistRole(rawPreference[SPECIALIST_ROLE_KEY])
	if specialistRole == nil then
		return snapshot
	end

	snapshot.specialistRole = specialistRole
	snapshot.assignedStationId = normalizeAssignedStationId(specialistRole, rawPreference[ASSIGNED_STATION_ID_KEY])
	snapshot.lastAssignedAt = normalizeLastAssignedAt(rawPreference[LAST_ASSIGNED_AT_KEY])

	return snapshot
end

local function buildPersistedPreference(snapshot: PreferenceSnapshot): any?
	if snapshot.specialistRole == nil then
		return nil
	end

	local persisted: any = {
		[SPECIALIST_ROLE_KEY] = snapshot.specialistRole,
	}

	if snapshot.assignedStationId ~= nil then
		persisted[ASSIGNED_STATION_ID_KEY] = snapshot.assignedStationId
	end

	if snapshot.lastAssignedAt ~= nil then
		persisted[LAST_ASSIGNED_AT_KEY] = snapshot.lastAssignedAt
	end

	return persisted
end

function SpecialistPreferenceProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local preference = profileData[PROFILE_KEY]
	if type(preference) ~= "table" then
		return false
	end

	return normalizeSpecialistRole(preference[SPECIALIST_ROLE_KEY]) ~= nil
end

function SpecialistPreferenceProfileState.GetPreference(profileData: any): PreferenceSnapshot
	if not SpecialistPreferenceProfileState.HasPersistedState(profileData) then
		return {
			specialistRole = nil,
			assignedStationId = nil,
			lastAssignedAt = nil,
		}
	end

	return normalizePreferenceTable(profileData[PROFILE_KEY])
end

function SpecialistPreferenceProfileState.CopyProfileField(profileData: any): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local snapshot = normalizePreferenceTable(profileData[PROFILE_KEY])
	return buildPersistedPreference(snapshot)
end

function SpecialistPreferenceProfileState.ApplySpecialistRole(profileData: any, specialistRole: any): PersistResult
	local normalizedRole = normalizeSpecialistRole(specialistRole)
	if normalizedRole == nil then
		return {
			accepted = false,
			reason = "invalid_specialist_role",
			profileData = ensureProfileState(profileData),
		}
	end

	local nextProfile = ensureProfileState(profileData)
	local snapshot = normalizePreferenceTable(nextProfile[PROFILE_KEY])
	snapshot.specialistRole = normalizedRole

	if normalizedRole == SpecialistConfig.SpecialistRoles.None then
		snapshot.assignedStationId = nil
	else
		snapshot.assignedStationId = normalizeAssignedStationId(normalizedRole, snapshot.assignedStationId)
	end

	local persisted = buildPersistedPreference(snapshot)
	if persisted == nil then
		return {
			accepted = false,
			reason = "invalid_specialist_role",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY] = persisted
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

function SpecialistPreferenceProfileState.ApplyAssignedStationId(profileData: any, assignedStationId: any): PersistResult
	local nextProfile = ensureProfileState(profileData)
	local snapshot = normalizePreferenceTable(nextProfile[PROFILE_KEY])
	if snapshot.specialistRole == SpecialistConfig.SpecialistRoles.None then
		if assignedStationId == nil then
			snapshot.assignedStationId = nil
			local persisted = buildPersistedPreference(snapshot)
			if persisted == nil then
				return {
					accepted = false,
					reason = "invalid_specialist_role",
					profileData = nextProfile,
				}
			end

			nextProfile[PROFILE_KEY] = persisted
			return {
				accepted = true,
				reason = "accepted",
				profileData = nextProfile,
			}
		end

		return {
			accepted = false,
			reason = "specialist_role_not_assigned",
			profileData = nextProfile,
		}
	end

	if snapshot.specialistRole == nil then
		return {
			accepted = false,
			reason = "specialist_role_not_assigned",
			profileData = nextProfile,
		}
	end

	if assignedStationId ~= nil and type(assignedStationId) ~= "string" then
		return {
			accepted = false,
			reason = "invalid_assigned_station_id",
			profileData = nextProfile,
		}
	end

	local normalizedStationId = normalizeAssignedStationId(snapshot.specialistRole, assignedStationId)
	if assignedStationId ~= nil and normalizedStationId == nil then
		return {
			accepted = false,
			reason = "assigned_station_invalid_for_role",
			profileData = nextProfile,
		}
	end

	snapshot.assignedStationId = normalizedStationId
	local persisted = buildPersistedPreference(snapshot)
	if persisted == nil then
		return {
			accepted = false,
			reason = "invalid_specialist_role",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY] = persisted
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

function SpecialistPreferenceProfileState.ApplyLastAssignedAt(profileData: any, lastAssignedAt: any): PersistResult
	local normalizedTimestamp = normalizeLastAssignedAt(lastAssignedAt)
	if normalizedTimestamp == nil then
		return {
			accepted = false,
			reason = "invalid_last_assigned_at",
			profileData = ensureProfileState(profileData),
		}
	end

	local nextProfile = ensureProfileState(profileData)
	local snapshot = normalizePreferenceTable(nextProfile[PROFILE_KEY])
	if snapshot.specialistRole == nil then
		snapshot.specialistRole = SpecialistConfig.SpecialistRoles.None
	end

	snapshot.lastAssignedAt = normalizedTimestamp
	local persisted = buildPersistedPreference(snapshot)
	if persisted == nil then
		return {
			accepted = false,
			reason = "invalid_specialist_role",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY] = persisted
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

return SpecialistPreferenceProfileState
