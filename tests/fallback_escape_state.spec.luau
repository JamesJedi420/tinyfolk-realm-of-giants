--!strict

local FallbackEscapeState = require("../src/ReplicatedStorage/Shared/GiantRealm/FallbackEscapeState")

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

local config = {
	RouteId = "EscapeRoute_B",
	OpenDelaySeconds = 2,
	CloseDurationSeconds = 4,
}

do
	local state = FallbackEscapeState.NewState(config)
	local noActivation = FallbackEscapeState.Refresh(state, config, { 101, 102 }, 10)
	assertFalse(noActivation.accepted, "two active Tinyfolk do not activate fallback")
	assertEqual(noActivation.reason, "not_last_tinyfolk", "two-active reason")
	assertEqual(noActivation.state.phase, FallbackEscapeState.Phases.Inactive, "two-active stays inactive")
end

do
	local state = FallbackEscapeState.NewState(config)
	local searching = FallbackEscapeState.Refresh(state, config, { 101 }, 20)
	assertTrue(searching.accepted, "one active Tinyfolk activates search")
	assertEqual(searching.reason, "searching", "search activation reason")
	assertEqual(searching.state.phase, FallbackEscapeState.Phases.Searching, "phase searching")
	assertEqual(searching.state.opensAt, 22, "open delay deterministic")

	local waiting = FallbackEscapeState.Refresh(searching.state, config, { 101 }, 21)
	assertFalse(waiting.accepted, "search waits before open")
	assertEqual(waiting.reason, "waiting_search", "search wait reason")

	local opened = FallbackEscapeState.Refresh(searching.state, config, { 101 }, 22)
	assertTrue(opened.accepted, "search reaches open")
	assertEqual(opened.state.phase, FallbackEscapeState.Phases.Open, "phase open")
end

do
	local state = FallbackEscapeState.NewState(config)
	local searching = FallbackEscapeState.Refresh(state, config, { 201 }, 30)
	local opened = FallbackEscapeState.Refresh(searching.state, config, { 201 }, 32)
	local closed = FallbackEscapeState.ApplyClose(opened.state, config, 9001, 33)
	assertTrue(closed.accepted, "open fallback can be closed")
	assertEqual(closed.state.phase, FallbackEscapeState.Phases.Closed, "phase closed")
	assertEqual(closed.state.closedEndsAt, 37, "close duration deterministic")
	assertEqual(closed.state.closedByUserId, 9001, "closed by user tracked")

	local waitClosed = FallbackEscapeState.Refresh(closed.state, config, { 201 }, 36)
	assertFalse(waitClosed.accepted, "closed waits before reopen")
	assertEqual(waitClosed.reason, "waiting_closed", "closed wait reason")

	local reopened = FallbackEscapeState.Refresh(closed.state, config, { 201 }, 37)
	assertTrue(reopened.accepted, "closed fallback reopens")
	assertEqual(reopened.state.phase, FallbackEscapeState.Phases.Open, "phase reopened")
end

do
	local state = FallbackEscapeState.NewState(config)
	local searching = FallbackEscapeState.Refresh(state, config, { 301 }, 40)
	local opened = FallbackEscapeState.Refresh(searching.state, config, { 301 }, 42)
	local resolved = FallbackEscapeState.ResolveEscape(opened.state, 301, 43)
	assertTrue(resolved.accepted, "open fallback resolves")
	assertEqual(resolved.state.phase, FallbackEscapeState.Phases.Resolved, "phase resolved")
	assertEqual(resolved.state.resolvedByUserId, 301, "resolved user tracked")

	local afterResolve = FallbackEscapeState.Refresh(resolved.state, config, { 301 }, 44)
	assertFalse(afterResolve.accepted, "resolved does not reactivate")
	assertEqual(afterResolve.reason, "resolved", "resolved refresh reason")
end

do
	local state = FallbackEscapeState.NewState(config)
	local invalidClose = FallbackEscapeState.ApplyClose(state, config, 9001.5, 50)
	assertFalse(invalidClose.accepted, "fractional closer rejected")
	assertEqual(invalidClose.reason, "closed_by_user_id_invalid", "fractional closer reason")

	local invalidEscape = FallbackEscapeState.ResolveEscape(state, 401, 51)
	assertFalse(invalidEscape.accepted, "inactive fallback cannot resolve")
	assertEqual(invalidEscape.reason, "fallback_not_open", "inactive resolve reason")
end

print("fallback_escape_state: all checks passed")
