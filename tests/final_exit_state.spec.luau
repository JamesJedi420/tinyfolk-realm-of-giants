--!strict

local FinalExitState = require("../src/ReplicatedStorage/Shared/GiantRealm/FinalExitState")

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
	RouteId = "EscapeRoute_Final",
	PoweredDurationSeconds = 2,
	OpeningDurationSeconds = 3,
	BlockedDurationSeconds = 4,
	ReopenDurationSeconds = 2,
}

do
	local state = FinalExitState.NewState(config)
	local threshold = FinalExitState.MarkObjectiveThresholdMet(state, config, 10)
	assertTrue(threshold.accepted, "threshold activation accepted")
	assertEqual(threshold.reason, "powered", "threshold activation reason")
	assertEqual(threshold.state.phase, FinalExitState.Phases.Powered, "threshold enters powered")
	assertEqual(threshold.state.poweredEndsAt, 12, "powered end deterministic")

	local earlyResolve = FinalExitState.ResolveTime(threshold.state, config, 11)
	assertFalse(earlyResolve.accepted, "powered wait rejects early")
	assertEqual(earlyResolve.reason, "waiting_powered", "powered wait reason")

	local opening = FinalExitState.ResolveTime(threshold.state, config, 12)
	assertTrue(opening.accepted, "powered advances to opening")
	assertEqual(opening.reason, "opening_started", "opening start reason")
	assertEqual(opening.state.phase, FinalExitState.Phases.Opening, "phase opening")
	assertEqual(opening.state.openingEndsAt, 15, "opening end deterministic")

	local open = FinalExitState.ResolveTime(opening.state, config, 15)
	assertTrue(open.accepted, "opening advances to open")
	assertEqual(open.reason, "open", "open reason")
	assertEqual(open.state.phase, FinalExitState.Phases.Open, "phase open")
	assertEqual(open.state.openStartedAt, 15, "open started timestamp tracked")
end

do
	local state = FinalExitState.NewState(config)
	local threshold = FinalExitState.MarkObjectiveThresholdMet(state, config, 20)
	local opening = FinalExitState.ResolveTime(threshold.state, config, 22)
	local blocked = FinalExitState.ApplyBlockInterruption(opening.state, config, 501, 23)
	assertTrue(blocked.accepted, "opening can be blocked")
	assertEqual(blocked.state.phase, FinalExitState.Phases.Blocked, "phase blocked from opening")
	assertEqual(blocked.state.blockedEndsAt, 27, "blocked end deterministic")
	assertEqual(blocked.state.blockedByUserId, 501, "blocked by user tracked")

	local blockedWait = FinalExitState.ResolveTime(blocked.state, config, 26)
	assertFalse(blockedWait.accepted, "blocked wait rejects early")
	assertEqual(blockedWait.reason, "waiting_blocked", "blocked wait reason")

	local reopening = FinalExitState.ResolveTime(blocked.state, config, 27)
	assertTrue(reopening.accepted, "blocked transitions to reopening")
	assertEqual(reopening.reason, "reopening", "reopening reason")
	assertEqual(reopening.state.phase, FinalExitState.Phases.Opening, "blocked returns to opening")
	assertEqual(reopening.state.openingEndsAt, 29, "reopening end deterministic")

	local reopened = FinalExitState.ResolveTime(reopening.state, config, 29)
	assertTrue(reopened.accepted, "reopening reaches open")
	assertEqual(reopened.state.phase, FinalExitState.Phases.Open, "phase open after reopen")

	local invalidFractional = FinalExitState.ApplyBlockInterruption(opening.state, config, 501.5, 23)
	assertFalse(invalidFractional.accepted, "fractional blocker user id rejected")
	assertEqual(invalidFractional.reason, "blocked_by_user_id_invalid", "fractional blocker rejection reason")

	local invalidNaN = FinalExitState.ApplyBlockInterruption(opening.state, config, 0 / 0, 23)
	assertFalse(invalidNaN.accepted, "NaN blocker user id rejected")
	assertEqual(invalidNaN.reason, "blocked_by_user_id_invalid", "NaN blocker rejection reason")

	local invalidZero = FinalExitState.ApplyBlockInterruption(opening.state, config, 0, 23)
	assertFalse(invalidZero.accepted, "zero blocker user id rejected")
	assertEqual(invalidZero.reason, "blocked_by_user_id_invalid", "zero blocker rejection reason")
end

do
	local state = FinalExitState.NewState(config)
	local threshold = FinalExitState.MarkObjectiveThresholdMet(state, config, 40)
	local repeatedThreshold = FinalExitState.MarkObjectiveThresholdMet(threshold.state, config, 41)
	assertFalse(repeatedThreshold.accepted, "threshold activation idempotent reject")
	assertEqual(repeatedThreshold.reason, "threshold_already_met", "threshold repeated reason")

	local idleTick = FinalExitState.ResolveTime(state, config, 41)
	assertFalse(idleTick.accepted, "dormant has no time transition")
	assertEqual(idleTick.reason, "no_time_transition", "dormant time reason")
end

do
	local state = FinalExitState.NewState(config)
	local threshold = FinalExitState.MarkObjectiveThresholdMet(state, config, 60)
	local opening = FinalExitState.ResolveTime(threshold.state, config, 62)
	local open = FinalExitState.ResolveTime(opening.state, config, 65)
	local resolved = FinalExitState.ResolveEscape(open.state, 7001, 66)
	assertTrue(resolved.accepted, "open exit can resolve")
	assertEqual(resolved.state.phase, FinalExitState.Phases.Resolved, "phase resolved")
	assertEqual(resolved.state.resolvedAt, 66, "resolved timestamp tracked")
	assertEqual(resolved.state.resolvedByUserId, 7001, "resolved by user tracked")

	local postResolvedTick = FinalExitState.ResolveTime(resolved.state, config, 90)
	assertFalse(postResolvedTick.accepted, "resolved does not reopen on time")
	assertEqual(postResolvedTick.reason, "no_time_transition", "resolved time reason")

	local postResolvedBlock = FinalExitState.ApplyBlockInterruption(resolved.state, config, 99, 91)
	assertFalse(postResolvedBlock.accepted, "resolved cannot be blocked again")
	assertEqual(postResolvedBlock.reason, "phase_not_interruptible", "resolved block reason")

	local snapshot = FinalExitState.GetSnapshot(resolved.state)
	assertTrue(snapshot.isResolved, "resolved snapshot reports resolved")
	assertFalse(snapshot.isEscapeOpen, "resolved snapshot not open")
end

print("final_exit_state: all checks passed")
