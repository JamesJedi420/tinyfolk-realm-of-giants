--!strict

local MessagingServiceAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MessagingServiceAdapter"))
	else (require :: any)("./MessagingServiceAdapter")
local NotificationMessageSchema = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("NotificationMessageSchema"))
	else (require :: any)("./NotificationMessageSchema")

local NotificationSubscriptionManager: any = {}
local globalEnv: any = getfenv()

local DEFAULT_TOPIC_KEYS = {
	"admissionQueue",
	"rescueQueue",
	"realm",
	"returns",
}

type Diagnostics = {
	subscribeAttempts: number,
	subscribeSucceeded: number,
	subscribeFailed: number,
	disconnectAttempts: number,
	disconnectSucceeded: number,
	disconnectFailed: number,
	messageAttempts: number,
	messageSucceeded: number,
	messageFailed: number,
	activeTopicCount: number,
	activeTopics: { string },
	lastTopic: string?,
	lastMessageType: string?,
	lastOperationId: string?,
	lastReason: string,
}

local runtimeConfig: any = nil
local activeByTopic: { [string]: any } = {}
local diagnostics: Diagnostics

local function resetDiagnostics(reason: string)
	diagnostics = {
		subscribeAttempts = 0,
		subscribeSucceeded = 0,
		subscribeFailed = 0,
		disconnectAttempts = 0,
		disconnectSucceeded = 0,
		disconnectFailed = 0,
		messageAttempts = 0,
		messageSucceeded = 0,
		messageFailed = 0,
		activeTopicCount = 0,
		activeTopics = {},
		lastTopic = nil,
		lastMessageType = nil,
		lastOperationId = nil,
		lastReason = reason,
	}
end

resetDiagnostics("not_started")

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local clone: any = {}
	for key, child in pairs(value) do
		clone[key] = cloneTable(child)
	end
	return clone
end

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end

	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end

	return nil
end

local function resolveAdapter(): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and configAny.messagingAdapter ~= nil then
		return configAny.messagingAdapter
	end
	local adapter = getGlobalTable("_MessagingServiceAdapter_QueryAPI")
	if adapter == nil then
		adapter = MessagingServiceAdapter.CreateDefault()
	end
	return adapter
end

local function resolveReconciliationApi(): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and configAny.reconciliationApi ~= nil then
		return configAny.reconciliationApi
	end
	return getGlobalTable("_NotificationReconciliation_QueryAPI")
end

local function resolveTopic(topicKeyOrName: any): any
	local result = NotificationMessageSchema.GetTopic(topicKeyOrName)
	if type(result) == "table" and result.accepted == true and type(result.topic) == "string" then
		return {
			accepted = true,
			reason = "accepted",
			topic = result.topic,
		}
	end
	return {
		accepted = false,
		reason = if type(result) == "table" and type(result.reason) == "string" then result.reason else "topic_invalid",
		topic = nil,
	}
end

local function rebuildActiveTopics()
	local topics = {}
	for topic in pairs(activeByTopic) do
		table.insert(topics, topic)
	end
	table.sort(topics)
	diagnostics.activeTopics = topics
	diagnostics.activeTopicCount = #topics
end

local function recordSubscribe(topic: string?, accepted: boolean, reason: string)
	diagnostics.subscribeAttempts += 1
	if accepted then
		diagnostics.subscribeSucceeded += 1
	else
		diagnostics.subscribeFailed += 1
	end
	diagnostics.lastTopic = topic
	diagnostics.lastReason = reason
end

local function recordDisconnect(topic: string?, accepted: boolean, reason: string)
	diagnostics.disconnectAttempts += 1
	if accepted then
		diagnostics.disconnectSucceeded += 1
	else
		diagnostics.disconnectFailed += 1
	end
	diagnostics.lastTopic = topic
	diagnostics.lastReason = reason
end

local function recordMessage(
	topic: string,
	accepted: boolean,
	reason: string,
	messageType: string?,
	operationId: string?
)
	diagnostics.messageAttempts += 1
	if accepted then
		diagnostics.messageSucceeded += 1
	else
		diagnostics.messageFailed += 1
	end
	diagnostics.lastTopic = topic
	diagnostics.lastMessageType = messageType
	diagnostics.lastOperationId = operationId
	diagnostics.lastReason = reason
end

local function extractMessageData(rawMessage: any): any
	if type(rawMessage) == "table" and rawMessage.Data ~= nil then
		return rawMessage.Data
	end
	return rawMessage
end

local function decodeMessage(rawData: any): any
	if type(rawData) == "table" then
		return {
			accepted = true,
			reason = "accepted",
			envelope = rawData,
		}
	end

	if type(rawData) ~= "string" then
		return {
			accepted = false,
			reason = "message_invalid",
			envelope = nil,
		}
	end

	local configAny: any = runtimeConfig
	local decode = if type(configAny) == "table" then configAny.decode else nil
	if type(decode) ~= "function" then
		return {
			accepted = false,
			reason = "message_decode_unavailable",
			envelope = nil,
		}
	end

	local ok, decoded = pcall(decode, rawData)
	if not ok or type(decoded) ~= "table" then
		return {
			accepted = false,
			reason = "message_decode_failed",
			envelope = nil,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		envelope = decoded,
	}
end

local function handleTopicMessage(topic: string, rawMessage: any)
	local decoded = decodeMessage(extractMessageData(rawMessage))
	if decoded.accepted ~= true then
		recordMessage(topic, false, decoded.reason, nil, nil)
		return
	end

	local envelope = decoded.envelope
	local validation = NotificationMessageSchema.ValidateEnvelope(envelope)
	local messageType = if type(envelope) == "table" then envelope.messageType else nil
	local operationId = if type(envelope) == "table" then envelope.operationId else nil
	if validation.accepted ~= true then
		local reason = if type(validation.reason) == "string" then validation.reason else "envelope_invalid"
		recordMessage(topic, false, reason, messageType, operationId)
		return
	end

	local reconciliationApi = resolveReconciliationApi()
	if type(reconciliationApi) ~= "table" or type((reconciliationApi :: any).HandleNotification) ~= "function" then
		recordMessage(topic, false, "reconciliation_api_unavailable", messageType, operationId)
		return
	end

	local ok, result = pcall(function()
		return (reconciliationApi :: any).HandleNotification(envelope)
	end)
	if not ok or type(result) ~= "table" then
		recordMessage(topic, false, "reconciliation_failed", messageType, operationId)
		return
	end
	if result.accepted ~= true then
		local reason = if type(result.reason) == "string" and result.reason ~= ""
			then result.reason
			else "reconciliation_rejected"
		recordMessage(topic, false, reason, messageType, operationId)
		return
	end

	recordMessage(topic, true, "accepted", messageType, operationId)
end

function NotificationSubscriptionManager.Start(config: any?): any
	NotificationSubscriptionManager.DisconnectAll()
	runtimeConfig = if type(config) == "table" then config else {}
	resetDiagnostics("started")
	return {
		ok = true,
		reason = nil,
	}
end

function NotificationSubscriptionManager.SubscribeTopic(topicKeyOrName: any): any
	local topicResult = resolveTopic(topicKeyOrName)
	if topicResult.accepted ~= true then
		recordSubscribe(nil, false, topicResult.reason)
		return {
			accepted = false,
			reason = topicResult.reason,
			topic = nil,
		}
	end

	local topic = topicResult.topic
	if activeByTopic[topic] ~= nil then
		recordSubscribe(topic, true, "already_subscribed")
		return {
			accepted = true,
			reason = "already_subscribed",
			topic = topic,
		}
	end

	local adapter = resolveAdapter()
	if type(adapter) ~= "table" or type((adapter :: any).Subscribe) ~= "function" then
		recordSubscribe(topic, false, "messaging_adapter_unavailable")
		return {
			accepted = false,
			reason = "messaging_adapter_unavailable",
			topic = topic,
		}
	end

	local subscribeResult = (adapter :: any).Subscribe({
		topic = topic,
		messageType = "subscription_init",
		operationId = "subscription_" .. topic,
		callback = function(rawMessage: any)
			handleTopicMessage(topic, rawMessage)
		end,
	})
	if type(subscribeResult) ~= "table" then
		recordSubscribe(topic, false, "subscribe_failed")
		return {
			accepted = false,
			reason = "subscribe_failed",
			topic = topic,
		}
	end
	if subscribeResult.accepted ~= true then
		local reason = if type(subscribeResult.reason) == "string" and subscribeResult.reason ~= ""
			then subscribeResult.reason
			else "subscribe_failed"
		recordSubscribe(topic, false, reason)
		return {
			accepted = false,
			reason = reason,
			topic = topic,
		}
	end

	activeByTopic[topic] = subscribeResult.subscription or true
	rebuildActiveTopics()
	recordSubscribe(topic, true, "accepted")
	return {
		accepted = true,
		reason = "accepted",
		topic = topic,
	}
end

function NotificationSubscriptionManager.SubscribeDefaults(): any
	local results = {}
	local accepted = true
	for _, topicKey in ipairs(DEFAULT_TOPIC_KEYS) do
		local result = NotificationSubscriptionManager.SubscribeTopic(topicKey)
		table.insert(results, result)
		if type(result) ~= "table" or result.accepted ~= true then
			accepted = false
		end
	end
	return {
		accepted = accepted,
		reason = if accepted then "accepted" else "subscribe_defaults_partial_failure",
		results = results,
	}
end

function NotificationSubscriptionManager.DisconnectTopic(topicKeyOrName: any): any
	local topicResult = resolveTopic(topicKeyOrName)
	if topicResult.accepted ~= true then
		recordDisconnect(nil, false, topicResult.reason)
		return {
			accepted = false,
			reason = topicResult.reason,
			topic = nil,
		}
	end

	local topic = topicResult.topic
	local subscription = activeByTopic[topic]
	if subscription == nil then
		recordDisconnect(topic, false, "subscription_not_found")
		return {
			accepted = false,
			reason = "subscription_not_found",
			topic = topic,
		}
	end

	local disconnectOk = true
	if type(subscription) == "table" and type((subscription :: any).Disconnect) == "function" then
		disconnectOk = pcall(function()
			(subscription :: any):Disconnect()
		end)
	end
	activeByTopic[topic] = nil
	rebuildActiveTopics()

	if not disconnectOk then
		recordDisconnect(topic, false, "disconnect_failed")
		return {
			accepted = false,
			reason = "disconnect_failed",
			topic = topic,
		}
	end

	recordDisconnect(topic, true, "accepted")
	return {
		accepted = true,
		reason = "accepted",
		topic = topic,
	}
end

function NotificationSubscriptionManager.DisconnectAll(): any
	local results = {}
	local topics = {}
	for topic in pairs(activeByTopic) do
		table.insert(topics, topic)
	end
	table.sort(topics)
	for _, topic in ipairs(topics) do
		table.insert(results, NotificationSubscriptionManager.DisconnectTopic(topic))
	end
	rebuildActiveTopics()
	return {
		accepted = true,
		reason = "accepted",
		results = results,
	}
end

function NotificationSubscriptionManager.GetDiagnostics(): Diagnostics
	rebuildActiveTopics()
	return cloneTable(diagnostics)
end

function NotificationSubscriptionManager.ConfigureForTests(config: any): any
	return NotificationSubscriptionManager.Start(config)
end

function NotificationSubscriptionManager.ResetForTests()
	NotificationSubscriptionManager.DisconnectAll()
	activeByTopic = {}
	runtimeConfig = nil
	resetDiagnostics("reset")
end

NotificationSubscriptionManager.Start({})

globalEnv._NotificationSubscriptionManager_QueryAPI = {
	Start = function(config: any?): any
		return NotificationSubscriptionManager.Start(config)
	end,
	SubscribeTopic = function(topicKeyOrName: any): any
		return NotificationSubscriptionManager.SubscribeTopic(topicKeyOrName)
	end,
	SubscribeDefaults = function(): any
		return NotificationSubscriptionManager.SubscribeDefaults()
	end,
	DisconnectTopic = function(topicKeyOrName: any): any
		return NotificationSubscriptionManager.DisconnectTopic(topicKeyOrName)
	end,
	DisconnectAll = function(): any
		return NotificationSubscriptionManager.DisconnectAll()
	end,
	GetDiagnostics = function(): Diagnostics
		return NotificationSubscriptionManager.GetDiagnostics()
	end,
	ConfigureForTests = function(config: any): any
		return NotificationSubscriptionManager.ConfigureForTests(config)
	end,
	ResetForTests = function()
		NotificationSubscriptionManager.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_NotificationSubscriptionManager_QueryAPI", globalEnv._NotificationSubscriptionManager_QueryAPI)
end

return NotificationSubscriptionManager
