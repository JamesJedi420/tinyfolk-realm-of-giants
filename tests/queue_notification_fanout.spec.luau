--!strict

local QueueNotificationFanout = require("../src/ServerScriptService/Services/QueueNotificationFanout")

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

local function makeEncodingCapture()
	local envelopes: { any } = {}
	local function encodeMessage(message: any): string
		table.insert(envelopes, message)
		return string.format("%s:%s", tostring(message.messageType), tostring(message.operationId))
	end

	return encodeMessage, envelopes
end

do
	local adapterCalls: { any } = {}
	local encodeMessage, envelopes = makeEncodingCapture()
	local fanout = QueueNotificationFanout.Create({
		messagingAdapter = {
			Publish = function(input: any)
				table.insert(adapterCalls, input)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
		encode = encodeMessage,
		now = function()
			return 42.25
		end,
		sourceJobId = "job-test",
	})
	assertTrue(type(fanout) == "table", "fanout created with adapter")

	local admission = fanout.PublishAdmission("admission_enqueue", {
		operationId = "op-admission",
	})
	assertTrue(admission.accepted, "admission publish accepted")
	assertEqual(adapterCalls[1].topic, "tin_queue_admission_v1", "admission topic")
	assertEqual(adapterCalls[1].message, "admission_enqueue:op-admission", "admission encoded message")
	assertEqual(adapterCalls[1].messageType, "admission_enqueue", "admission message type")
	assertEqual(adapterCalls[1].operationId, "op-admission", "admission operation id")
	assertEqual(envelopes[1].schemaVersion, 1, "admission schema version")
	assertEqual(envelopes[1].messageType, "admission_enqueue", "admission envelope message type")
	assertEqual(envelopes[1].operationId, "op-admission", "admission envelope operation id")
	assertEqual(envelopes[1].sourceJobId, "job-test", "admission source job id")
	assertEqual(envelopes[1].sentAt, 42.25, "admission sent at")
	assertEqual(envelopes[1].payload.operationId, "op-admission", "admission payload operation id")

	local rescue = fanout.PublishRescue("rescue_accepted", {
		operationId = "op-rescue",
	})
	assertTrue(rescue.accepted, "rescue publish accepted")
	assertEqual(adapterCalls[2].topic, "tin_queue_rescue_v1", "rescue topic")
	assertEqual(adapterCalls[2].message, "rescue_accepted:op-rescue", "rescue encoded message")
	assertEqual(adapterCalls[2].messageType, "rescue_accepted", "rescue message type")
	assertEqual(adapterCalls[2].operationId, "op-rescue", "rescue operation id")
	assertEqual(envelopes[2].schemaVersion, 1, "rescue schema version")
	assertEqual(envelopes[2].messageType, "rescue_accepted", "rescue envelope message type")
	assertEqual(envelopes[2].operationId, "op-rescue", "rescue envelope operation id")

	local announcement = fanout.PublishSystemAnnouncement("announcement_created", {
		operationId = "op-announcement",
		announcementId = "global-1",
		severity = "warning",
	})
	assertTrue(announcement.accepted, "announcement publish accepted")
	assertEqual(adapterCalls[3].topic, "tin_announcement_v1", "announcement topic")
	assertEqual(adapterCalls[3].message, "announcement_created:op-announcement", "announcement encoded message")
	assertEqual(adapterCalls[3].messageType, "announcement_created", "announcement message type")
	assertEqual(adapterCalls[3].operationId, "op-announcement", "announcement operation id")
	assertEqual(envelopes[3].schemaVersion, 1, "announcement schema version")
	assertEqual(envelopes[3].messageType, "announcement_created", "announcement envelope message type")
	assertEqual(envelopes[3].operationId, "op-announcement", "announcement envelope operation id")
end

do
	local encodeMessage = makeEncodingCapture()
	local fanout = QueueNotificationFanout.Create({
		messagingAdapter = {
			Publish = function(_input: any)
				error("should not publish invalid events")
			end,
		},
		encode = encodeMessage,
	})

	local invalidEvent = fanout.PublishAdmission("", {})
	assertFalse(invalidEvent.accepted, "invalid event rejected")
	assertEqual(invalidEvent.reason, "event_name_invalid", "invalid event reason")
end

do
	local fanout = QueueNotificationFanout.Create({
		messagingAdapter = {
			Publish = function(_input: any)
				error("should not publish encode failures")
			end,
		},
		encode = function(_message: any)
			error("encode failed")
		end,
	})

	local encodeFailed = fanout.PublishAdmission("admission_enqueue", {})
	assertFalse(encodeFailed.accepted, "encode failure rejected")
	assertEqual(encodeFailed.reason, "message_encode_failed", "encode failure reason")
end

do
	local encodeMessage = makeEncodingCapture()
	local fanout = QueueNotificationFanout.Create({
		messagingAdapter = {
			Publish = function(_input: any)
				error("should not publish schema failures")
			end,
		},
		encode = encodeMessage,
	})

	local schemaFailed = fanout.PublishAdmission("admission_enqueue", {
		value = string.rep("x", 513),
	})
	assertFalse(schemaFailed.accepted, "schema failure rejected")
	assertEqual(schemaFailed.reason, "payload_invalid", "schema failure reason")
end

do
	local encodeMessage = makeEncodingCapture()
	local fanout = QueueNotificationFanout.Create({
		messagingAdapter = {
			Publish = function(_input: any)
				return {
					accepted = false,
					reason = "publish_failed",
				}
			end,
		},
		encode = encodeMessage,
	})

	local rejected = fanout.PublishRescue("rescue_rejected", {
		operationId = "op-rejected",
	})
	assertFalse(rejected.accepted, "adapter rejection rejected")
	assertEqual(rejected.reason, "publish_failed", "adapter rejection reason")
end

do
	local serviceCalls: { any } = {}
	local encodeMessage = makeEncodingCapture()
	local fanout = QueueNotificationFanout.Create({
		messagingService = {
			PublishAsync = function(_self: any, topic: string, message: any)
				table.insert(serviceCalls, {
					topic = topic,
					message = message,
				})
			end,
		},
		encode = encodeMessage,
	})

	local legacy = fanout.PublishAdmission("admission_enqueue", {
		operationId = "op-legacy",
	})
	assertTrue(legacy.accepted, "legacy messaging service publish accepted")
	assertEqual(serviceCalls[1].topic, "tin_queue_admission_v1", "legacy publish topic")
	assertEqual(serviceCalls[1].message, "admission_enqueue:op-legacy", "legacy publish message")
end

do
	local adapterCalls: { any } = {}
	local encodeMessage, envelopes = makeEncodingCapture()
	local fanout = QueueNotificationFanout.Create({
		messagingAdapter = {
			Publish = function(input: any)
				table.insert(adapterCalls, input)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
		encode = encodeMessage,
		now = function()
			return 12.345
		end,
	})

	local generated = fanout.PublishAdmission("admission_batch_processed", {
		processed = 2,
	})
	assertTrue(generated.accepted, "missing operation id publish accepted")
	assertEqual(adapterCalls[1].operationId, "notification_admission_batch_processed_12345", "generated operation id")
	assertEqual(
		envelopes[1].operationId,
		"notification_admission_batch_processed_12345",
		"generated envelope operation id"
	)
end

print("queue_notification_fanout: all checks passed")
