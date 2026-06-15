--!strict

local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")

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

local function makeSharedHubSnapshot(updatedAt: number): any
	return {
		locationCategory = RealmAssignmentProfileState.LocationCategory.SharedHub,
		updatedAt = updatedAt,
	}
end

local function makeGiantRealmSnapshot(ownerUserId: number, updatedAt: number): any
	return {
		locationCategory = RealmAssignmentProfileState.LocationCategory.GiantRealm,
		realmId = string.format("giant_realm_%d", ownerUserId),
		realmOwnerUserId = ownerUserId,
		updatedAt = updatedAt,
	}
end

local function makeInFlightSnapshot(ownerUserId: number, reason: string, updatedAt: number): any
	return {
		locationCategory = RealmAssignmentProfileState.LocationCategory.TransferInFlight,
		realmId = string.format("giant_realm_%d", ownerUserId),
		realmOwnerUserId = ownerUserId,
		assignmentReason = reason,
		updatedAt = updatedAt,
	}
end

do
	assertFalse(RealmAssignmentProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(RealmAssignmentProfileState.HasPersistedState({}), "empty profile not persisted")
end

do
	local profileData = {
		realmAssignment = makeSharedHubSnapshot(10),
	}
	assertTrue(RealmAssignmentProfileState.HasPersistedState(profileData), "shared hub persisted")
	local snapshot = RealmAssignmentProfileState.GetAssignment(profileData)
	assertTrue(snapshot ~= nil, "shared hub snapshot available")
	assertEqual(
		snapshot.locationCategory,
		RealmAssignmentProfileState.LocationCategory.SharedHub,
		"shared hub category"
	)
end

do
	local profileData = {
		realmAssignment = makeGiantRealmSnapshot(9001, 20),
	}
	assertTrue(RealmAssignmentProfileState.HasPersistedState(profileData), "giant realm persisted")
	local snapshot = RealmAssignmentProfileState.GetAssignment(profileData)
	assertEqual(snapshot.realmId, "giant_realm_9001", "giant realm id")
	assertEqual(snapshot.realmOwnerUserId, 9001, "giant realm owner")
	assertTrue(snapshot.assignmentReason == nil, "giant realm reason cleared")
end

do
	local profileData = {
		realmAssignment = makeInFlightSnapshot(9002, RealmAssignmentProfileState.AssignmentReason.Capture, 30),
	}
	assertTrue(RealmAssignmentProfileState.HasPersistedState(profileData), "in flight persisted")
	local snapshot = RealmAssignmentProfileState.GetAssignment(profileData)
	assertEqual(snapshot.assignmentReason, RealmAssignmentProfileState.AssignmentReason.Capture, "capture reason")
end

do
	local profileData = {
		realmAssignment = {
			locationCategory = RealmAssignmentProfileState.LocationCategory.SharedHub,
			realmId = "giant_realm_1",
			updatedAt = 10,
		},
	}
	assertFalse(RealmAssignmentProfileState.HasPersistedState(profileData), "shared hub rejects realm fields")
end

do
	local profileData = {
		realmAssignment = {
			locationCategory = RealmAssignmentProfileState.LocationCategory.GiantRealm,
			realmId = "giant_realm_9001",
			realmOwnerUserId = 9002,
			updatedAt = 10,
		},
	}
	assertFalse(RealmAssignmentProfileState.HasPersistedState(profileData), "realm id owner mismatch rejected")
end

do
	local copied = RealmAssignmentProfileState.CopyProfileField({
		realmAssignment = makeInFlightSnapshot(9003, RealmAssignmentProfileState.AssignmentReason.Trade, 40),
		invalidField = "ignored",
	})
	assertTrue(type(copied) == "table", "copy returns table")
	assertEqual(copied.realmId, "giant_realm_9003", "copy keeps realm id")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")
end

do
	local applyResult = RealmAssignmentProfileState.ApplyAssignment({}, makeGiantRealmSnapshot(9010, 50))
	assertTrue(applyResult.accepted, "apply giant realm accepted")
	assertTrue(RealmAssignmentProfileState.HasPersistedState(applyResult.profileData), "apply writes assignment")
end

do
	local seeded = RealmAssignmentProfileState.ApplyAssignment({}, makeGiantRealmSnapshot(9011, 51))
	assertTrue(seeded.accepted, "seed apply accepted")
	local clearResult = RealmAssignmentProfileState.ClearAssignment(seeded.profileData)
	assertTrue(clearResult.accepted, "clear accepted")
	assertFalse(RealmAssignmentProfileState.HasPersistedState(clearResult.profileData), "clear removes assignment")
end

print("realm_assignment_profile_state: all checks passed")
