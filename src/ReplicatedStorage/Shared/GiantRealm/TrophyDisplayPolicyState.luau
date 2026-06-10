--!strict

local TrophyDisplayPolicyState = {}

TrophyDisplayPolicyState.PROFILE_KEY = "trophyDisplayPreference"
TrophyDisplayPolicyState.OPT_OUT_KEY = "optOutOfNameDisplay"

export type Preference = {
	optOutOfNameDisplay: boolean,
}

local function clonePreference(preference: Preference): Preference
	return {
		optOutOfNameDisplay = preference.optOutOfNameDisplay,
	}
end

function TrophyDisplayPolicyState.CreateDefaultPreference(): Preference
	return {
		optOutOfNameDisplay = false,
	}
end

function TrophyDisplayPolicyState.ReadFromProfile(profileData: any): Preference
	local defaultPreference = TrophyDisplayPolicyState.CreateDefaultPreference()
	if type(profileData) ~= "table" then
		return defaultPreference
	end

	local rawPreference = profileData[TrophyDisplayPolicyState.PROFILE_KEY]
	if type(rawPreference) ~= "table" then
		return defaultPreference
	end

	if rawPreference[TrophyDisplayPolicyState.OPT_OUT_KEY] == true then
		return {
			optOutOfNameDisplay = true,
		}
	end

	return defaultPreference
end

function TrophyDisplayPolicyState.ValidatePreference(preference: any): (boolean, string?)
	if type(preference) ~= "table" then
		return false, "trophy_display_preference_invalid"
	end

	local optOut = preference[TrophyDisplayPolicyState.OPT_OUT_KEY]
	if optOut ~= nil and type(optOut) ~= "boolean" then
		return false, "trophy_display_opt_out_invalid"
	end

	return true, nil
end

function TrophyDisplayPolicyState.ApplyUpdate(profileData: any, optOutOfNameDisplay: boolean): any
	if type(profileData) ~= "table" then
		return {
			accepted = false,
			reason = "profile_data_invalid",
			profileData = profileData,
			preference = nil,
		}
	end

	if type(optOutOfNameDisplay) ~= "boolean" then
		return {
			accepted = false,
			reason = "opt_out_invalid",
			profileData = profileData,
			preference = nil,
		}
	end

	local nextProfileData = table.clone(profileData)
	local nextPreference = {
		[TrophyDisplayPolicyState.OPT_OUT_KEY] = optOutOfNameDisplay,
	}
	nextProfileData[TrophyDisplayPolicyState.PROFILE_KEY] = nextPreference

	local valid, reason = TrophyDisplayPolicyState.ValidatePreference(nextPreference)
	if not valid then
		return {
			accepted = false,
			reason = reason or "trophy_display_preference_invalid",
			profileData = profileData,
			preference = nil,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfileData,
		preference = clonePreference({
			optOutOfNameDisplay = optOutOfNameDisplay,
		}),
	}
end

return TrophyDisplayPolicyState
