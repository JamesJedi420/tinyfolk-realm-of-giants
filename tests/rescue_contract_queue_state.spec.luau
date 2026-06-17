--!nocheck
local RescueContractQueueState = require("../src/ReplicatedStorage/Shared/GiantRealm/RescueContractQueueState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function makePendingEntry(overrides: any?): any
	local entry = {
		queueEntryId = "queue_1",
		operationId = "rescue_accept_queue_1",
		capturedUserId = 2102,
		realmId = "giant_realm_9001",
		sessionId = "session_a",
		rewardHint = "rescue_contract",
		dangerRating = 0.5,
		expiration = 112,
		rescuerUserId = 2101,
		targetRealmOwnerUserId = 9001,
		entryRouteId = "RescueEntryRoute_9001",
		entryRouteKind = "RescueEntry",
		createdAt = 100,
		status = "pending",
	}
	if overrides ~= nil then
		for key, value in overrides do
			entry[key] = value
		end
	end
	return entry
end

do
	local state = RescueContractQueueState.NewState()
	state = RescueContractQueueState.UpsertPending(state, makePendingEntry())
	local pending = RescueContractQueueState.GetPendingEntries(state)
	assertEqual(#pending, 1, "upsert pending adds one entry")
	assertEqual(pending[1].queueEntryId, "queue_1", "pending entry id")
end

do
	local state = RescueContractQueueState.NewState()
	state = RescueContractQueueState.UpsertPending(state, makePendingEntry())
	local acceptedEntry
	state, acceptedEntry = RescueContractQueueState.MarkAccepted(state, "queue_1", 3001, 101)
	assertTrue(acceptedEntry ~= nil, "mark accepted returns entry")
	assertEqual(acceptedEntry.status, "accepted", "mark accepted updates status")
	assertEqual(acceptedEntry.acceptedByUserId, 3001, "mark accepted stores accepter")
	local pending = RescueContractQueueState.GetPendingEntries(state)
	assertEqual(#pending, 0, "accepted entries not returned as pending")
end

do
	local state = RescueContractQueueState.NewState()
	state = RescueContractQueueState.UpsertPending(state, makePendingEntry())
	state = RescueContractQueueState.MarkResolvedByContract(state, 2101, 2102, "rescued", 102)
	local pending = RescueContractQueueState.GetPendingEntries(state)
	assertEqual(#pending, 0, "resolved by contract removes pending visibility")
	local entry = RescueContractQueueState.GetEntry(state, "queue_1")
	assertEqual(entry.status, "resolved", "resolved by contract updates status")
	assertEqual(entry.resolvedReason, "rescued", "resolved by contract reason")
end

do
	local state = RescueContractQueueState.NewState()
	state = RescueContractQueueState.UpsertPending(state, makePendingEntry())
	local expiredEntries
	state, expiredEntries = RescueContractQueueState.PruneExpired(state, 120)
	assertEqual(#expiredEntries, 1, "prune expired returns one expired entry")
	assertEqual(expiredEntries[1].status, "expired", "prune expired marks status")
	local pending = RescueContractQueueState.GetPendingEntries(state)
	assertEqual(#pending, 0, "expired entries not pending")
end

print("rescue_contract_queue_state: all checks passed")
