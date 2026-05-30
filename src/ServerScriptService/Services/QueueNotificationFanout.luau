--!strict

local MessagingServiceAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MessagingServiceAdapter"))
	else (require :: any)("./MessagingServiceAdapter")

local QueueNotificationFanout: any = {}
local globalEnv: any = getfenv()

local ADMISSION_TOPIC = "tin_queue_admission_v1"
local RESCUE_TOPIC = "tin_queue_rescue_v1"

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

function QueueNotificationFanout.Create(config: any?): any?
	local configAny: any = config
	local messagingService = if type(configAny) == "table" then configAny.messagingService else nil
	local messagingAdapter = if type(configAny) == "table" then configAny.messagingAdapter else nil
	local encode = if type(configAny) == "table" then configAny.encode else nil

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

	local function publish(topic: string, eventName: any, payload: any): any
		local resolvedEventName = sanitizeEventName(eventName)
		if resolvedEventName == nil then
			return {
				accepted = false,
				reason = "event_name_invalid",
			}
		end

		local message = {
			eventName = resolvedEventName,
			payload = sanitizePayload(payload),
		}

		local encodeOk, encodedOrError = pcall(encode, message)
		if not encodeOk or type(encodedOrError) ~= "string" then
			return {
				accepted = false,
				reason = "message_encode_failed",
			}
		end

		local publishResult = messagingAdapter.Publish({
			topic = topic,
			message = encodedOrError,
			messageType = resolvedEventName,
			operationId = if type(payload) == "table" then payload.operationId else nil,
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
		return publish(ADMISSION_TOPIC, eventName, payload)
	end

	function fanout.PublishRescue(eventName: any, payload: any): any
		return publish(RESCUE_TOPIC, eventName, payload)
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
		encode = function(value: any): string
			return httpService:JSONEncode(value)
		end,
	})
end

return QueueNotificationFanout
