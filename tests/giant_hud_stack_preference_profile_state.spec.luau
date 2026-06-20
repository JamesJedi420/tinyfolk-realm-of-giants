--!strict

local GiantHudStackPreferenceProfileState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/GiantHudStackPreferenceProfileState")

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
	local defaultPreference = GiantHudStackPreferenceProfileState.CreateDefaultPreference()
	assertFalse(defaultPreference.expandedBySectionId.Treasury, "default treasury collapsed")
	assertFalse(defaultPreference.expandedBySectionId.PenRationing, "default pen collapsed")
	assertFalse(defaultPreference.expandedBySectionId.SocialEconomy, "default social collapsed")
	assertFalse(defaultPreference.expandedBySectionId.GiantEffects, "default effects collapsed")
end

do
	assertFalse(GiantHudStackPreferenceProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(GiantHudStackPreferenceProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		GiantHudStackPreferenceProfileState.HasPersistedState({
			giantHudStackPreference = {},
		}),
		"missing expanded map not persisted"
	)
	assertFalse(
		GiantHudStackPreferenceProfileState.HasPersistedState({
			giantHudStackPreference = {
				expandedBySectionId = {
					UnknownSection = true,
				},
			},
		}),
		"unknown section not persisted"
	)
end

do
	local profileData = {
		giantHudStackPreference = {
			expandedBySectionId = {
				Treasury = true,
				SocialEconomy = true,
			},
		},
	}
	assertTrue(GiantHudStackPreferenceProfileState.HasPersistedState(profileData), "valid sections persisted")
	local preference = GiantHudStackPreferenceProfileState.GetPreference(profileData)
	assertTrue(preference.expandedBySectionId.Treasury, "treasury expanded preserved")
	assertTrue(preference.expandedBySectionId.SocialEconomy, "social expanded preserved")
	assertFalse(preference.expandedBySectionId.PenRationing, "missing pen defaults collapsed")
end

do
	local preference = GiantHudStackPreferenceProfileState.GetPreference({
		giantHudStackPreference = {
			expandedBySectionId = {
				Treasury = "yes",
			},
		},
	})
	assertFalse(preference.expandedBySectionId.Treasury, "invalid expanded defaults collapsed")
end

do
	local profileData = {
		giantHudStackPreference = {
			expandedBySectionId = {
				Treasury = true,
				extraField = true,
			},
		},
	}
	local copied = GiantHudStackPreferenceProfileState.CopyProfileField(profileData)
	assertTrue(copied.expandedBySectionId.Treasury, "copy keeps valid treasury")
	assertEqual(copied.expandedBySectionId.extraField, nil, "copy omits unknown sections")
	assertFalse(copied.expandedBySectionId.PenRationing, "copy includes default collapsed sections")
end

do
	local applyTreasury = GiantHudStackPreferenceProfileState.ApplySectionExpanded({}, "Treasury", true)
	assertTrue(applyTreasury.accepted, "apply treasury expanded accepted")
	assertTrue(applyTreasury.preference.expandedBySectionId.Treasury, "apply treasury returns preference")
	assertTrue(
		applyTreasury.profileData.giantHudStackPreference.expandedBySectionId.Treasury,
		"apply treasury writes profile key"
	)

	local applySocial = GiantHudStackPreferenceProfileState.ApplySectionExpanded(
		applyTreasury.profileData,
		"SocialEconomy",
		true
	)
	assertTrue(applySocial.accepted, "apply social accepted")
	assertTrue(applySocial.preference.expandedBySectionId.SocialEconomy, "apply social merges preference")
	assertTrue(applySocial.preference.expandedBySectionId.Treasury, "apply social preserves treasury")
end

do
	local rejectedSection = GiantHudStackPreferenceProfileState.ApplySectionExpanded({}, "NotASection", true)
	assertFalse(rejectedSection.accepted, "unknown section rejected")
	assertEqual(rejectedSection.reason, "section_id_invalid", "unknown section reason")

	local rejectedExpanded = GiantHudStackPreferenceProfileState.ApplySectionExpanded({}, "Treasury", "yes")
	assertFalse(rejectedExpanded.accepted, "invalid expanded rejected")
	assertEqual(rejectedExpanded.reason, "expanded_invalid", "invalid expanded reason")
end

print("giant_hud_stack_preference_profile_state: all checks passed")
