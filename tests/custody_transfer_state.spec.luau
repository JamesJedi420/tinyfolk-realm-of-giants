local CustodyTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/CustodyTransferState")
local CaptivityDurationState = require("../src/ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState")

local function assertEqual(actual: any, expected: any, message: string)
	if actual ~= expected then
		error(string.format("%s (expected=%s actual=%s)", message, tostring(expected), tostring(actual)))
	end
	print("PASS [" .. message .. "]")
end

local function assertTrue(value: any, message: string)
	if value ~= true then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function assertFalse(value: any, message: string)
	if value ~= false then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function makeRecord(overrides: any?): any
	local record = {
		custodianUserId = 100,
		targetUserId = 200,
		startedAt = 10,
		expiresAt = 18,
		captivityAnchorAt = 10,
		containmentPhase = CaptivityDurationState.Phases.captured,
		containedAt = nil,
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			record[key] = value
		end
	end
	return record
end

local state = CustodyTransferState.NewState()

local terms = CustodyTransferState.BuildTerms({
	record = makeRecord(),
	incomingCustodianUserId = 300,
	now = 12,
}, nil)
assertTrue(type(terms) == "table", "build terms")
assertEqual(terms.outgoingCustodianUserId, 100, "terms outgoing custodian")
assertEqual(terms.incomingCustodianUserId, 300, "terms incoming custodian")
assertEqual(terms.captivityAnchorAt, 10, "terms captivity anchor")
assertEqual(terms.custodyExpiresAt, 18, "terms custody expires")
assertTrue(terms.remainingSeconds > 0, "terms remaining seconds positive")
assertTrue(#terms.endConditions >= 4, "terms include end conditions")

local requested = CustodyTransferState.ResolveRequest(state, {
	now = 12,
	outgoingCustodianUserId = 100,
	incomingCustodianUserId = 300,
	targetUserId = 200,
	record = makeRecord(),
	requestExpirySeconds = 8,
	requestId = "transfer_test_1",
}, nil)
assertTrue(requested.accepted == true, "request accepted")
assertTrue(requested.request ~= nil, "request returns pending request")
assertEqual(requested.request.requestId, "transfer_test_1", "request id")
assertEqual(requested.request.outgoingConfirmedAt, 12, "outgoing confirmed at request")
assertEqual(requested.request.incomingConfirmedAt, nil, "incoming not confirmed yet")
state = requested.state

local duplicate = CustodyTransferState.ResolveRequest(state, {
	now = 12.5,
	outgoingCustodianUserId = 100,
	incomingCustodianUserId = 301,
	targetUserId = 200,
	record = makeRecord(),
	requestExpirySeconds = 8,
	requestId = "transfer_test_2",
}, nil)
assertFalse(duplicate.accepted == true, "duplicate pending rejected")
assertEqual(duplicate.reason, "transfer_already_pending", "duplicate pending reason")

local changedTerms = CustodyTransferState.ResolveConfirm(state, {
	now = 13,
	incomingCustodianUserId = 300,
	requestId = "transfer_test_1",
	record = makeRecord({ expiresAt = 17 }),
}, nil)
assertFalse(changedTerms.accepted == true, "confirm rejects changed terms")
assertEqual(changedTerms.reason, "transfer_terms_changed", "changed terms reason")

local confirmed = CustodyTransferState.ResolveConfirm(state, {
	now = 13,
	incomingCustodianUserId = 300,
	requestId = "transfer_test_1",
	record = makeRecord(),
}, nil)
assertTrue(confirmed.accepted == true, "confirm accepted")
assertEqual(confirmed.request.incomingConfirmedAt, 13, "incoming confirmed at settle")
assertEqual(confirmed.terms.captivityAnchorAt, 10, "confirmed terms preserve anchor")
assertTrue(CustodyTransferState.GetPendingByRequestId(confirmed.state, "transfer_test_1") == nil, "pending cleared")

state = CustodyTransferState.NewState()
local requestAgain = CustodyTransferState.ResolveRequest(state, {
	now = 1,
	outgoingCustodianUserId = 100,
	incomingCustodianUserId = 300,
	targetUserId = 200,
	record = makeRecord({ startedAt = 1, expiresAt = 9, captivityAnchorAt = 1 }),
	requestExpirySeconds = 4,
	requestId = "transfer_cancel_1",
}, nil)
state = requestAgain.state
assertTrue(requestAgain.accepted == true, "cancel setup request accepted")

local cancelled = CustodyTransferState.ResolveCancel(state, {
	now = 2,
	requestId = "transfer_cancel_1",
	actorUserId = 300,
})
assertTrue(cancelled.accepted == true, "incoming can cancel")
assertEqual(cancelled.reason, "transfer_cancelled", "cancel reason")
state = cancelled.state
assertTrue(CustodyTransferState.GetPendingByTargetUserId(state, 200) == nil, "cancel clears pending")

state = CustodyTransferState.NewState()
local expiredRequest = CustodyTransferState.ResolveRequest(state, {
	now = 1,
	outgoingCustodianUserId = 100,
	incomingCustodianUserId = 300,
	targetUserId = 200,
	record = makeRecord({ startedAt = 1, expiresAt = 9, captivityAnchorAt = 1 }),
	requestExpirySeconds = 2,
	requestId = "transfer_expired_1",
}, nil)
state = expiredRequest.state
local expiredConfirm = CustodyTransferState.ResolveConfirm(state, {
	now = 4,
	incomingCustodianUserId = 300,
	requestId = "transfer_expired_1",
	record = makeRecord({ startedAt = 1, expiresAt = 9, captivityAnchorAt = 1 }),
}, nil)
assertFalse(expiredConfirm.accepted == true, "expired request rejected")
assertEqual(expiredConfirm.reason, "transfer_request_missing", "expired request pruned before confirm")

print("custody_transfer_state: all checks passed")
