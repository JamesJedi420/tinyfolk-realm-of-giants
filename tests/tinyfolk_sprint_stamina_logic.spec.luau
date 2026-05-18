--!strict

local SprintStaminaLogic = require("../src/ReplicatedStorage/Shared/TinyfolkMovement/SprintStaminaLogic")
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
		requestedSprint = true,
		isTinyfolk = true,
		hasTrait = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
	}
end

do
	local state, outcome = SprintStaminaLogic.ResolveTick(nil, Config, baseEvent(10))

	assertTrue(outcome.accepted, "empty state can sprint")
	assertEqual(outcome.reason, "accepted", "empty state accepted reason")
	assertEqual(state.stamina, 100, "empty state stamina")
	assertTrue(outcome.snapshot.isSprinting, "empty state sprinting")
	assertFalse(outcome.snapshot.isExhausted, "empty state not exhausted")
	assertEqual(outcome.snapshot.speedMultiplier, 1.25, "empty state speed multiplier")
end

do
	local state, first = SprintStaminaLogic.ResolveTick(nil, Config, baseEvent(10))
	local nextState, second = SprintStaminaLogic.ResolveTick(state, Config, baseEvent(11))

	assertTrue(first.accepted, "drain setup accepted")
	assertEqual(nextState.stamina, 75, "drain after one second")
	assertTrue(second.snapshot.isSprinting, "drain keeps sprinting")
	assertEqual(second.snapshot.staminaRatio, 0.75, "drain ratio")
end

do
	local state = {
		stamina = 4,
		requestedSprint = true,
		isSprinting = true,
		isExhausted = false,
		lastUpdatedAt = 10,
	} :: any
	local nextState, outcome = SprintStaminaLogic.ResolveTick(state, Config, {
		now = 11,
		requestedSprint = true,
		isTinyfolk = true,
		hasTrait = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
	})

	assertFalse(outcome.accepted, "empty stamina sprint rejected")
	assertEqual(outcome.reason, "stamina_empty", "empty stamina reason")
	assertEqual(nextState.stamina, 0, "empty stamina clamps to zero")
	assertFalse(outcome.snapshot.isSprinting, "empty stamina stops sprinting")
	assertTrue(outcome.snapshot.isBreathless, "empty stamina breathless")
end

do
	local state = {
		stamina = 0,
		requestedSprint = false,
		isSprinting = false,
		isExhausted = true,
		lastUpdatedAt = 10,
	} :: any
	local nextState, outcome = SprintStaminaLogic.ResolveTick(state, Config, {
		now = 12,
		requestedSprint = false,
		isTinyfolk = true,
		hasTrait = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
	})

	assertTrue(outcome.accepted, "regen tick accepted")
	assertFalse(outcome.snapshot.isSprinting, "regen does not sprint")
	assertFalse(outcome.snapshot.isExhausted, "regen clears exhaustion above threshold")
	assertEqual(nextState.stamina, 40, "regen restores stamina")
end

do
	local state, outcome = SprintStaminaLogic.ResolveTick(nil, Config, {
		now = 10,
		requestedSprint = true,
		isTinyfolk = false,
		hasTrait = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
	})

	assertFalse(outcome.accepted, "non-tinyfolk sprint rejected")
	assertEqual(outcome.reason, "invalid_sprint_context", "non-tinyfolk reason")
	assertFalse(outcome.snapshot.canSprint, "non-tinyfolk cannot sprint")
	assertEqual(state.requestedSprint, true, "non-tinyfolk request still recorded")
end

print("tinyfolk_sprint_stamina_logic: all checks passed")
