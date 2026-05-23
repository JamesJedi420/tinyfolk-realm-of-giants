--!strict

local EventLogConfig = require("../Config/EventLogConfig")

local EventLogState = {}

export type EventRecord = {
	sequence: number,
	timestamp: number,
	category: string,
	message: string,
	severity: string,
	metadata: any?,
}

export type State = {
	events: { EventRecord },
	sequence: number,
	lastReason: string?,
}

export type AppendInput = {
	timestamp: number,
	category: string,
	message: string,
	severity: string?,
	metadata: any?,
}

export type AppendResult = {
	accepted: boolean,
	reason: string,
	state: State,
	record: EventRecord?,
}

local function validNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function validTimestamp(timestamp: any): boolean
	if not validNumber(timestamp) then
		return false
	end
	return timestamp >= 0
end

local function validText(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function validSeverity(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value == EventLogConfig.Severity.Info
		or value == EventLogConfig.Severity.Warn
		or value == EventLogConfig.Severity.Error
end

local cloneMetadata: (value: any) -> any
cloneMetadata = function(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local output: any = {}
	for key, childValue in pairs(value) do
		output[cloneMetadata(key)] = cloneMetadata(childValue)
	end
	return output
end

local function cloneRecord(record: EventRecord): EventRecord
	return {
		sequence = record.sequence,
		timestamp = record.timestamp,
		category = record.category,
		message = record.message,
		severity = record.severity,
		metadata = cloneMetadata(record.metadata),
	}
end

local function cloneState(state: State): State
	local events: { EventRecord } = {}
	for _, record in ipairs(state.events) do
		table.insert(events, cloneRecord(record))
	end

	return {
		events = events,
		sequence = state.sequence,
		lastReason = state.lastReason,
	}
end

local function maxRecentEvents(): number
	local configured = EventLogConfig.MaxRecentEvents
	if type(configured) ~= "number" or configured < 1 then
		return 1
	end
	return math.max(1, math.floor(configured))
end

function EventLogState.NewState(): State
	return {
		events = {},
		sequence = 0,
		lastReason = nil,
	}
end

function EventLogState.AppendEvent(state: State, input: AppendInput): AppendResult
	local nextState = cloneState(state)

	if not validTimestamp(input.timestamp) then
		nextState.lastReason = "timestamp_invalid"
		return { accepted = false, reason = "timestamp_invalid", state = nextState, record = nil }
	end

	if not validText(input.category) then
		nextState.lastReason = "category_invalid"
		return { accepted = false, reason = "category_invalid", state = nextState, record = nil }
	end

	if not validText(input.message) then
		nextState.lastReason = "message_invalid"
		return { accepted = false, reason = "message_invalid", state = nextState, record = nil }
	end

	local severity = input.severity or EventLogConfig.DefaultSeverity
	if not validSeverity(severity) then
		nextState.lastReason = "severity_invalid"
		return { accepted = false, reason = "severity_invalid", state = nextState, record = nil }
	end

	nextState.sequence += 1
	local record: EventRecord = {
		sequence = nextState.sequence,
		timestamp = input.timestamp,
		category = input.category,
		message = input.message,
		severity = severity,
		metadata = cloneMetadata(input.metadata),
	}

	table.insert(nextState.events, record)
	while #nextState.events > maxRecentEvents() do
		table.remove(nextState.events, 1)
	end

	nextState.lastReason = "accepted"
	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		record = cloneRecord(record),
	}
end

function EventLogState.GetRecentEvents(state: State, limit: number?): { EventRecord }
	local output: { EventRecord } = {}
	if type(limit) == "number" and limit <= 0 then
		return output
	end

	local maxCount = if type(limit) == "number" then math.max(0, math.floor(limit)) else #state.events
	for index = #state.events, 1, -1 do
		if #output >= maxCount then
			break
		end
		table.insert(output, cloneRecord(state.events[index]))
	end

	return output
end

function EventLogState.GetStateSnapshot(state: State): any
	return {
		eventCount = #state.events,
		sequence = state.sequence,
		lastReason = state.lastReason,
	}
end

return EventLogState
