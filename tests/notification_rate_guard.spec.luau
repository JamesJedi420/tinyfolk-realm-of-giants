--!strict

local NotificationRateGuard = require("../src/ServerScriptService/Services/NotificationRateGuard")

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

do
	local now = 100
	local guard = NotificationRateGuard.Create({
		now = function()
			return now
		end,
		maxPublishesPerWindow = 2,
		windowSeconds = 1,
	})

	local first = guard.EvaluatePublish({
		topic = "tin_queue_admission_v1",
		messageType = "admission_enqueue",
		operationId = "op-1",
	})
	assertTrue(first.accepted, "first low-frequency publish accepted")
	assertEqual(first.reason, "accepted", "first low-frequency reason")
	assertEqual(first.action, "publish", "first low-frequency action")

	local second = guard.EvaluatePublish({
		topic = "tin_queue_admission_v1",
		messageType = "admission_enqueue",
		operationId = "op-2",
	})
	assertTrue(second.accepted, "second publish inside window accepted")

	local third = guard.EvaluatePublish({
		topic = "tin_queue_admission_v1",
		messageType = "admission_enqueue",
		operationId = "op-3",
	})
	assertFalse(third.accepted, "third non-coalescible publish dropped")
	assertEqual(third.reason, "rate_limited", "third non-coalescible reason")
	assertEqual(third.action, "drop", "third non-coalescible action")

	local diagnostics = guard.GetDiagnostics()
	assertEqual(diagnostics.attempts, 3, "diagnostics attempts")
	assertEqual(diagnostics.accepted, 2, "diagnostics accepted")
	assertEqual(diagnostics.dropped, 1, "diagnostics dropped")
	assertEqual(diagnostics.frequencyByKey["tin_queue_admission_v1|admission_enqueue"], 3, "frequency by key")
	assertEqual(diagnostics.lastOperationId, "op-3", "last operation id")
	assertEqual(diagnostics.lastReason, "rate_limited", "last reason")

	now = 102
	local afterWindow = guard.EvaluatePublish({
		topic = "tin_queue_admission_v1",
		messageType = "admission_enqueue",
		operationId = "op-4",
	})
	assertTrue(afterWindow.accepted, "window reset accepts publish")
	assertEqual(afterWindow.reason, "accepted", "window reset reason")
end

do
	local now = 10
	local guard = NotificationRateGuard.Create({
		now = function()
			return now
		end,
		maxPublishesPerWindow = 1,
		windowSeconds = 1,
	})

	local first = guard.EvaluatePublish({
		topic = "tin_realm_v1",
		messageType = "RealmStatusChanged",
		operationId = "realm-op-1",
		realmId = "realm-a",
	})
	assertTrue(first.accepted, "first status accepted")
	assertEqual(first.action, "publish", "first status publishes")

	local coalesced = guard.EvaluatePublish({
		topic = "tin_realm_v1",
		messageType = "RealmStatusChanged",
		operationId = "realm-op-2",
		realmId = "realm-a",
	})
	assertTrue(coalesced.accepted, "high-frequency status accepted as coalesced")
	assertEqual(coalesced.reason, "coalesced", "high-frequency status reason")
	assertEqual(coalesced.action, "coalesce", "high-frequency status action")
	assertEqual(coalesced.summary.messageType, "RealmStatusSummary", "high-frequency status summary type")
	assertEqual(coalesced.summary.realmId, "realm-a", "high-frequency status summary realm")

	local diagnostics = guard.GetDiagnostics()
	assertEqual(diagnostics.coalesced, 1, "diagnostics coalesced")
	assertEqual(diagnostics.lastRealmId, "realm-a", "diagnostics last realm")
	assertEqual(diagnostics.realmStatusByRealm["realm-a"], now, "realm status timestamp")
end

do
	local now = 50
	local guard = NotificationRateGuard.Create({
		now = function()
			return now
		end,
		realmStatusMinIntervalSeconds = 5,
		maxPublishesPerWindow = 10,
	})

	local first = guard.EvaluatePublish({
		topic = "tin_realm_v1",
		messageType = "RealmStatusChanged",
		operationId = "realm-a-1",
		realmId = "realm-a",
	})
	assertEqual(first.action, "publish", "realm-a first publishes")

	now = 52
	local sameRealm = guard.EvaluatePublish({
		topic = "tin_realm_v1",
		messageType = "RealmStatusChanged",
		operationId = "realm-a-2",
		realmId = "realm-a",
	})
	assertEqual(sameRealm.action, "coalesce", "same realm min interval coalesces")

	local otherRealm = guard.EvaluatePublish({
		topic = "tin_realm_v1",
		messageType = "RealmStatusChanged",
		operationId = "realm-b-1",
		realmId = "realm-b",
	})
	assertEqual(otherRealm.action, "publish", "different realm publishes independently")

	now = 56
	local afterInterval = guard.EvaluatePublish({
		topic = "tin_realm_v1",
		messageType = "RealmStatusChanged",
		operationId = "realm-a-3",
		realmId = "realm-a",
	})
	assertEqual(afterInterval.action, "publish", "same realm publishes after interval")
end

do
	local guard = NotificationRateGuard.Create()

	local invalidTopic = guard.EvaluatePublish({
		topic = "",
		messageType = "RealmStatusChanged",
	})
	assertFalse(invalidTopic.accepted, "invalid topic rejected")
	assertEqual(invalidTopic.reason, "topic_invalid", "invalid topic reason")

	local invalidMessageType = guard.EvaluatePublish({
		topic = "tin_realm_v1",
		messageType = "",
	})
	assertFalse(invalidMessageType.accepted, "invalid message type rejected")
	assertEqual(invalidMessageType.reason, "message_type_invalid", "invalid message type reason")

	local flushed = guard.Flush()
	assertTrue(flushed.accepted, "flush accepted")
	local diagnostics = guard.GetDiagnostics()
	assertEqual(diagnostics.flushAttempts, 1, "flush attempts")
end

do
	local guard = NotificationRateGuard.ConfigureForTests({
		maxPublishesPerWindow = 1,
	})
	assertTrue(type(guard.EvaluatePublish) == "function", "configured query api guard")
	assertTrue(type((_G :: any)._NotificationRateGuard_QueryAPI) == "table", "global query api published")
	NotificationRateGuard.ResetForTests()
	assertEqual((_G :: any)._NotificationRateGuard_QueryAPI, nil, "global query api reset")
end

print("notification_rate_guard: all checks passed")
