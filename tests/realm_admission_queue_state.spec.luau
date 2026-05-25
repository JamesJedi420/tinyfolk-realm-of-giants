--!strict

local RealmAdmissionQueueState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAdmissionQueueState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function makeEntry(overrides: any?): any
	local entry = {
		operationId = "op-9001",
		partyId = "party-17",
		targetRealmId = "realm-9402",
		entryType = "standard",
		priority = nil,
		createdAt = 100,
		expiration = 220,
		partySize = 2,
		retryCount = 0,
	}
	if overrides ~= nil then
		for key, value in pairs(overrides) do
			entry[key] = value
		end
	end
	return entry
end

local priorityStandard = RealmAdmissionQueueState.ResolvePriority("standard")
local priorityDirect = RealmAdmissionQueueState.ResolvePriority("direct_invite")
local priorityRescue = RealmAdmissionQueueState.ResolvePriority("rescue_contract")
assertEqual(priorityStandard, 100, "standard priority")
assertEqual(priorityDirect, 200, "direct invite priority")
assertEqual(priorityRescue, 300, "rescue contract priority")

local boostedPriority, boostedReason = RealmAdmissionQueueState.ResolvePriority("direct_invite", 250)
assertEqual(boostedPriority, 250, "explicit higher priority kept")
assertEqual(boostedReason, nil, "explicit higher priority reason")

local clampedPriority, clampedReason = RealmAdmissionQueueState.ResolvePriority("rescue_contract", 1)
assertEqual(clampedPriority, 300, "priority clamped to baseline")
assertEqual(clampedReason, nil, "priority clamp reason")

local invalidTypePriority, invalidTypeReason = RealmAdmissionQueueState.ResolvePriority("unknown")
assertEqual(invalidTypePriority, nil, "invalid type priority nil")
assertEqual(invalidTypeReason, "entry_type_invalid", "invalid type reason")

local valid = RealmAdmissionQueueState.NewEntry(makeEntry())
assertTrue(valid.ok, "valid entry accepted")
assertEqual(valid.entry.priority, 100, "default priority derived")
assertEqual(valid.entry.partySize, 2, "party size accepted")
assertEqual(valid.entry.retryCount, 0, "retry count default")

local rescueInput = makeEntry({
	entryType = "rescue_contract",
	priority = 250,
})
rescueInput.partySize = nil
rescueInput.retryCount = nil
local rescue = RealmAdmissionQueueState.NewEntry(rescueInput)
assertTrue(rescue.ok, "rescue entry accepted")
assertEqual(rescue.entry.priority, 300, "rescue baseline priority enforced")
assertEqual(rescue.entry.partySize, 1, "party size default")
assertEqual(rescue.entry.retryCount, 0, "retry default")

local invalidParty = RealmAdmissionQueueState.NewEntry(makeEntry({ partyId = "" }))
assertFalse(invalidParty.ok, "invalid party rejected")
assertEqual(invalidParty.reason, "party_id_invalid", "invalid party reason")

local invalidExpiration = RealmAdmissionQueueState.NewEntry(makeEntry({ expiration = 100 }))
assertFalse(invalidExpiration.ok, "expiration equal created rejected")
assertEqual(invalidExpiration.reason, "expiration_invalid", "invalid expiration reason")

local invalidRetry = RealmAdmissionQueueState.NewEntry(makeEntry({ retryCount = -1 }))
assertFalse(invalidRetry.ok, "negative retry rejected")
assertEqual(invalidRetry.reason, "retry_count_invalid", "negative retry reason")

local snapshot = RealmAdmissionQueueState.GetSnapshot(valid.entry)
assertTrue(snapshot ~= nil, "snapshot exists")
assertEqual(snapshot.operationId, valid.entry.operationId, "snapshot operation id")
local snapshotAny: any = snapshot
snapshotAny.operationId = "mutated"
assertEqual(valid.entry.operationId, "op-9001", "snapshot clone isolation")

assertFalse(RealmAdmissionQueueState.IsExpired(valid.entry, 219), "entry before expiration")
assertTrue(RealmAdmissionQueueState.IsExpired(valid.entry, 220), "entry at expiration")

local retried = RealmAdmissionQueueState.WithRetryIncrement(valid.entry)
assertTrue(retried.ok, "retry increment accepted")
assertEqual(retried.entry.retryCount, 1, "retry count incremented")
assertEqual(valid.entry.retryCount, 0, "retry increment clone isolation")

print("realm_admission_queue_state: all checks passed")
