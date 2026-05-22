--!strict

local PostCrossingBurstLogic = require("../src/ReplicatedStorage/Shared/TinyfolkMovement/PostCrossingBurstLogic")
local Config = require("../src/ReplicatedStorage/Shared/Config/TinyfolkMovementTraitConfig")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function baseEvent(now: number): any
	return {
		now = now,
		validCrossing = true,
		routeId = "EscapeRoute_A",
		isTinyfolk = true,
		hasTrait = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
		currentWalkSpeed = 16,
		baseWalkSpeed = 16,
	}
end

do
	local state, outcome = PostCrossingBurstLogic.ResolveCrossing(nil, Config, baseEvent(10))

	assertTrue(outcome.accepted, "valid crossing starts burst")
	assertEqual(outcome.reason, "accepted", "valid crossing reason")
	assertEqual(state.burstActiveUntil, 11.25, "valid crossing burst until")
	assertEqual(state.burstCooldownUntil, 16, "valid crossing cooldown until")
	assertEqual(state.sharedBurstCooldownUntil, 16, "valid crossing shared cooldown until")
	assertEqual(state.traceCostUntil, 14.25, "valid crossing trace until")
	assertEqual(outcome.targetWalkSpeed, 22, "valid crossing target speed")
	assertEqual(outcome.restoreWalkSpeed, 16, "valid crossing restore speed")
end

do
	local state, outcome = PostCrossingBurstLogic.ResolveCrossing(nil, Config, {
		now = 10,
		validCrossing = false,
		routeId = "EscapeRoute_A",
		isTinyfolk = true,
		hasTrait = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
		currentWalkSpeed = 16,
		baseWalkSpeed = 16,
	})

	assertFalse(outcome.accepted, "invalid crossing does not start burst")
	assertEqual(outcome.reason, "invalid_crossing", "invalid crossing reason")
	assertEqual(state.burstActiveUntil, nil, "invalid crossing keeps burst nil")
end

do
	local event = baseEvent(10)
	event.hasTrait = false
	local state, outcome = PostCrossingBurstLogic.ResolveCrossing(nil, Config, event)

	assertFalse(outcome.accepted, "non-trait holder does not start burst")
	assertEqual(outcome.reason, "trait_not_enabled", "non-trait rejection reason")
	assertEqual(state.burstActiveUntil, nil, "non-trait keeps burst nil")
end

do
	local state, first = PostCrossingBurstLogic.ResolveCrossing(nil, Config, baseEvent(10))
	local nextState, second = PostCrossingBurstLogic.ResolveCrossing(state, Config, baseEvent(10.5))

	assertTrue(first.accepted, "active restack setup accepted")
	assertFalse(second.accepted, "repeated active crossing rejected")
	assertEqual(second.reason, "burst_already_active", "active restack reason")
	assertEqual(nextState.burstActiveUntil, state.burstActiveUntil, "active restack does not extend active until")
	assertEqual(nextState.burstCooldownUntil, state.burstCooldownUntil, "active restack does not extend cooldown")
end

do
	local state = {
		burstActiveUntil = 11.25,
		burstCooldownUntil = 16,
		sharedBurstCooldownUntil = 16,
		traceCostUntil = 14.25,
		lastCrossingRouteId = "EscapeRoute_A",
		lastBurstReason = "PostCrossingBurst",
	} :: any
	local event = baseEvent(12)
	local nextState, outcome = PostCrossingBurstLogic.ResolveCrossing(state, Config, event)

	assertFalse(outcome.accepted, "cooldown crossing rejected")
	assertEqual(outcome.reason, "burst_cooldown", "cooldown rejection reason")
	assertEqual(nextState.burstCooldownUntil, 16, "cooldown crossing does not restack")
end

do
	local state = {
		sharedBurstCooldownUntil = 16,
	} :: any
	local event = baseEvent(12)
	local nextState, outcome = PostCrossingBurstLogic.ResolveCrossing(state, Config, event)

	assertFalse(outcome.accepted, "shared movement-burst cooldown blocks crossing")
	assertEqual(outcome.reason, "shared_burst_cooldown", "shared cooldown reason")
	assertEqual(nextState.burstActiveUntil, nil, "shared cooldown does not start burst")
end

do
	local state, _outcome = PostCrossingBurstLogic.ResolveCrossing(nil, Config, baseEvent(10))
	local snapshot = PostCrossingBurstLogic.Snapshot(state, 12)

	assertFalse(snapshot.burstActive, "trace remains after boost window burst inactive")
	assertTrue(snapshot.traceCostActive, "trace remains after boost window")
	assertEqual(snapshot.traceCostReason, "PostCrossingBurst", "trace reason remains readable")
end

do
	local eventA = baseEvent(100)
	local eventB = baseEvent(100)
	local stateA, outcomeA = PostCrossingBurstLogic.ResolveCrossing(nil, Config, eventA)
	local stateB, outcomeB = PostCrossingBurstLogic.ResolveCrossing(nil, Config, eventB)

	assertEqual(outcomeA.accepted, outcomeB.accepted, "deterministic accepted output")
	assertEqual(outcomeA.targetWalkSpeed, outcomeB.targetWalkSpeed, "deterministic speed output")
	assertEqual(stateA.burstActiveUntil, stateB.burstActiveUntil, "deterministic active until")
	assertEqual(stateA.burstCooldownUntil, stateB.burstCooldownUntil, "deterministic cooldown until")
	assertEqual(stateA.traceCostUntil, stateB.traceCostUntil, "deterministic trace until")
end

print("post_crossing_burst_logic: all checks passed")
