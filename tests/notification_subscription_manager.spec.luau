--!strict

local NotificationMessageSchema = require("../src/ServerScriptService/Services/NotificationMessageSchema")
local NotificationSubscriptionManager = require("../src/ServerScriptService/Services/NotificationSubscriptionManager")

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

local function buildEnvelope(messageType: string, operationId: string, payload: any?): any
	local result = NotificationMessageSchema.BuildEnvelope({
		messageType = messageType,
		operationId = operationId,
		sourceJobId = "job-test",
		sentAt = 10,
		payload = payload or {},
	})
	assertTrue(result.accepted, "test envelope accepted")
	return result.envelope
end

local function makeAdapter(config: any?): (any, { any }, { string })
	local configAny: any = config
	local subscribeCalls: { any } = {}
	local disconnects: { string } = {}
	local adapter: any = {}
	adapter.Subscribe = function(input: any): any
		table.insert(subscribeCalls, input)
		if type(configAny) == "table" and configAny.reject == true then
			return {
				accepted = false,
				reason = "subscribe_failed",
			}
		end
		local topic = input.topic
		return {
			accepted = true,
			reason = "accepted",
			subscription = {
				Disconnect = function(_self: any)
					table.insert(disconnects, topic)
					if type(configAny) == "table" and configAny.disconnectThrows == true then
						error("disconnect_failed")
					end
				end,
			},
		}
	end
	return adapter, subscribeCalls, disconnects
end

local function configure(config: any)
	NotificationSubscriptionManager.ResetForTests()
	local result = NotificationSubscriptionManager.ConfigureForTests(config)
	assertTrue(result.ok, "configure accepted")
end

do
	local adapter, subscribeCalls = makeAdapter()
	configure({
		messagingAdapter = adapter,
		reconciliationApi = {
			HandleNotification = function(_envelope: any): any
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
	})

	local first = NotificationSubscriptionManager.SubscribeDefaults()
	assertTrue(first.accepted, "default subscriptions accepted")
	assertEqual(#subscribeCalls, 5, "default subscribes once per topic")
	assertEqual(subscribeCalls[1].topic, "tin_queue_admission_v1", "default first topic")
	assertEqual(subscribeCalls[2].topic, "tin_queue_rescue_v1", "default second topic")
	assertEqual(subscribeCalls[3].topic, "tin_realm_v1", "default third topic")
	assertEqual(subscribeCalls[4].topic, "tin_announcement_v1", "default fourth topic")
	assertEqual(subscribeCalls[5].topic, "tin_return_v1", "default fifth topic")

	local second = NotificationSubscriptionManager.SubscribeDefaults()
	assertTrue(second.accepted, "repeat defaults accepted")
	assertEqual(#subscribeCalls, 5, "repeat default subscriptions do not duplicate")
	assertEqual(second.results[1].reason, "already_subscribed", "repeat reason")

	local diagnostics = NotificationSubscriptionManager.GetDiagnostics()
	assertEqual(diagnostics.activeTopicCount, 5, "diagnostics active count")
	assertEqual(diagnostics.subscribeSucceeded, 10, "diagnostics counts idempotent successes")
end

do
	local handled: { any } = {}
	local adapter, subscribeCalls = makeAdapter()
	configure({
		messagingAdapter = adapter,
		decode = function(encoded: string): any
			assertEqual(encoded, "encoded-envelope", "decode receives encoded payload")
			return buildEnvelope("admission_enqueue", "op-sub-1", {
				partyId = "party-1",
			})
		end,
		reconciliationApi = {
			HandleNotification = function(envelope: any): any
				table.insert(handled, envelope)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
	})

	local subscribed = NotificationSubscriptionManager.SubscribeTopic("admissionQueue")
	assertTrue(subscribed.accepted, "single topic subscribed")
	subscribeCalls[1].callback({
		Data = "encoded-envelope",
	})
	assertEqual(#handled, 1, "encoded callback routed")
	assertEqual(handled[1].operationId, "op-sub-1", "encoded callback envelope")

	local diagnostics = NotificationSubscriptionManager.GetDiagnostics()
	assertEqual(diagnostics.messageAttempts, 1, "message diagnostics attempt")
	assertEqual(diagnostics.messageSucceeded, 1, "message diagnostics success")
	assertEqual(diagnostics.lastMessageType, "admission_enqueue", "message diagnostics type")
	assertEqual(diagnostics.lastOperationId, "op-sub-1", "message diagnostics operation")
end

do
	local handled: { any } = {}
	local adapter, subscribeCalls = makeAdapter()
	configure({
		messagingAdapter = adapter,
		reconciliationApi = {
			HandleNotification = function(envelope: any): any
				table.insert(handled, envelope)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
	})

	assertTrue(NotificationSubscriptionManager.SubscribeTopic("rescueQueue").accepted, "table payload topic subscribed")
	subscribeCalls[1].callback(buildEnvelope("rescue_queue_published", "op-table", {
		queueEntryId = "queue-1",
	}))
	assertEqual(#handled, 1, "table payload routed")
	assertEqual(handled[1].messageType, "rescue_queue_published", "table payload message type")
end

do
	local adapter, subscribeCalls = makeAdapter()
	configure({
		messagingAdapter = adapter,
		decode = function(_encoded: string): any
			error("decode failed")
		end,
		reconciliationApi = {
			HandleNotification = function(_envelope: any): any
				error("should not route decode failures")
			end,
		},
	})

	assertTrue(
		NotificationSubscriptionManager.SubscribeTopic("admissionQueue").accepted,
		"decode failure topic subscribed"
	)
	subscribeCalls[1].callback({
		Data = "bad",
	})
	local diagnostics = NotificationSubscriptionManager.GetDiagnostics()
	assertEqual(diagnostics.messageFailed, 1, "decode failure counted")
	assertEqual(diagnostics.lastReason, "message_decode_failed", "decode failure reason")
end

do
	local adapter, subscribeCalls = makeAdapter()
	configure({
		messagingAdapter = adapter,
		reconciliationApi = {
			HandleNotification = function(_envelope: any): any
				error("should not route invalid envelope")
			end,
		},
	})

	assertTrue(
		NotificationSubscriptionManager.SubscribeTopic("admissionQueue").accepted,
		"invalid envelope topic subscribed"
	)
	subscribeCalls[1].callback({
		Data = {
			schemaVersion = 1,
			messageType = "admission_enqueue",
			operationId = "op-invalid",
			sourceJobId = "",
			sentAt = math.huge,
			payload = {},
		},
	})
	local diagnostics = NotificationSubscriptionManager.GetDiagnostics()
	assertEqual(diagnostics.messageFailed, 1, "invalid envelope counted")
	assertEqual(diagnostics.lastReason, "sent_at_invalid", "invalid envelope reason")
end

do
	local adapter, subscribeCalls = makeAdapter()
	configure({
		messagingAdapter = adapter,
		reconciliationApi = {
			HandleNotification = function(_envelope: any): any
				return {
					accepted = false,
					reason = "message_type_unhandled",
				}
			end,
		},
	})

	assertTrue(NotificationSubscriptionManager.SubscribeTopic("realm").accepted, "rejection topic subscribed")
	subscribeCalls[1].callback(buildEnvelope("realm_status_changed", "op-reject", {}))
	local diagnostics = NotificationSubscriptionManager.GetDiagnostics()
	assertEqual(diagnostics.messageFailed, 1, "reconciliation rejection counted")
	assertEqual(diagnostics.lastReason, "message_type_unhandled", "reconciliation rejection reason")
end

do
	local adapter = makeAdapter({
		reject = true,
	})
	configure({
		messagingAdapter = adapter,
	})

	local rejected = NotificationSubscriptionManager.SubscribeTopic("admissionQueue")
	assertFalse(rejected.accepted, "adapter rejection rejected")
	assertEqual(rejected.reason, "subscribe_failed", "adapter rejection reason")
	local diagnostics = NotificationSubscriptionManager.GetDiagnostics()
	assertEqual(diagnostics.subscribeFailed, 1, "adapter rejection diagnostics")
end

do
	configure({})
	local invalid = NotificationSubscriptionManager.SubscribeTopic("")
	assertFalse(invalid.accepted, "invalid topic rejected")
	assertEqual(invalid.reason, "topic_invalid", "invalid topic reason")
end

do
	local adapter, _subscribeCalls, disconnects = makeAdapter()
	configure({
		messagingAdapter = adapter,
	})

	assertTrue(NotificationSubscriptionManager.SubscribeTopic("admissionQueue").accepted, "disconnect setup one")
	assertTrue(NotificationSubscriptionManager.SubscribeTopic("rescueQueue").accepted, "disconnect setup two")
	local disconnectOne = NotificationSubscriptionManager.DisconnectTopic("admissionQueue")
	assertTrue(disconnectOne.accepted, "disconnect one accepted")
	assertEqual(disconnects[1], "tin_queue_admission_v1", "disconnect one topic")
	assertEqual(NotificationSubscriptionManager.GetDiagnostics().activeTopicCount, 1, "disconnect one active count")

	local missing = NotificationSubscriptionManager.DisconnectTopic("admissionQueue")
	assertFalse(missing.accepted, "missing disconnect rejected")
	assertEqual(missing.reason, "subscription_not_found", "missing disconnect reason")

	local disconnectAll = NotificationSubscriptionManager.DisconnectAll()
	assertTrue(disconnectAll.accepted, "disconnect all accepted")
	assertEqual(disconnects[2], "tin_queue_rescue_v1", "disconnect all topic")
	assertEqual(NotificationSubscriptionManager.GetDiagnostics().activeTopicCount, 0, "disconnect all active count")
end

do
	local adapter = makeAdapter({
		disconnectThrows = true,
	})
	configure({
		messagingAdapter = adapter,
	})

	assertTrue(NotificationSubscriptionManager.SubscribeTopic("admissionQueue").accepted, "disconnect throw setup")
	local failed = NotificationSubscriptionManager.DisconnectTopic("admissionQueue")
	assertFalse(failed.accepted, "disconnect throw rejected")
	assertEqual(failed.reason, "disconnect_failed", "disconnect throw reason")
	assertEqual(NotificationSubscriptionManager.GetDiagnostics().disconnectFailed, 1, "disconnect throw diagnostics")
end

do
	local api: any = rawget(getfenv(), "_NotificationSubscriptionManager_QueryAPI")
	assertTrue(type(api) == "table", "query api exists")
	assertTrue(type(api.SubscribeDefaults) == "function", "query api exposes SubscribeDefaults")
	assertTrue(type(api.DisconnectAll) == "function", "query api exposes DisconnectAll")
	assertTrue(type(api.GetDiagnostics) == "function", "query api exposes diagnostics")
end

NotificationSubscriptionManager.ResetForTests()

print("notification_subscription_manager: all checks passed")
