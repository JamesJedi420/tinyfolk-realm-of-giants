--!strict

local MessagingServiceAdapter = require("../src/ServerScriptService/Services/MessagingServiceAdapter")

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

local function makeMessagingService(config: any?)
	local configAny: any = config
	local publishes: { any } = {}
	local subscriptions: { any } = {}
	local service: any = {}

	service.PublishAsync = function(_self: any, topic: string, message: any)
		if type(configAny) == "table" and configAny.publishThrows == true then
			error("publish_failed")
		end
		table.insert(publishes, {
			topic = topic,
			message = message,
		})
	end

	service.SubscribeAsync = function(_self: any, topic: string, callback: (any) -> ())
		if type(configAny) == "table" and configAny.subscribeThrows == true then
			error("subscribe_failed")
		end
		local subscription = {
			topic = topic,
			callback = callback,
			Disconnect = function() end,
		}
		table.insert(subscriptions, subscription)
		return subscription
	end

	return service, publishes, subscriptions
end

local unavailableDefault = MessagingServiceAdapter.CreateDefault()
assertEqual(unavailableDefault, nil, "default adapter unavailable outside runtime")

do
	local messagingService, publishes, subscriptions = makeMessagingService()
	local adapter = MessagingServiceAdapter.Create({
		messagingService = messagingService,
	})

	local published = adapter.Publish({
		topic = "tin_topic",
		message = "encoded",
		messageType = "admission_enqueue",
		operationId = "op-1",
	})
	assertTrue(published.accepted, "publish accepted")
	assertEqual(publishes[1].topic, "tin_topic", "publish topic")
	assertEqual(publishes[1].message, "encoded", "publish message")

	local subscribed = adapter.Subscribe({
		topic = "tin_topic",
		callback = function(_message: any) end,
		messageType = "subscription_init",
		operationId = "op-sub",
	})
	assertTrue(subscribed.accepted, "subscribe accepted")
	assertEqual(subscribed.reason, "accepted", "subscribe reason")
	assertTrue(type(subscribed.subscription) == "table", "subscribe returns subscription")
	assertEqual(subscriptions[1].topic, "tin_topic", "subscribe topic")

	local diagnostics = adapter.GetDiagnostics()
	assertEqual(diagnostics.publishAttempts, 1, "diagnostics publish attempts")
	assertEqual(diagnostics.publishSucceeded, 1, "diagnostics publish success")
	assertEqual(diagnostics.publishFailed, 0, "diagnostics publish failed")
	assertEqual(diagnostics.publishRateLimited, 0, "diagnostics publish rate limited")
	assertEqual(diagnostics.publishCoalesced, 0, "diagnostics publish coalesced")
	assertEqual(diagnostics.subscribeAttempts, 1, "diagnostics subscribe attempts")
	assertEqual(diagnostics.subscribeSucceeded, 1, "diagnostics subscribe success")
	assertEqual(diagnostics.subscribeFailed, 0, "diagnostics subscribe failed")
	assertEqual(diagnostics.lastTopic, "tin_topic", "diagnostics last topic")
	assertEqual(diagnostics.lastMessageType, "subscription_init", "diagnostics last message type")
	assertEqual(diagnostics.lastOperationId, "op-sub", "diagnostics last operation id")
	assertEqual(diagnostics.lastReason, "accepted", "diagnostics last reason")
end

do
	local messagingService, publishes = makeMessagingService()
	local guardCalls: { any } = {}
	local adapter = MessagingServiceAdapter.Create({
		messagingService = messagingService,
		rateGuard = {
			EvaluatePublish = function(input: any)
				table.insert(guardCalls, input)
				return {
					accepted = true,
					reason = "accepted",
					action = "publish",
				}
			end,
		},
	})

	local published = adapter.Publish({
		topic = "tin_topic",
		message = "encoded",
		messageType = "RealmStatusChanged",
		operationId = "op-guard-accepted",
	})
	assertTrue(published.accepted, "guard accepted publish")
	assertEqual(published.reason, "accepted", "guard accepted reason")
	assertEqual(#guardCalls, 1, "guard called before publish")
	assertEqual(#publishes, 1, "guard accepted calls platform publish")
end

do
	local messagingService, publishes = makeMessagingService()
	local adapter = MessagingServiceAdapter.Create({
		messagingService = messagingService,
		rateGuard = {
			EvaluatePublish = function(_input: any)
				return {
					accepted = false,
					reason = "rate_limited",
					action = "drop",
				}
			end,
		},
	})

	local limited = adapter.Publish({
		topic = "tin_topic",
		message = "encoded",
		messageType = "admission_enqueue",
		operationId = "op-limited",
	})
	assertFalse(limited.accepted, "rate limited rejected")
	assertEqual(limited.reason, "rate_limited", "rate limited reason")
	assertEqual(#publishes, 0, "rate limited skips platform publish")

	local diagnostics = adapter.GetDiagnostics()
	assertEqual(diagnostics.publishAttempts, 1, "rate limited diagnostics attempts")
	assertEqual(diagnostics.publishFailed, 1, "rate limited diagnostics failed")
	assertEqual(diagnostics.publishRateLimited, 1, "rate limited diagnostics counter")
	assertEqual(diagnostics.lastRateGuardReason, "rate_limited", "rate limited diagnostics reason")
end

do
	local messagingService, publishes = makeMessagingService()
	local adapter = MessagingServiceAdapter.Create({
		messagingService = messagingService,
		rateGuard = {
			EvaluatePublish = function(_input: any)
				return {
					accepted = true,
					reason = "coalesced",
					action = "coalesce",
				}
			end,
		},
	})

	local coalesced = adapter.Publish({
		topic = "tin_topic",
		message = "encoded",
		messageType = "RealmStatusChanged",
		operationId = "op-coalesced",
	})
	assertTrue(coalesced.accepted, "coalesced accepted")
	assertEqual(coalesced.reason, "coalesced", "coalesced reason")
	assertEqual(#publishes, 0, "coalesced skips platform publish")

	local diagnostics = adapter.GetDiagnostics()
	assertEqual(diagnostics.publishAttempts, 1, "coalesced diagnostics attempts")
	assertEqual(diagnostics.publishSucceeded, 1, "coalesced diagnostics success")
	assertEqual(diagnostics.publishCoalesced, 1, "coalesced diagnostics counter")
	assertEqual(diagnostics.lastRateGuardReason, "coalesced", "coalesced diagnostics reason")
end

do
	local messagingService, publishes = makeMessagingService()
	local adapter = MessagingServiceAdapter.Create({
		messagingService = messagingService,
		rateGuard = {
			EvaluatePublish = function(_input: any)
				error("guard failed")
			end,
		},
	})

	local failed = adapter.Publish({
		topic = "tin_topic",
		message = "encoded",
		messageType = "RealmStatusChanged",
		operationId = "op-guard-failed",
	})
	assertFalse(failed.accepted, "guard failure rejected")
	assertEqual(failed.reason, "rate_guard_failed", "guard failure reason")
	assertEqual(#publishes, 0, "guard failure skips platform publish")
end

do
	local adapter = MessagingServiceAdapter.Create()

	local invalidTopic = adapter.Publish({
		topic = "",
		message = "encoded",
	})
	assertFalse(invalidTopic.accepted, "invalid publish topic rejected")
	assertEqual(invalidTopic.reason, "topic_invalid", "invalid publish topic reason")

	local invalidMessage = adapter.Publish({
		topic = "tin_topic",
		message = nil,
	})
	assertFalse(invalidMessage.accepted, "invalid publish message rejected")
	assertEqual(invalidMessage.reason, "message_invalid", "invalid publish message reason")

	local unavailable = adapter.Publish({
		topic = "tin_topic",
		message = "encoded",
		messageType = "admission_enqueue",
		operationId = "op-unavailable",
	})
	assertFalse(unavailable.accepted, "unavailable publish rejected")
	assertEqual(unavailable.reason, "messaging_service_unavailable", "unavailable publish reason")

	local invalidCallback = adapter.Subscribe({
		topic = "tin_topic",
		callback = nil,
	})
	assertFalse(invalidCallback.accepted, "invalid callback rejected")
	assertEqual(invalidCallback.reason, "callback_invalid", "invalid callback reason")
end

do
	local publishThrowingService = makeMessagingService({
		publishThrows = true,
	})
	local publishAdapter = MessagingServiceAdapter.Create({
		messagingService = publishThrowingService,
	})
	local publishFailed = publishAdapter.Publish({
		topic = "tin_topic",
		message = "encoded",
	})
	assertFalse(publishFailed.accepted, "publish throw rejected")
	assertEqual(publishFailed.reason, "publish_failed", "publish throw reason")

	local subscribeThrowingService = makeMessagingService({
		subscribeThrows = true,
	})
	local subscribeAdapter = MessagingServiceAdapter.Create({
		messagingService = subscribeThrowingService,
	})
	local subscribeFailed = subscribeAdapter.Subscribe({
		topic = "tin_topic",
		callback = function(_message: any) end,
	})
	assertFalse(subscribeFailed.accepted, "subscribe throw rejected")
	assertEqual(subscribeFailed.reason, "subscribe_failed", "subscribe throw reason")

	local diagnostics = subscribeAdapter.GetDiagnostics()
	assertEqual(diagnostics.subscribeAttempts, 1, "subscribe failure diagnostics attempts")
	assertEqual(diagnostics.subscribeFailed, 1, "subscribe failure diagnostics failed")
	assertEqual(diagnostics.lastReason, "subscribe_failed", "subscribe failure diagnostics reason")
end

print("messaging_service_adapter: all checks passed")
