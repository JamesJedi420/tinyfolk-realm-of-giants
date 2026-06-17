--!nocheck
local RescueContractHubState = require("../src/ReplicatedStorage/Shared/GiantRealm/RescueContractHubState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local sampleEntry = {
	queueEntryId = "queue_1",
	operationId = "rescue_accept_queue_1",
	capturedUserId = 2102,
	realmId = "giant_realm_9001",
	sessionId = "session_a",
	rewardHint = "rescue_contract",
	dangerRating = 0.6,
	expiration = 120,
	rescuerUserId = 2101,
	targetRealmOwnerUserId = 9001,
	entryRouteId = "RescueEntryRoute_9001",
	entryRouteKind = "RescueEntry",
	createdAt = 100,
	status = "pending",
}

do
	local row = RescueContractHubState.BuildContractRow(sampleEntry, 105)
	assertTrue(row ~= nil, "build contract row")
	assertEqual(row.queueEntryId, "queue_1", "row queue entry id")
	assertEqual(row.secondsRemaining, 15, "row seconds remaining")
	assertEqual(row.rewardTierLabel, "Elevated", "row reward tier")
end

do
	local projected = RescueContractHubState.ProjectContracts({
		entries = { sampleEntry },
		limit = 10,
		nowAt = 105,
	})
	assertTrue(projected.accepted, "project contracts accepted")
	assertEqual(#projected.contracts, 1, "project contracts count")
	assertEqual(projected.contracts[1].realmDisplayName, "giant_realm_9001", "project realm display")
end

do
	local safe, reason = RescueContractHubState.AssertClientSafeContractRow({
		queueEntryId = "queue_1",
		realmId = "giant_realm_9001",
	})
	assertTrue(safe, "client safe row")
	assertEqual(reason, nil, "client safe row reason")

	local unsafe, unsafeReason = RescueContractHubState.AssertClientSafeContractRow({
		queueEntryId = "queue_1",
		storeReceiptId = "receipt_1",
	})
	assertEqual(unsafe, false, "client unsafe row")
	assertEqual(unsafeReason, "forbidden_field_exposed", "client unsafe row reason")
end

print("rescue_contract_hub_state: all checks passed")
