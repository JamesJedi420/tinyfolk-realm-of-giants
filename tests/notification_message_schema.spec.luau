--!strict

local NotificationMessageSchema = require("../src/ServerScriptService/Services/NotificationMessageSchema")

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
	local topic = NotificationMessageSchema.GetTopic("admissionQueue")
	assertTrue(topic.accepted, "known topic accepted")
	assertEqual(topic.topic, "tin_queue_admission_v1", "known topic value")

	local announcementTopic = NotificationMessageSchema.GetTopic("systemAnnouncement")
	assertTrue(announcementTopic.accepted, "system announcement topic accepted")
	assertEqual(announcementTopic.topic, "tin_announcement_v1", "system announcement topic value")

	local literalTopic = NotificationMessageSchema.GetTopic("tin_custom_v1")
	assertTrue(literalTopic.accepted, "literal topic accepted")
	assertEqual(literalTopic.topic, "tin_custom_v1", "literal topic value")

	local invalidTopic = NotificationMessageSchema.GetTopic("")
	assertFalse(invalidTopic.accepted, "empty topic rejected")
	assertEqual(invalidTopic.reason, "topic_invalid", "empty topic reason")
end

do
	local result = NotificationMessageSchema.BuildEnvelope({
		messageType = "admission_enqueue",
		operationId = "op-1",
		sourceJobId = "job-1",
		sentAt = 123.5,
		payload = {
			partyId = "party-1",
			memberCount = 2,
			accepted = true,
		},
	})

	assertTrue(result.accepted, "valid envelope accepted")
	assertEqual(result.envelope.schemaVersion, NotificationMessageSchema.SCHEMA_VERSION, "schema version")
	assertEqual(result.envelope.messageType, "admission_enqueue", "message type")
	assertEqual(result.envelope.operationId, "op-1", "operation id")
	assertEqual(result.envelope.sourceJobId, "job-1", "source job id")
	assertEqual(result.envelope.sentAt, 123.5, "sent at")
	assertEqual(result.envelope.payload.partyId, "party-1", "payload cloned")

	local validation = NotificationMessageSchema.ValidateEnvelope(result.envelope)
	assertTrue(validation.accepted, "built envelope validates")
end

do
	local missingMessageType = NotificationMessageSchema.BuildEnvelope({
		messageType = "",
		operationId = "op-1",
		sourceJobId = "job-1",
		sentAt = 1,
		payload = {},
	})
	assertFalse(missingMessageType.accepted, "missing message type rejected")
	assertEqual(missingMessageType.reason, "message_type_invalid", "missing message type reason")

	local missingOperationId = NotificationMessageSchema.BuildEnvelope({
		messageType = "admission_enqueue",
		operationId = "",
		sourceJobId = "job-1",
		sentAt = 1,
		payload = {},
	})
	assertFalse(missingOperationId.accepted, "missing operation id rejected")
	assertEqual(missingOperationId.reason, "operation_id_invalid", "missing operation id reason")

	local invalidSentAt = NotificationMessageSchema.BuildEnvelope({
		messageType = "admission_enqueue",
		operationId = "op-1",
		sourceJobId = "job-1",
		sentAt = math.huge,
		payload = {},
	})
	assertFalse(invalidSentAt.accepted, "invalid sentAt rejected")
	assertEqual(invalidSentAt.reason, "sent_at_invalid", "invalid sentAt reason")
end

do
	local invalidPayload = NotificationMessageSchema.BuildEnvelope({
		messageType = "admission_enqueue",
		operationId = "op-1",
		sourceJobId = "job-1",
		sentAt = 1,
		payload = function() end,
	})
	assertFalse(invalidPayload.accepted, "function payload rejected")
	assertEqual(invalidPayload.reason, "payload_invalid", "function payload reason")

	local oversizedPayload: any = {}
	for index = 1, 65 do
		oversizedPayload["k" .. tostring(index)] = index
	end
	local oversized = NotificationMessageSchema.BuildEnvelope({
		messageType = "admission_enqueue",
		operationId = "op-1",
		sourceJobId = "job-1",
		sentAt = 1,
		payload = oversizedPayload,
	})
	assertFalse(oversized.accepted, "oversized payload rejected")
	assertEqual(oversized.reason, "payload_invalid", "oversized payload reason")

	local longString = string.rep("x", 513)
	local longStringResult = NotificationMessageSchema.BuildEnvelope({
		messageType = "admission_enqueue",
		operationId = "op-1",
		sourceJobId = "job-1",
		sentAt = 1,
		payload = {
			value = longString,
		},
	})
	assertFalse(longStringResult.accepted, "long payload string rejected")
	assertEqual(longStringResult.reason, "payload_invalid", "long payload string reason")
end

do
	local envelope = {
		schemaVersion = 999,
		messageType = "admission_enqueue",
		operationId = "op-1",
		sourceJobId = "job-1",
		sentAt = 1,
		payload = {},
	}
	local invalidVersion = NotificationMessageSchema.ValidateEnvelope(envelope)
	assertFalse(invalidVersion.accepted, "invalid schema version rejected")
	assertEqual(invalidVersion.reason, "schema_version_invalid", "invalid schema version reason")
end

print("notification_message_schema: all checks passed")
