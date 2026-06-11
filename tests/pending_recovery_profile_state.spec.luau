--!strict

local PendingRecoveryProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/PendingRecoveryProfileState")

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

local function makeValidInput(): any
	return {
		handoffToken = "handoff:9001:1",
		targetRealmId = "realm-main-01",
		startedAt = 10,
		status = PendingRecoveryProfileState.Status.AwaitingDestination,
	}
end

do
	assertFalse(PendingRecoveryProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(PendingRecoveryProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		PendingRecoveryProfileState.HasPersistedState({
			pendingRecovery = {},
		}),
		"empty pending recovery not persisted"
	)
end

do
	local profileData = {
		pendingRecovery = makeValidInput(),
	}
	assertTrue(PendingRecoveryProfileState.HasPersistedState(profileData), "valid pending recovery persisted")
	local snapshot = PendingRecoveryProfileState.GetRecovery(profileData)
	assertTrue(snapshot ~= nil, "snapshot available")
	assertEqual(snapshot.handoffToken, "handoff:9001:1", "handoff token")
	assertEqual(snapshot.targetRealmId, "realm-main-01", "target realm id")
	assertEqual(snapshot.startedAt, 10, "started at")
	assertEqual(snapshot.status, PendingRecoveryProfileState.Status.AwaitingDestination, "status")
end

do
	local profileData = {
		pendingRecovery = {
			handoffToken = "",
			targetRealmId = "realm-main-01",
			startedAt = 10,
			status = PendingRecoveryProfileState.Status.AwaitingDestination,
		},
	}
	assertFalse(PendingRecoveryProfileState.HasPersistedState(profileData), "empty handoff token rejected")
end

do
	local profileData = {
		pendingRecovery = {
			handoffToken = "handoff:9001:1",
			targetRealmId = "realm-main-01",
			startedAt = -1,
			status = PendingRecoveryProfileState.Status.AwaitingDestination,
		},
	}
	assertFalse(PendingRecoveryProfileState.HasPersistedState(profileData), "invalid startedAt rejected")
end

do
	local profileData = {
		pendingRecovery = {
			handoffToken = "handoff:9001:1",
			targetRealmId = "realm-main-01",
			startedAt = 10,
			status = "invalid_status",
		},
	}
	assertFalse(PendingRecoveryProfileState.HasPersistedState(profileData), "invalid status rejected")
end

do
	local copied = PendingRecoveryProfileState.CopyProfileField({
		pendingRecovery = makeValidInput(),
		invalidField = "ignored",
	})
	assertTrue(type(copied) == "table", "copy returns table")
	assertEqual(copied.handoffToken, "handoff:9001:1", "copy keeps handoff token")
	assertEqual(copied.targetRealmId, "realm-main-01", "copy keeps target realm id")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")
end

do
	local applyResult = PendingRecoveryProfileState.ApplyPendingHandoff({}, {
		handoffToken = "handoff:9001:2",
		targetRealmId = "realm-main-02",
		startedAt = 20,
	})
	assertTrue(applyResult.accepted, "apply pending handoff accepted")
	assertTrue(PendingRecoveryProfileState.HasPersistedState(applyResult.profileData), "apply writes pending recovery")
	local snapshot = PendingRecoveryProfileState.GetRecovery(applyResult.profileData)
	assertEqual(snapshot.targetRealmId, "realm-main-02", "apply target realm id")
end

do
	local applyResult = PendingRecoveryProfileState.ApplyPendingHandoff({}, {
		handoffToken = "",
		targetRealmId = "realm-main-02",
		startedAt = 20,
	})
	assertFalse(applyResult.accepted, "invalid apply rejected")
	assertEqual(applyResult.reason, "pending_recovery_input_invalid", "invalid apply reason")
end

do
	local seeded = PendingRecoveryProfileState.ApplyPendingHandoff({}, makeValidInput())
	assertTrue(seeded.accepted, "seed apply accepted")
	local clearResult = PendingRecoveryProfileState.ClearRecovery(seeded.profileData)
	assertTrue(clearResult.accepted, "clear accepted")
	assertFalse(
		PendingRecoveryProfileState.HasPersistedState(clearResult.profileData),
		"clear removes pending recovery"
	)
end

print("pending_recovery_profile_state: all checks passed")
