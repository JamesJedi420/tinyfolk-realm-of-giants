--!strict

local EscapeConfig = require("../src/ReplicatedStorage/Shared/Config/EscapeConfig")
local SafeLocationProfileState = require("../src/ReplicatedStorage/Shared/Escape/SafeLocationProfileState")

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

local function makeValidInput(returnReason: string): any
	return {
		returnPointName = EscapeConfig.TinyfolkReturnPointName,
		returnedAt = 10,
		returnReason = returnReason,
		realmId = "giant_realm_9001",
		realmOwnerUserId = 9001,
		sourceId = "Transport_A",
	}
end

do
	assertFalse(SafeLocationProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(SafeLocationProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		SafeLocationProfileState.HasPersistedState({
			safeLocation = {},
		}),
		"empty safe location not persisted"
	)
end

do
	local profileData = {
		safeLocation = makeValidInput("safe_return"),
	}
	assertTrue(SafeLocationProfileState.HasPersistedState(profileData), "valid safe location persisted")
	local snapshot = SafeLocationProfileState.GetLocation(profileData)
	assertTrue(snapshot ~= nil, "snapshot available")
	assertEqual(snapshot.returnPointName, EscapeConfig.TinyfolkReturnPointName, "return point name")
	assertEqual(snapshot.returnedAt, 10, "returned at")
	assertEqual(snapshot.returnReason, "safe_return", "return reason")
	assertEqual(snapshot.realmId, "giant_realm_9001", "realm id")
	assertEqual(snapshot.realmOwnerUserId, 9001, "realm owner")
	assertEqual(snapshot.sourceId, "Transport_A", "source id")
end

do
	local profileData = {
		safeLocation = {
			returnPointName = "UnknownReturnPoint",
			returnedAt = 10,
			returnReason = "safe_return",
		},
	}
	assertFalse(SafeLocationProfileState.HasPersistedState(profileData), "unknown return point rejected")
	assertTrue(SafeLocationProfileState.GetLocation(profileData) == nil, "unknown return point yields nil snapshot")
end

do
	local profileData = {
		safeLocation = {
			returnPointName = EscapeConfig.TinyfolkReturnPointName,
			returnedAt = -1,
			returnReason = "safe_return",
		},
	}
	assertFalse(SafeLocationProfileState.HasPersistedState(profileData), "invalid returnedAt rejected")
end

do
	local profileData = {
		safeLocation = {
			returnPointName = EscapeConfig.TinyfolkReturnPointName,
			returnedAt = 10,
			returnReason = "invalid_reason",
		},
	}
	assertFalse(SafeLocationProfileState.HasPersistedState(profileData), "invalid return reason rejected")
end

do
	local copied = SafeLocationProfileState.CopyProfileField({
		safeLocation = makeValidInput("escape_success"),
		invalidField = "ignored",
	})
	assertTrue(type(copied) == "table", "copy returns table")
	assertEqual(copied.returnReason, "escape_success", "copy keeps return reason")
	assertEqual(copied.realmOwnerUserId, 9001, "copy keeps realm owner")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")
end

do
	local applied = SafeLocationProfileState.ApplySafeReturn({}, makeValidInput("safe_return"))
	assertTrue(applied.accepted, "apply accepted")
	assertEqual(
		applied.profileData.safeLocation.returnPointName,
		EscapeConfig.TinyfolkReturnPointName,
		"apply writes return point"
	)
	assertEqual(applied.profileData.safeLocation.returnReason, "safe_return", "apply writes return reason")
end

do
	local first = SafeLocationProfileState.ApplySafeReturn({}, makeValidInput("safe_return"))
	assertTrue(first.accepted, "first apply accepted")
	local second = SafeLocationProfileState.ApplySafeReturn(first.profileData, {
		returnedAt = 20,
		returnReason = "escape_success",
		sourceId = "EscapeRoute_A",
	})
	assertTrue(second.accepted, "second apply accepted")
	assertEqual(second.profileData.safeLocation.returnedAt, 20, "apply replaces prior snapshot")
	assertEqual(second.profileData.safeLocation.returnReason, "escape_success", "apply updates return reason")
	assertEqual(second.profileData.safeLocation.sourceId, "EscapeRoute_A", "apply updates source id")
end

do
	local rejected = SafeLocationProfileState.ApplySafeReturn({}, {
		returnedAt = 10,
		returnReason = "not_a_reason",
	})
	assertFalse(rejected.accepted, "invalid apply rejected")
	assertEqual(rejected.reason, "safe_location_input_invalid", "invalid apply reason")
end

do
	local defaulted = SafeLocationProfileState.ApplySafeReturn({}, {
		returnedAt = 11,
		returnReason = "escape_success",
	})
	assertTrue(defaulted.accepted, "default return point accepted")
	assertEqual(
		defaulted.profileData.safeLocation.returnPointName,
		EscapeConfig.TinyfolkReturnPointName,
		"default return point name"
	)
end

do
	local applied = SafeLocationProfileState.ApplySafeReturn({}, makeValidInput("logout"))
	assertTrue(applied.accepted, "logout return reason accepted")
	assertEqual(applied.profileData.safeLocation.returnReason, "logout", "logout return reason persisted")
end

do
	local applied = SafeLocationProfileState.ApplySafeReturn({}, makeValidInput("safe_return"))
	local cleared = SafeLocationProfileState.ClearSafeLocation(applied.profileData)
	assertTrue(cleared.accepted, "clear safe location accepted")
	assertFalse(SafeLocationProfileState.HasPersistedState(cleared.profileData), "clear removes safe location")
end

print("safe_location_profile_state: all checks passed")
