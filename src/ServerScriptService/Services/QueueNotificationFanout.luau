--!strict

local MessagingServiceAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MessagingServiceAdapter"))
	else (require :: any)("./MessagingServiceAdapter")
local NotificationMessageSchema = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("NotificationMessageSchema"))
	else (require :: any)("./NotificationMessageSchema")

local QueueNotificationFanout: any = {}
local globalEnv: any = getfenv()

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

local function sanitizeEventName(eventName: any): string?
	if type(eventName) ~= "string" then
		return nil
	end
	if eventName == "" then
		return nil
	end
	return eventName
end

local function sanitizePayload(payload: any): any
	if type(payload) == "table" then
		return payload
	end
	return {}
end

local function resolveOperationId(messageType: string, payload: any, sentAt: number): string
	if type(payload) == "table" and type(payload.operationId) == "string" and payload.operationId ~= "" then
		return payload.operationId
	end
	return string.format("notification_%s_%d", messageType, math.floor(sentAt * 1000))
end

local function resolveDefaultSourceJobId(): string
	if game == nil then
		return ""
	end

	local ok, jobId = pcall(function()
		return (game :: any).JobId
	end)
	if ok and type(jobId) == "string" then
		return jobId
	end
	return ""
end

function QueueNotificationFanout.Create(config: any?): any?
	local configAny: any = config
	local messagingService = if type(configAny) == "table" then configAny.messagingService else nil
	local messagingAdapter = if type(configAny) == "table" then configAny.messagingAdapter else nil
	local encode = if type(configAny) == "table" then configAny.encode else nil
	local nowFn = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
	local sourceJobId = if type(configAny) == "table" and type(configAny.sourceJobId) == "string"
		then configAny.sourceJobId
		else ""

	if messagingAdapter == nil and messagingService ~= nil then
		messagingAdapter = MessagingServiceAdapter.Create({
			messagingService = messagingService,
		})
	end
	if type(encode) ~= "function" then
		return nil
	end
	if type(messagingAdapter) ~= "table" or type(messagingAdapter.Publish) ~= "function" then
		return nil
	end

	local fanout: any = {}

	local function resolveSentAt(): number
		if type(nowFn) == "function" then
			local now = nowFn()
			if type(now) == "number" and now == now and now ~= math.huge and now ~= -math.huge then
				return now
			end
		end
		return os.clock()
	end

	local function publish(topicKey: string, eventName: any, payload: any): any
		local resolvedEventName = sanitizeEventName(eventName)
		if resolvedEventName == nil then
			return {
				accepted = false,
				reason = "event_name_invalid",
			}
		end

		local topicResult = NotificationMessageSchema.GetTopic(topicKey)
		if topicResult.accepted ~= true then
			return {
				accepted = false,
				reason = if type(topicResult.reason) == "string" then topicResult.reason else "topic_invalid",
			}
		end

		local sentAt = resolveSentAt()
		local operationId = resolveOperationId(resolvedEventName, payload, sentAt)
		local envelopeResult = NotificationMessageSchema.BuildEnvelope({
			messageType = resolvedEventName,
			operationId = operationId,
			sourceJobId = sourceJobId,
			sentAt = sentAt,
			payload = sanitizePayload(payload),
		})
		if envelopeResult.accepted ~= true then
			return {
				accepted = false,
				reason = if type(envelopeResult.reason) == "string" then envelopeResult.reason else "message_invalid",
			}
		end

		local encodeOk, encodedOrError = pcall(encode, envelopeResult.envelope)
		if not encodeOk or type(encodedOrError) ~= "string" then
			return {
				accepted = false,
				reason = "message_encode_failed",
			}
		end

		local publishResult = messagingAdapter.Publish({
			topic = topicResult.topic,
			message = encodedOrError,
			messageType = resolvedEventName,
			operationId = operationId,
		})
		if type(publishResult) ~= "table" then
			return {
				accepted = false,
				reason = "publish_failed",
			}
		end
		if publishResult.accepted ~= true then
			return {
				accepted = false,
				reason = if type(publishResult.reason) == "string" then publishResult.reason else "publish_failed",
			}
		end

		return {
			accepted = true,
			reason = "accepted",
		}
	end

	function fanout.PublishAdmission(eventName: any, payload: any): any
		return publish("admissionQueue", eventName, payload)
	end

	function fanout.PublishRescue(eventName: any, payload: any): any
		return publish("rescueQueue", eventName, payload)
	end

	function fanout.PublishSystemAnnouncement(eventName: any, payload: any): any
		return publish("systemAnnouncement", eventName, payload)
	end

	return fanout
end

function QueueNotificationFanout.CreateDefault(): any?
	if game == nil or type(game.GetService) ~= "function" then
		return nil
	end

	local messagingAdapter = getGlobalTable("_MessagingServiceAdapter_QueryAPI")
	if messagingAdapter == nil then
		messagingAdapter = MessagingServiceAdapter.CreateDefault()
	end

	if messagingAdapter == nil then
		return nil
	end

	local httpService: any? = nil
	local httpOk, httpOrError = pcall(function()
		return game:GetService("HttpService")
	end)
	if httpOk and httpOrError ~= nil then
		httpService = httpOrError
	end
	if httpService == nil or type(httpService.JSONEncode) ~= "function" then
		return nil
	end

	return QueueNotificationFanout.Create({
		messagingAdapter = messagingAdapter,
		sourceJobId = resolveDefaultSourceJobId(),
		encode = function(value: any): string
			return httpService:JSONEncode(value)
		end,
	})
end

return QueueNotificationFanout
