--!strict

local RoleConfig = require("../Config/RoleConfig")

local RolePreferenceProfileState: any = {}

local PROFILE_KEY = "rolePreference"
local PREFERRED_ROLE_KEY = "preferredRole"

export type PreferenceSnapshot = {
	preferredRole: string?,
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

local validPersistedRoleSet: { [string]: boolean } = {
	[RoleConfig.Roles.Giant] = true,
	[RoleConfig.Roles.Tinyfolk] = true,
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

local function normalizePreferredRole(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	if validPersistedRoleSet[value] ~= true then
		return nil
	end
	return value
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
		preferredRole = nil,
	}

	if type(rawPreference) ~= "table" then
		return snapshot
	end

	snapshot.preferredRole = normalizePreferredRole(rawPreference[PREFERRED_ROLE_KEY])
	return snapshot
end

local function buildPersistedPreference(snapshot: PreferenceSnapshot): any?
	if snapshot.preferredRole == nil then
		return nil
	end

	return {
		[PREFERRED_ROLE_KEY] = snapshot.preferredRole,
	}
end

function RolePreferenceProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local preference = profileData[PROFILE_KEY]
	if type(preference) ~= "table" then
		return false
	end

	return normalizePreferredRole(preference[PREFERRED_ROLE_KEY]) ~= nil
end

function RolePreferenceProfileState.GetPreference(profileData: any): PreferenceSnapshot
	if not RolePreferenceProfileState.HasPersistedState(profileData) then
		return {
			preferredRole = nil,
		}
	end

	return normalizePreferenceTable(profileData[PROFILE_KEY])
end

function RolePreferenceProfileState.CopyProfileField(profileData: any): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local snapshot = normalizePreferenceTable(profileData[PROFILE_KEY])
	return buildPersistedPreference(snapshot)
end

function RolePreferenceProfileState.ApplyPreferredRole(profileData: any, preferredRole: any): PersistResult
	local normalizedRole = normalizePreferredRole(preferredRole)
	if normalizedRole == nil then
		return {
			accepted = false,
			reason = "invalid_preferred_role",
			profileData = ensureProfileState(profileData),
		}
	end

	local nextProfile = ensureProfileState(profileData)
	local persisted = buildPersistedPreference({
		preferredRole = normalizedRole,
	})
	if persisted == nil then
		return {
			accepted = false,
			reason = "invalid_preferred_role",
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

return RolePreferenceProfileState
