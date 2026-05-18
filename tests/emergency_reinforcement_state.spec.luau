--!strict

local EmergencyReinforcementState = require("../src/ReplicatedStorage/Shared/GiantRealm/EmergencyReinforcementState")

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

local function makeInput(overrides: any?): any
	local input = {
		now = 100,
		matchStartedAt = 0,
		requesterRole = "Tinyfolk",
		requesterUserId = 1,
		activeTinyfolkCount = 1,
		activeTinyfolkThreshold = 2,
		minMatchElapsedSeconds = 45,
		objectiveId = "CallCenter_A",
		expectedObjectiveId = "CallCenter_A",
		objectiveInRange = true,
		hasSpawnPart = true,
		spawnProtected = false,
		candidateUserId = 2,
		callCooldownSeconds = 45,
	}

	if overrides ~= nil then
		for key, value in overrides do
			input[key] = value
		end
	end

	return input
end

do
	local state = EmergencyReinforcementState.NewState()
	local result = EmergencyReinforcementState.ResolveRequest(
		state,
		makeInput({
			now = 20,
			matchStartedAt = 0,
			minMatchElapsedSeconds = 45,
		})
	)

	assertFalse(result.accepted, "request rejects before match minimum elapsed")
	assertEqual(result.reason, "match_not_ready", "request before match start reason")
end

do
	local state = EmergencyReinforcementState.NewState()
	local result = EmergencyReinforcementState.ResolveRequest(
		state,
		makeInput({
			activeTinyfolkCount = 2,
			activeTinyfolkThreshold = 2,
		})
	)

	assertFalse(result.accepted, "request rejects at active tinyfolk threshold")
	assertEqual(result.reason, "active_tinyfolk_threshold_not_met", "threshold rejection reason")
end

do
	local state = EmergencyReinforcementState.NewState()
	local result = EmergencyReinforcementState.ResolveRequest(
		state,
		makeInput({
			objectiveId = "WrongObjective",
		})
	)

	assertFalse(result.accepted, "request rejects invalid objective")
	assertEqual(result.reason, "invalid_objective", "invalid objective reason")
end

do
	local state = EmergencyReinforcementState.NewState()
	local accepted = EmergencyReinforcementState.ResolveRequest(state, makeInput())

	assertTrue(accepted.accepted, "valid request accepted")
	assertEqual(accepted.state.used, true, "accepted request marks used")
	assertEqual(accepted.state.triggeredByUserId, 1, "accepted request stores trigger user id")
	assertEqual(accepted.state.spawnedUserId, 2, "accepted request stores spawned user id")
	assertEqual(accepted.state.cooldownEndsAt, 145, "accepted request stores cooldown end")

	local followUp = EmergencyReinforcementState.ResolveRequest(accepted.state, makeInput({ now = 110 }))
	assertFalse(followUp.accepted, "second request rejects after one-time use")
	assertEqual(followUp.reason, "reinforcement_already_used", "already used rejection reason")
end

print("emergency_reinforcement_state: all checks passed")
