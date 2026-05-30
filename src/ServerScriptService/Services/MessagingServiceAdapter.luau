--!strict

local MessagingServiceAdapter: any = {}

export type AdapterResult = {
	accepted: boolean,
	reason: string,
	subscription: any?,
}

type Diagnostics = {
	publishAttempts: number,
	publishSucceeded: number,
	publishFailed: number,
	subscribeAttempts: number,
	subscribeSucceeded: number,
	subscribeFailed: number,
	lastTopic: string?,
	lastMessageType: string?,
	lastOperationId: string?,
	lastReason: string,
}

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return string.len(value) > 0
end

local function hasMethod(target: any, methodName: string): boolean
	if target == nil then
		return false
	end

	local ok, member = pcall(function()
		return (target :: any)[methodName]
	end)
	if not ok then
		return false
	end
	return type(member) == "function"
end

local function cloneDiagnostics(diagnostics: Diagnostics): Diagnostics
	return {
		publishAttempts = diagnostics.publishAttempts,
		publishSucceeded = diagnostics.publishSucceeded,
		publishFailed = diagnostics.publishFailed,
		subscribeAttempts = diagnostics.subscribeAttempts,
		subscribeSucceeded = diagnostics.subscribeSucceeded,
		subscribeFailed = diagnostics.subscribeFailed,
		lastTopic = diagnostics.lastTopic,
		lastMessageType = diagnostics.lastMessageType,
		lastOperationId = diagnostics.lastOperationId,
		lastReason = diagnostics.lastReason,
	}
end

local function resolveMetadata(input: any): (string?, string?)
	if type(input) ~= "table" then
		return nil, nil
	end

	local messageType = if isNonEmptyString(input.messageType) then input.messageType else nil
	local operationId = if isNonEmptyString(input.operationId) then input.operationId else nil
	local message = input.message
	if type(message) == "table" then
		if messageType == nil and isNonEmptyString(message.messageType) then
			messageType = message.messageType
		end
		if operationId == nil and isNonEmptyString(message.operationId) then
			operationId = message.operationId
		end
	end

	return messageType, operationId
end

function MessagingServiceAdapter.Create(config: any?): any
	local configAny: any = config
	local messagingService = if type(configAny) == "table" then configAny.messagingService else nil
	local diagnostics: Diagnostics = {
		publishAttempts = 0,
		publishSucceeded = 0,
		publishFailed = 0,
		subscribeAttempts = 0,
		subscribeSucceeded = 0,
		subscribeFailed = 0,
		lastTopic = nil,
		lastMessageType = nil,
		lastOperationId = nil,
		lastReason = "not_started",
	}

	local adapter: any = {}

	local function record(
		kind: string,
		accepted: boolean,
		topic: string?,
		messageType: string?,
		operationId: string?,
		reason: string
	)
		diagnostics.lastTopic = topic
		diagnostics.lastMessageType = messageType
		diagnostics.lastOperationId = operationId
		diagnostics.lastReason = reason

		if kind == "publish" then
			diagnostics.publishAttempts += 1
			if accepted then
				diagnostics.publishSucceeded += 1
			else
				diagnostics.publishFailed += 1
			end
		else
			diagnostics.subscribeAttempts += 1
			if accepted then
				diagnostics.subscribeSucceeded += 1
			else
				diagnostics.subscribeFailed += 1
			end
		end
	end

	function adapter.Publish(input: any): AdapterResult
		local inputAny: any = input
		local topic = if type(inputAny) == "table" then inputAny.topic else nil
		local message = if type(inputAny) == "table" then inputAny.message else nil
		local messageType, operationId = resolveMetadata(input)

		if not isNonEmptyString(topic) then
			record("publish", false, nil, messageType, operationId, "topic_invalid")
			return { accepted = false, reason = "topic_invalid", subscription = nil }
		end
		if message == nil then
			record("publish", false, topic, messageType, operationId, "message_invalid")
			return { accepted = false, reason = "message_invalid", subscription = nil }
		end
		if messagingService == nil or not hasMethod(messagingService, "PublishAsync") then
			record("publish", false, topic, messageType, operationId, "messaging_service_unavailable")
			return { accepted = false, reason = "messaging_service_unavailable", subscription = nil }
		end

		local publishOk = pcall(function()
			messagingService:PublishAsync(topic, message)
		end)
		if not publishOk then
			record("publish", false, topic, messageType, operationId, "publish_failed")
			return { accepted = false, reason = "publish_failed", subscription = nil }
		end

		record("publish", true, topic, messageType, operationId, "accepted")
		return { accepted = true, reason = "accepted", subscription = nil }
	end

	function adapter.Subscribe(input: any): AdapterResult
		local inputAny: any = input
		local topic = if type(inputAny) == "table" then inputAny.topic else nil
		local callback = if type(inputAny) == "table" then inputAny.callback else nil
		local messageType, operationId = resolveMetadata(input)

		if not isNonEmptyString(topic) then
			record("subscribe", false, nil, messageType, operationId, "topic_invalid")
			return { accepted = false, reason = "topic_invalid", subscription = nil }
		end
		if type(callback) ~= "function" then
			record("subscribe", false, topic, messageType, operationId, "callback_invalid")
			return { accepted = false, reason = "callback_invalid", subscription = nil }
		end
		if messagingService == nil or not hasMethod(messagingService, "SubscribeAsync") then
			record("subscribe", false, topic, messageType, operationId, "messaging_service_unavailable")
			return { accepted = false, reason = "messaging_service_unavailable", subscription = nil }
		end

		local subscribeOk, subscription = pcall(function()
			return messagingService:SubscribeAsync(topic, callback)
		end)
		if not subscribeOk then
			record("subscribe", false, topic, messageType, operationId, "subscribe_failed")
			return { accepted = false, reason = "subscribe_failed", subscription = nil }
		end

		record("subscribe", true, topic, messageType, operationId, "accepted")
		return { accepted = true, reason = "accepted", subscription = subscription }
	end

	function adapter.GetDiagnostics(): Diagnostics
		return cloneDiagnostics(diagnostics)
	end

	return adapter
end

function MessagingServiceAdapter.CreateDefault(): any?
	if game == nil or type(game.GetService) ~= "function" then
		return nil
	end

	local messagingService: any? = nil
	local messagingOk, messagingOrError = pcall(function()
		return game:GetService("MessagingService")
	end)
	if messagingOk and messagingOrError ~= nil then
		messagingService = messagingOrError
	end
	if messagingService == nil then
		return nil
	end

	return MessagingServiceAdapter.Create({
		messagingService = messagingService,
	})
end

return MessagingServiceAdapter
