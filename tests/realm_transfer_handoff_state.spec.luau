--!nocheck

local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferHandoffState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferHandoffState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local targetRealmId = "giant_realm_9001"
local now = 100

local beginResult = RealmTransferHandoffState.BeginHandoff(nil, {
	userId = 7001,
	targetRealmId = targetRealmId,
	operationId = "handoff:7001:1",
	assignmentReason = RealmAssignmentProfileState.AssignmentReason.Capture,
	now = now,
	ttlSeconds = 90,
	realmOwnerUserId = 9001,
})
assertTrue(beginResult.accepted == true, "begin accepted")
assertTrue(beginResult.sessionRecord ~= nil, "begin session record")
assertTrue(beginResult.handoffEntry ~= nil, "begin handoff entry")
assertEqual(beginResult.handoffEntry.assignmentReason, "capture", "begin assignment reason")

local consumeResult = RealmTransferHandoffState.ConsumeHandoff(beginResult.sessionRecord, {
	userId = 7001,
	handoffToken = "handoff:7001:1",
	now = now + 10,
})
assertTrue(consumeResult.accepted == true, "consume accepted")
assertTrue(consumeResult.sessionRecord.handoffsByToken["handoff:7001:1"] == nil, "consume clears token")

local expiredBegin = RealmTransferHandoffState.BeginHandoff(nil, {
	userId = 7002,
	targetRealmId = targetRealmId,
	operationId = "handoff:7002:1",
	now = now,
	ttlSeconds = 30,
})
assertTrue(expiredBegin.accepted == true, "expired begin accepted")
local expiredConsume = RealmTransferHandoffState.ConsumeHandoff(expiredBegin.sessionRecord, {
	userId = 7002,
	handoffToken = "handoff:7002:1",
	now = now + 31,
})
assertEqual(expiredConsume.reason, "handoff_token_expired", "expired consume rejected")

local activeBegin = RealmTransferHandoffState.BeginHandoff(nil, {
	userId = 7003,
	targetRealmId = targetRealmId,
	operationId = "handoff:7003:dup",
	now = now,
})
assertTrue(activeBegin.accepted == true, "active begin accepted")
local duplicateBegin = RealmTransferHandoffState.BeginHandoff(activeBegin.sessionRecord, {
	userId = 7004,
	targetRealmId = targetRealmId,
	operationId = "handoff:7003:dup",
	now = now + 1,
})
assertEqual(duplicateBegin.reason, "handoff_token_already_active", "duplicate token rejected")

print("realm_transfer_handoff_state: all checks passed")
