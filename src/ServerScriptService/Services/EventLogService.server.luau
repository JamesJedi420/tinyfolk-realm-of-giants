--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local EventLogConfig = require(Config:WaitForChild("EventLogConfig"))
local EventLogState = require(GiantRealm:WaitForChild("EventLogState"))

local state = EventLogState.NewState()
local globalEnv: any = getfenv()

local function now(): number
	return os.clock()
end

local function recordEvent(category: any, message: any, severity: any, timestamp: any, metadata: any): any
	local resolvedTimestamp = if type(timestamp) == "number" then timestamp else now()
	local transition = EventLogState.AppendEvent(state, {
		timestamp = resolvedTimestamp,
		category = category,
		message = message,
		severity = if severity == nil then EventLogConfig.DefaultSeverity else severity,
		metadata = metadata,
	})

	state = transition.state
	return {
		accepted = transition.accepted,
		reason = transition.reason,
		record = transition.record,
	}
end

globalEnv._EventLogService_QueryAPI = {
	RecordEvent = function(category: any, message: any, severity: any?, timestamp: any?, metadata: any?): any
		return recordEvent(category, message, severity, timestamp, metadata)
	end,
	RecordEventFromPayload = function(payload: any): any
		if type(payload) ~= "table" then
			return { accepted = false, reason = "payload_invalid", record = nil }
		end

		return recordEvent(
			(payload :: any).category,
			(payload :: any).message,
			(payload :: any).severity,
			(payload :: any).timestamp,
			(payload :: any).metadata
		)
	end,
	GetRecentEvents = function(limit: number?): any
		return EventLogState.GetRecentEvents(state, limit)
	end,
	GetStateSnapshot = function(): any
		return EventLogState.GetStateSnapshot(state)
	end,
	ResetForTests = function()
		state = EventLogState.NewState()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_EventLogService_QueryAPI", globalEnv._EventLogService_QueryAPI)
end

return globalEnv._EventLogService_QueryAPI
