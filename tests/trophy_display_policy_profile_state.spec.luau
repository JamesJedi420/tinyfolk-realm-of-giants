--!strict

local TrophyDisplayPolicyProfileState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/TrophyDisplayPolicyProfileState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

do
	local defaultPreference = TrophyDisplayPolicyProfileState.CreateDefaultPreference()
	assertFalse(defaultPreference.optOutOfNameDisplay, "default preference allows visitor reference")
end

do
	assertFalse(TrophyDisplayPolicyProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(TrophyDisplayPolicyProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		TrophyDisplayPolicyProfileState.HasPersistedState({
			trophyDisplayPreference = {},
		}),
		"missing opt-out not persisted"
	)
	assertFalse(
		TrophyDisplayPolicyProfileState.HasPersistedState({
			trophyDisplayPreference = {
				optOutOfNameDisplay = "yes",
			},
		}),
		"invalid opt-out type not persisted"
	)
end

do
	local profileData = {
		trophyDisplayPreference = {
			optOutOfNameDisplay = true,
		},
	}
	assertTrue(TrophyDisplayPolicyProfileState.HasPersistedState(profileData), "opt-out true persisted")
	local preference = TrophyDisplayPolicyProfileState.GetPreference(profileData)
	assertTrue(preference.optOutOfNameDisplay, "opt-out true preserved")
end

do
	local profileData = {
		trophyDisplayPreference = {
			optOutOfNameDisplay = false,
		},
	}
	assertTrue(TrophyDisplayPolicyProfileState.HasPersistedState(profileData), "opt-out false persisted")
	local preference = TrophyDisplayPolicyProfileState.GetPreference(profileData)
	assertFalse(preference.optOutOfNameDisplay, "opt-out false preserved")
end

do
	local preference = TrophyDisplayPolicyProfileState.GetPreference({
		trophyDisplayPreference = {
			optOutOfNameDisplay = "yes",
		},
	})
	assertFalse(preference.optOutOfNameDisplay, "invalid opt-out defaults to allow reference")
end

do
	local profileData = {
		trophyDisplayPreference = {
			optOutOfNameDisplay = true,
			extraField = "ignored",
		},
	}
	local copied = TrophyDisplayPolicyProfileState.CopyProfileField(profileData)
	assertTrue(copied.optOutOfNameDisplay, "copy keeps valid opt-out")
	assertEqual(copied.extraField, nil, "copy omits extra fields")
end

do
	local copied = TrophyDisplayPolicyProfileState.CopyProfileField({
		trophyDisplayPreference = {
			optOutOfNameDisplay = "yes",
		},
	})
	assertEqual(copied, nil, "copy drops invalid opt-out preference")
end

do
	local applyOptOut = TrophyDisplayPolicyProfileState.ApplyOptOut({}, true)
	assertTrue(applyOptOut.accepted, "apply opt-out accepted")
	assertTrue(applyOptOut.preference.optOutOfNameDisplay, "apply opt-out returns preference")
	assertTrue(applyOptOut.profileData.trophyDisplayPreference.optOutOfNameDisplay, "apply opt-out writes profile key")

	local revert = TrophyDisplayPolicyProfileState.ApplyOptOut(applyOptOut.profileData, false)
	assertTrue(revert.accepted, "revert opt-out accepted")
	assertFalse(revert.preference.optOutOfNameDisplay, "revert opt-out clears preference")
end

do
	local rejected = TrophyDisplayPolicyProfileState.ApplyOptOut({}, "yes")
	assertFalse(rejected.accepted, "invalid opt-out rejected")
	assertEqual(rejected.reason, "opt_out_invalid", "invalid opt-out reason")
end

print("trophy_display_policy_profile_state: all checks passed")
