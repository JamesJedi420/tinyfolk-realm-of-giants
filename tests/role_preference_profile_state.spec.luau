--!strict

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local RolePreferenceProfileState = require("../src/ReplicatedStorage/Shared/Role/RolePreferenceProfileState")

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
	assertFalse(RolePreferenceProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(RolePreferenceProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		RolePreferenceProfileState.HasPersistedState({
			rolePreference = {},
		}),
		"missing preferred role not persisted"
	)
end

do
	local profileData = {
		rolePreference = {
			preferredRole = RoleConfig.Roles.Giant,
		},
	}
	assertTrue(RolePreferenceProfileState.HasPersistedState(profileData), "valid preference persisted")
	local preference = RolePreferenceProfileState.GetPreference(profileData)
	assertEqual(preference.preferredRole, RoleConfig.Roles.Giant, "giant role preserved")
end

do
	local profileData = {
		rolePreference = {
			preferredRole = "NotARealRole",
		},
	}
	assertFalse(RolePreferenceProfileState.HasPersistedState(profileData), "invalid role not persisted")
	local preference = RolePreferenceProfileState.GetPreference(profileData)
	assertEqual(preference.preferredRole, nil, "invalid role filtered")
end

do
	local profileData = {
		rolePreference = {
			preferredRole = RoleConfig.Roles.Tinyfolk,
			extraField = "ignored",
		},
	}
	local copied = RolePreferenceProfileState.CopyProfileField(profileData)
	assertEqual(copied.preferredRole, RoleConfig.Roles.Tinyfolk, "copy keeps valid role")
	assertEqual(copied.extraField, nil, "copy omits extra fields")
end

do
	local applyRole = RolePreferenceProfileState.ApplyPreferredRole({}, RoleConfig.Roles.Tinyfolk)
	assertTrue(applyRole.accepted, "apply role accepted")
	assertEqual(
		applyRole.profileData.rolePreference.preferredRole,
		RoleConfig.Roles.Tinyfolk,
		"apply role writes preferred role"
	)

	local applyGiant = RolePreferenceProfileState.ApplyPreferredRole(applyRole.profileData, RoleConfig.Roles.Giant)
	assertTrue(applyGiant.accepted, "apply giant accepted")
	assertEqual(
		applyGiant.profileData.rolePreference.preferredRole,
		RoleConfig.Roles.Giant,
		"apply giant overwrites preferred role"
	)
end

do
	local rejectedRole = RolePreferenceProfileState.ApplyPreferredRole({}, "NotARealRole")
	assertFalse(rejectedRole.accepted, "invalid role rejected")
	assertEqual(rejectedRole.reason, "invalid_preferred_role", "invalid role reason")
end

print("role_preference_profile_state: all checks passed")
