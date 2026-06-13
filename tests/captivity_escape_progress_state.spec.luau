local CaptivityEscapeProgressState = require("../src/ReplicatedStorage/Shared/GiantRealm/CaptivityEscapeProgressState")

local function assertEqual(actual: any, expected: any, message: string)
	if actual ~= expected then
		error(string.format("%s (expected=%s actual=%s)", message, tostring(expected), tostring(actual)))
	end
	print("PASS [" .. message .. "]")
end

local function assertTrue(value: any, message: string)
	if value ~= true then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function assertFalse(value: any, message: string)
	if value ~= false then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local config = {
	StruggleProgressRequired = 4,
	StruggleProgressPerAction = 1,
	StruggleActionCooldownSeconds = 0.25,
	AllyAssistProgressBonus = 2,
	AllyAssistCooldownSeconds = 0.5,
	StruggleProgressDecayIntervalSeconds = 2,
	StruggleProgressDecayAmount = 1,
	StruggleAllyProgressBonusPerAlly = 1,
}

local state = CaptivityEscapeProgressState.NewState(config, 0)
assertEqual(state.required, 4, "required progress configured")
assertEqual(state.progress, 0, "initial progress zero")

local first = CaptivityEscapeProgressState.ResolveStruggle(state, { now = 1, nearbyAllyCount = 1 }, config)
assertTrue(first.accepted, "first struggle accepted")
assertEqual(first.state.progress, 2, "struggle plus one ally bonus")
assertFalse(first.completed, "not complete after one struggle")

local cooldown = CaptivityEscapeProgressState.ResolveStruggle(first.state, { now = 1.1, nearbyAllyCount = 0 }, config)
assertFalse(cooldown.accepted, "cooldown rejects")
assertEqual(cooldown.reason, "struggle_cooldown", "cooldown reason")

local second = CaptivityEscapeProgressState.ResolveStruggle(first.state, { now = 1.3, nearbyAllyCount = 0 }, config)
assertTrue(second.accepted, "second struggle accepted")
assertEqual(second.state.progress, 3, "progress increments")

local third = CaptivityEscapeProgressState.ResolveStruggle(second.state, { now = 1.6, nearbyAllyCount = 0 }, config)
assertTrue(third.completed, "threshold reached")
assertTrue(third.snapshot.isReady, "snapshot ready")

local assist = CaptivityEscapeProgressState.ResolveAllyAssist(state, { now = 2 }, config)
assertTrue(assist.accepted, "ally assist accepted")
assertEqual(assist.state.progress, 2, "ally assist bonus applied")

local assistCooldown = CaptivityEscapeProgressState.ResolveAllyAssist(assist.state, { now = 2.2 }, config)
assertFalse(assistCooldown.accepted, "ally assist cooldown rejects")

local decayPending = CaptivityEscapeProgressState.ResolveDecay(third.state, 2.0, config)
assertEqual(decayPending.reason, "decay_not_due", "decay not due immediately")

local decayApplied = CaptivityEscapeProgressState.ResolveDecay(third.state, 4.1, config)
assertEqual(decayApplied.state.progress, 3, "decay reduces progress")
assertEqual(decayApplied.reason, "progress_decayed", "decay reason")

local suppressed = CaptivityEscapeProgressState.ResolveSuppression(third.state, 5)
assertTrue(suppressed.state.suppressed, "suppression flag set")
assertEqual(suppressed.state.progress, 0, "suppression clears progress")
assertEqual(suppressed.snapshot.phase, "suppressed", "suppressed phase")

local blocked =
	CaptivityEscapeProgressState.ResolveStruggle(suppressed.state, { now = 5.5, nearbyAllyCount = 0 }, config)
assertFalse(blocked.accepted, "suppressed struggle rejected")
assertEqual(blocked.reason, "escape_suppressed_contained", "suppressed struggle reason")

local reset = CaptivityEscapeProgressState.ResolveReset(third.state, 6, "custody_ended")
assertEqual(reset.state.progress, 0, "reset clears progress")
assertFalse(reset.state.suppressed, "reset clears suppression")

print("captivity_escape_progress_state: all checks passed")
