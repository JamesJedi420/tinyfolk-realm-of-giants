--!nocheck
local EventLogState = require("../src/ReplicatedStorage/Shared/GiantRealm/EventLogState")
local EventLogConfig = require("../src/ReplicatedStorage/Shared/Config/EventLogConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function newState()
	return EventLogState.NewState()
end

do
	local transition = EventLogState.AppendEvent(newState(), {
		timestamp = 1,
		category = "capture",
		message = "capture accepted",
		severity = "info",
		metadata = { userId = 1001 },
	})
	assertTrue(transition.accepted, "valid event accepted")
	assertEqual(transition.reason, "accepted", "valid event reason")
	assertEqual(transition.record.sequence, 1, "valid event sequence")
	assertEqual(transition.record.category, "capture", "valid event category")
	assertEqual(transition.record.message, "capture accepted", "valid event message")
	assertEqual(transition.record.severity, "info", "valid event severity")
	assertEqual(transition.state.lastReason, "accepted", "valid event state reason")
end

do
	local rejected = EventLogState.AppendEvent(newState(), {
		timestamp = 0 / 0,
		category = "capture",
		message = "capture accepted",
		severity = "info",
	})
	assertFalse(rejected.accepted, "invalid timestamp rejected")
	assertEqual(rejected.reason, "timestamp_invalid", "invalid timestamp reason")
end

do
	local rejected = EventLogState.AppendEvent(newState(), {
		timestamp = 1,
		category = "",
		message = "capture accepted",
		severity = "info",
	})
	assertFalse(rejected.accepted, "invalid category rejected")
	assertEqual(rejected.reason, "category_invalid", "invalid category reason")
end

do
	local rejected = EventLogState.AppendEvent(newState(), {
		timestamp = 1,
		category = "capture",
		message = "",
		severity = "info",
	})
	assertFalse(rejected.accepted, "invalid message rejected")
	assertEqual(rejected.reason, "message_invalid", "invalid message reason")
end

do
	local rejected = EventLogState.AppendEvent(newState(), {
		timestamp = 1,
		category = "capture",
		message = "capture accepted",
		severity = "critical",
	})
	assertFalse(rejected.accepted, "invalid severity rejected")
	assertEqual(rejected.reason, "severity_invalid", "invalid severity reason")
end

do
	local state = newState()
	local withDefault = EventLogState.AppendEvent(state, {
		timestamp = 1,
		category = "capture",
		message = "capture accepted",
		severity = nil,
	})
	assertTrue(withDefault.accepted, "default severity event accepted")
	assertEqual(withDefault.record.severity, EventLogConfig.DefaultSeverity, "default severity applied")
end

do
	local state = newState()
	state = EventLogState.AppendEvent(state, {
		timestamp = 1,
		category = "capture",
		message = "first",
		severity = "info",
	}).state
	state = EventLogState.AppendEvent(state, {
		timestamp = 2,
		category = "score",
		message = "second",
		severity = "warn",
	}).state
	state = EventLogState.AppendEvent(state, {
		timestamp = 3,
		category = "escape",
		message = "third",
		severity = "error",
	}).state

	local twoRecent = EventLogState.GetRecentEvents(state, 2)
	assertEqual(#twoRecent, 2, "recent event limit")
	assertEqual(twoRecent[1].message, "third", "recent newest first")
	assertEqual(twoRecent[2].message, "second", "recent second newest")

	local noneRecent = EventLogState.GetRecentEvents(state, 0)
	assertEqual(#noneRecent, 0, "zero limit returns none")
end

print("event_log_state: all checks passed")
