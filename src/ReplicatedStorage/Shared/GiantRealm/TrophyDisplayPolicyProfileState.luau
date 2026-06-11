--!strict

local TrophyDisplayPolicyProfileState: any = {}

TrophyDisplayPolicyProfileState.PROFILE_KEY = "trophyDisplayPreference"
TrophyDisplayPolicyProfileState.OPT_OUT_KEY = "optOutOfNameDisplay"

export type PreferenceSnapshot = {
	optOutOfNameDisplay: boolean,
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
	preference: PreferenceSnapshot?,
}

local PROFILE_KEY = TrophyDisplayPolicyProfileState.PROFILE_KEY
local OPT_OUT_KEY = TrophyDisplayPolicyProfileState.OPT_OUT_KEY

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

local function normalizeOptOut(value: any): boolean?
	if type(value) ~= "boolean" then
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
		optOutOfNameDisplay = false,
	}

	if type(rawPreference) ~= "table" then
		return snapshot
	end

	local normalizedOptOut = normalizeOptOut(rawPreference[OPT_OUT_KEY])
	if normalizedOptOut == nil then
		return snapshot
	end

	snapshot.optOutOfNameDisplay = normalizedOptOut
	return snapshot
end

local function buildPersistedPreference(snapshot: PreferenceSnapshot): any?
	local normalizedOptOut = normalizeOptOut(snapshot.optOutOfNameDisplay)
	if normalizedOptOut == nil then
		return nil
	end

	return {
		[OPT_OUT_KEY] = normalizedOptOut,
	}
end

function TrophyDisplayPolicyProfileState.CreateDefaultPreference(): PreferenceSnapshot
	return {
		optOutOfNameDisplay = false,
	}
end

function TrophyDisplayPolicyProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local preference = profileData[PROFILE_KEY]
	if type(preference) ~= "table" then
		return false
	end

	return normalizeOptOut(preference[OPT_OUT_KEY]) ~= nil
end

function TrophyDisplayPolicyProfileState.GetPreference(profileData: any): PreferenceSnapshot
	if not TrophyDisplayPolicyProfileState.HasPersistedState(profileData) then
		return TrophyDisplayPolicyProfileState.CreateDefaultPreference()
	end

	return normalizePreferenceTable(profileData[PROFILE_KEY])
end

function TrophyDisplayPolicyProfileState.CopyProfileField(profileData: any): any?
	if type(profileData) ~= "table" then
		return nil
	end

	local snapshot = normalizePreferenceTable(profileData[PROFILE_KEY])
	if not TrophyDisplayPolicyProfileState.HasPersistedState(profileData) then
		return nil
	end

	return buildPersistedPreference(snapshot)
end

function TrophyDisplayPolicyProfileState.ApplyOptOut(profileData: any, optOutOfNameDisplay: any): PersistResult
	local normalizedOptOut = normalizeOptOut(optOutOfNameDisplay)
	if normalizedOptOut == nil then
		return {
			accepted = false,
			reason = "opt_out_invalid",
			profileData = ensureProfileState(profileData),
			preference = nil,
		}
	end

	local nextProfile = ensureProfileState(profileData)
	local persisted = buildPersistedPreference({
		optOutOfNameDisplay = normalizedOptOut,
	})
	if persisted == nil then
		return {
			accepted = false,
			reason = "trophy_display_preference_invalid",
			profileData = nextProfile,
			preference = nil,
		}
	end

	nextProfile[PROFILE_KEY] = persisted
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		preference = {
			optOutOfNameDisplay = normalizedOptOut,
		},
	}
end

return TrophyDisplayPolicyProfileState
