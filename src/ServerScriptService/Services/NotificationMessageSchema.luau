--!strict

local NotificationMessageSchema: any = {}

NotificationMessageSchema.SCHEMA_VERSION = 1

NotificationMessageSchema.Topics = {
	admissionQueue = "tin_queue_admission_v1",
	rescueQueue = "tin_queue_rescue_v1",
	realm = "tin_realm_v1",
	systemAnnouncement = "tin_announcement_v1",
	hub = "tin_hub_v1",
	returns = "tin_return_v1",
	custody = "tin_custody_v1",
	admin = "tin_admin_v1",
}

local MAX_TOPIC_LENGTH = 80
local MAX_MESSAGE_TYPE_LENGTH = 96
local MAX_OPERATION_ID_LENGTH = 160
local MAX_SOURCE_JOB_ID_LENGTH = 160
local MAX_STRING_LENGTH = 512
local MAX_PAYLOAD_KEYS = 64
local MAX_PAYLOAD_DEPTH = 4

local function isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isNonEmptyString(value: any, maxLength: number): boolean
	return type(value) == "string" and value ~= "" and string.len(value) <= maxLength
end

local function cloneCompactValue(value: any, depth: number): (boolean, string, any?)
	local valueType = type(value)
	if value == nil then
		return true, "accepted", nil
	end
	if valueType == "string" then
		if string.len(value) > MAX_STRING_LENGTH then
			return false, "payload_invalid", nil
		end
		return true, "accepted", value
	end
	if valueType == "number" then
		if not isFiniteNumber(value) then
			return false, "payload_invalid", nil
		end
		return true, "accepted", value
	end
	if valueType == "boolean" then
		return true, "accepted", value
	end
	if valueType ~= "table" then
		return false, "payload_invalid", nil
	end
	if depth >= MAX_PAYLOAD_DEPTH then
		return false, "payload_invalid", nil
	end

	local clone: any = {}
	local count = 0
	for key, child in pairs(value) do
		local keyType = type(key)
		if keyType ~= "string" and keyType ~= "number" then
			return false, "payload_invalid", nil
		end
		if keyType == "string" and string.len(key) > MAX_STRING_LENGTH then
			return false, "payload_invalid", nil
		end

		count += 1
		if count > MAX_PAYLOAD_KEYS then
			return false, "payload_invalid", nil
		end

		local childAccepted, childReason, childClone = cloneCompactValue(child, depth + 1)
		if not childAccepted then
			return false, childReason, nil
		end
		clone[key] = childClone
	end

	return true, "accepted", clone
end

local function cloneEnvelopePayload(payload: any): (boolean, string, any?)
	if type(payload) ~= "table" then
		return false, "payload_invalid", nil
	end
	return cloneCompactValue(payload, 0)
end

function NotificationMessageSchema.GetTopic(topicKey: any): any
	if not isNonEmptyString(topicKey, MAX_TOPIC_LENGTH) then
		return {
			accepted = false,
			reason = "topic_invalid",
			topic = nil,
		}
	end

	local topics: any = NotificationMessageSchema.Topics
	local topic = topics[topicKey]
	if topic == nil then
		topic = topicKey
	end
	if not isNonEmptyString(topic, MAX_TOPIC_LENGTH) then
		return {
			accepted = false,
			reason = "topic_invalid",
			topic = nil,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		topic = topic,
	}
end

function NotificationMessageSchema.NormalizePayload(payload: any): any
	local accepted, reason, normalized = cloneEnvelopePayload(payload)
	return {
		accepted = accepted,
		reason = reason,
		payload = normalized,
	}
end

function NotificationMessageSchema.ValidateEnvelope(envelope: any): any
	if type(envelope) ~= "table" then
		return {
			accepted = false,
			reason = "envelope_invalid",
		}
	end
	if envelope.schemaVersion ~= NotificationMessageSchema.SCHEMA_VERSION then
		return {
			accepted = false,
			reason = "schema_version_invalid",
		}
	end
	if not isNonEmptyString(envelope.messageType, MAX_MESSAGE_TYPE_LENGTH) then
		return {
			accepted = false,
			reason = "message_type_invalid",
		}
	end
	if not isNonEmptyString(envelope.operationId, MAX_OPERATION_ID_LENGTH) then
		return {
			accepted = false,
			reason = "operation_id_invalid",
		}
	end
	if type(envelope.sourceJobId) ~= "string" or string.len(envelope.sourceJobId) > MAX_SOURCE_JOB_ID_LENGTH then
		return {
			accepted = false,
			reason = "source_job_id_invalid",
		}
	end
	if type(envelope.sentAt) ~= "number" or not isFiniteNumber(envelope.sentAt) then
		return {
			accepted = false,
			reason = "sent_at_invalid",
		}
	end

	local payloadResult = NotificationMessageSchema.NormalizePayload(envelope.payload)
	if payloadResult.accepted ~= true then
		return {
			accepted = false,
			reason = payloadResult.reason,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
	}
end

function NotificationMessageSchema.BuildEnvelope(input: any): any
	local inputAny: any = input
	if type(inputAny) ~= "table" then
		return {
			accepted = false,
			reason = "envelope_invalid",
			envelope = nil,
		}
	end

	local messageType = inputAny.messageType
	if not isNonEmptyString(messageType, MAX_MESSAGE_TYPE_LENGTH) then
		return {
			accepted = false,
			reason = "message_type_invalid",
			envelope = nil,
		}
	end

	local operationId = inputAny.operationId
	if not isNonEmptyString(operationId, MAX_OPERATION_ID_LENGTH) then
		return {
			accepted = false,
			reason = "operation_id_invalid",
			envelope = nil,
		}
	end

	local sourceJobId = inputAny.sourceJobId
	if sourceJobId == nil then
		sourceJobId = ""
	end
	if type(sourceJobId) ~= "string" or string.len(sourceJobId) > MAX_SOURCE_JOB_ID_LENGTH then
		return {
			accepted = false,
			reason = "source_job_id_invalid",
			envelope = nil,
		}
	end

	local sentAt = inputAny.sentAt
	if type(sentAt) ~= "number" or not isFiniteNumber(sentAt) then
		return {
			accepted = false,
			reason = "sent_at_invalid",
			envelope = nil,
		}
	end

	local payloadResult = NotificationMessageSchema.NormalizePayload(inputAny.payload)
	if payloadResult.accepted ~= true then
		return {
			accepted = false,
			reason = payloadResult.reason,
			envelope = nil,
		}
	end

	local envelope = {
		schemaVersion = NotificationMessageSchema.SCHEMA_VERSION,
		messageType = messageType,
		operationId = operationId,
		sourceJobId = sourceJobId,
		sentAt = sentAt,
		payload = payloadResult.payload,
	}

	return {
		accepted = true,
		reason = "accepted",
		envelope = envelope,
	}
end

return NotificationMessageSchema
