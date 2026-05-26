--!strict

local QueueNotificationFanout: any = {}

local ADMISSION_TOPIC = "tin_queue_admission_v1"
local RESCUE_TOPIC = "tin_queue_rescue_v1"

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
	local encode = if type(configAny) == "table" then configAny.encode else nil

	if messagingService == nil then
		return nil
	end
	if not hasMethod(messagingService, "PublishAsync") then
		return nil
	end
	if type(encode) ~= "function" then
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

		local publishOk = pcall(function()
			messagingService:PublishAsync(topic, encodedOrError)
		end)
		if not publishOk then
			return {
				accepted = false,
				reason = "publish_failed",
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
		messagingService = messagingService,
		encode = function(value: any): string
			return httpService:JSONEncode(value)
		end,
	})
end

return QueueNotificationFanout
