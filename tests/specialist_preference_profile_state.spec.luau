--!strict

local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local SpecialistPreferenceProfileState =
	require("../src/ReplicatedStorage/Shared/Specialist/SpecialistPreferenceProfileState")

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
	assertFalse(SpecialistPreferenceProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(SpecialistPreferenceProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		SpecialistPreferenceProfileState.HasPersistedState({
			specialistPreference = {
				assignedStationId = "MiningStation_A",
			},
		}),
		"missing specialist role not persisted"
	)
end

do
	local profileData = {
		specialistPreference = {
			specialistRole = SpecialistConfig.SpecialistRoles.Miner,
			assignedStationId = "MiningStation_A",
			lastAssignedAt = 1234567890,
		},
	}
	assertTrue(SpecialistPreferenceProfileState.HasPersistedState(profileData), "valid preference persisted")
	local preference = SpecialistPreferenceProfileState.GetPreference(profileData)
	assertEqual(preference.specialistRole, SpecialistConfig.SpecialistRoles.Miner, "miner role preserved")
	assertEqual(preference.assignedStationId, "MiningStation_A", "station preserved")
	assertEqual(preference.lastAssignedAt, 1234567890, "timestamp preserved")
end

do
	local profileData = {
		specialistPreference = {
			specialistRole = "InvalidSpecialistRole",
			assignedStationId = "MiningStation_A",
			lastAssignedAt = 1234567890,
		},
	}
	assertFalse(SpecialistPreferenceProfileState.HasPersistedState(profileData), "invalid role not persisted")
	local preference = SpecialistPreferenceProfileState.GetPreference(profileData)
	assertEqual(preference.specialistRole, nil, "invalid role filtered")
end

do
	local profileData = {
		specialistPreference = {
			specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
			assignedStationId = "Shrine_A",
			lastAssignedAt = "not-a-number",
		},
	}
	local copied = SpecialistPreferenceProfileState.CopyProfileField(profileData)
	assertEqual(copied.specialistRole, SpecialistConfig.SpecialistRoles.Woodcutter, "copy keeps valid role")
	assertEqual(copied.assignedStationId, nil, "copy drops mismatched station")
	assertEqual(copied.lastAssignedAt, nil, "copy drops invalid timestamp")
end

do
	local applyRole = SpecialistPreferenceProfileState.ApplySpecialistRole({}, SpecialistConfig.SpecialistRoles.Farmer)
	assertTrue(applyRole.accepted, "apply role accepted")
	assertEqual(
		applyRole.profileData.specialistPreference.specialistRole,
		SpecialistConfig.SpecialistRoles.Farmer,
		"apply role writes specialist role"
	)

	local applyStation = SpecialistPreferenceProfileState.ApplyAssignedStationId(applyRole.profileData, "Farm_A")
	assertTrue(applyStation.accepted, "apply station accepted")
	assertEqual(applyStation.profileData.specialistPreference.assignedStationId, "Farm_A", "apply station writes id")

	local applyTimestamp = SpecialistPreferenceProfileState.ApplyLastAssignedAt(applyStation.profileData, 42)
	assertTrue(applyTimestamp.accepted, "apply timestamp accepted")
	assertEqual(applyTimestamp.profileData.specialistPreference.lastAssignedAt, 42, "apply timestamp writes value")

	local clearRole = SpecialistPreferenceProfileState.ApplySpecialistRole(
		applyTimestamp.profileData,
		SpecialistConfig.SpecialistRoles.None
	)
	assertTrue(clearRole.accepted, "clear role accepted")
	assertEqual(
		clearRole.profileData.specialistPreference.specialistRole,
		SpecialistConfig.SpecialistRoles.None,
		"clear role writes none"
	)
	assertEqual(clearRole.profileData.specialistPreference.assignedStationId, nil, "clear role drops station")

	local clearStation = SpecialistPreferenceProfileState.ApplyAssignedStationId(clearRole.profileData, nil)
	assertTrue(clearStation.accepted, "clear station accepted when role is none")
end

do
	local rejectedRole = SpecialistPreferenceProfileState.ApplySpecialistRole({}, "NotARealRole")
	assertFalse(rejectedRole.accepted, "invalid role rejected")
	assertEqual(rejectedRole.reason, "invalid_specialist_role", "invalid role reason")

	local rejectedStation = SpecialistPreferenceProfileState.ApplyAssignedStationId({}, "MiningStation_A")
	assertFalse(rejectedStation.accepted, "station without role rejected")
	assertEqual(rejectedStation.reason, "specialist_role_not_assigned", "station without role reason")
end

print("specialist_preference_profile_state: all checks passed")
