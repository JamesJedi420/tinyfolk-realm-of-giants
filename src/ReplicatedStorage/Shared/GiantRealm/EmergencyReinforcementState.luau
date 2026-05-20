--!strict

local EmergencyReinforcementState = {}

export type ReinforcementState = {
	used: boolean,
	callStartedAt: number?,
	cooldownEndsAt: number?,
	triggeredByUserId: number?,
	spawnedUserId: number?,
	lastReason: string?,
	lastObjectiveId: string?,
}

export type RequestInput = {
	now: number,
	matchStartedAt: number,
	requesterRole: string?,
	requesterUserId: number,
	activeTinyfolkCount: number,
	activeTinyfolkThreshold: number,
	minMatchElapsedSeconds: number,
	objectiveId: string?,
	expectedObjectiveId: string,
	objectiveInRange: boolean,
	hasSpawnPart: boolean,
	spawnProtected: boolean,
	candidateUserId: number?,
	callCooldownSeconds: number,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	state: ReinforcementState,
}

local function cloneState(state: ReinforcementState): ReinforcementState
	return {
		used = state.used == true,
		callStartedAt = state.callStartedAt,
		cooldownEndsAt = state.cooldownEndsAt,
		triggeredByUserId = state.triggeredByUserId,
		spawnedUserId = state.spawnedUserId,
		lastReason = state.lastReason,
		lastObjectiveId = state.lastObjectiveId,
	}
end

local function validNow(now: any): boolean
	if type(now) ~= "number" then
		return false
	end

	if now ~= now or now == math.huge or now == -math.huge then
		return false
	end

	return now >= 0
end

local function validNonNegativeNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return value >= 0
end

local function validPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return value > 0
end

function EmergencyReinforcementState.NewState(): ReinforcementState
	return {
		used = false,
		callStartedAt = nil,
		cooldownEndsAt = nil,
		triggeredByUserId = nil,
		spawnedUserId = nil,
		lastReason = nil,
		lastObjectiveId = nil,
	}
end

function EmergencyReinforcementState.ResolveRequest(state: ReinforcementState, input: RequestInput): TransitionResult
	local nextState = cloneState(state)

	if not validNow(input.now) then
		nextState.lastReason = "invalid_now"
		return { accepted = false, reason = "invalid_now", state = nextState }
	end

	if not validNonNegativeNumber(input.matchStartedAt) then
		nextState.lastReason = "invalid_match_started_at"
		return { accepted = false, reason = "invalid_match_started_at", state = nextState }
	end

	if not validPositiveInteger(input.requesterUserId) then
		nextState.lastReason = "requester_user_id_invalid"
		return { accepted = false, reason = "requester_user_id_invalid", state = nextState }
	end

	if not validNonNegativeNumber(input.activeTinyfolkCount) then
		nextState.lastReason = "invalid_active_tinyfolk_count"
		return { accepted = false, reason = "invalid_active_tinyfolk_count", state = nextState }
	end

	if not validNonNegativeNumber(input.activeTinyfolkThreshold) then
		nextState.lastReason = "invalid_active_tinyfolk_threshold"
		return { accepted = false, reason = "invalid_active_tinyfolk_threshold", state = nextState }
	end

	if not validNonNegativeNumber(input.minMatchElapsedSeconds) then
		nextState.lastReason = "invalid_min_match_elapsed"
		return { accepted = false, reason = "invalid_min_match_elapsed", state = nextState }
	end

	if not validNonNegativeNumber(input.callCooldownSeconds) then
		nextState.lastReason = "invalid_call_cooldown"
		return { accepted = false, reason = "invalid_call_cooldown", state = nextState }
	end

	if nextState.used == true then
		nextState.lastReason = "reinforcement_already_used"
		return { accepted = false, reason = "reinforcement_already_used", state = nextState }
	end

	if input.requesterRole ~= "Tinyfolk" then
		nextState.lastReason = "requester_not_tinyfolk"
		return { accepted = false, reason = "requester_not_tinyfolk", state = nextState }
	end

	local elapsed = input.now - input.matchStartedAt
	if elapsed < input.minMatchElapsedSeconds then
		nextState.lastReason = "match_not_ready"
		return { accepted = false, reason = "match_not_ready", state = nextState }
	end

	if input.activeTinyfolkCount >= input.activeTinyfolkThreshold then
		nextState.lastReason = "active_tinyfolk_threshold_not_met"
		return { accepted = false, reason = "active_tinyfolk_threshold_not_met", state = nextState }
	end

	if type(input.objectiveId) ~= "string" or input.objectiveId ~= input.expectedObjectiveId then
		nextState.lastReason = "invalid_objective"
		return { accepted = false, reason = "invalid_objective", state = nextState }
	end

	if input.objectiveInRange ~= true then
		nextState.lastReason = "objective_out_of_range"
		return { accepted = false, reason = "objective_out_of_range", state = nextState }
	end

	if input.hasSpawnPart ~= true then
		nextState.lastReason = "reinforcement_spawn_missing"
		return { accepted = false, reason = "reinforcement_spawn_missing", state = nextState }
	end

	if input.spawnProtected == true then
		nextState.lastReason = "reinforcement_spawn_protected"
		return { accepted = false, reason = "reinforcement_spawn_protected", state = nextState }
	end

	if input.candidateUserId == nil then
		nextState.lastReason = "reinforcement_candidate_missing"
		return { accepted = false, reason = "reinforcement_candidate_missing", state = nextState }
	end

	if not validPositiveInteger(input.candidateUserId) then
		nextState.lastReason = "reinforcement_candidate_invalid"
		return { accepted = false, reason = "reinforcement_candidate_invalid", state = nextState }
	end

	nextState.used = true
	nextState.callStartedAt = input.now
	nextState.cooldownEndsAt = input.now + math.max(0, input.callCooldownSeconds)
	nextState.triggeredByUserId = input.requesterUserId
	nextState.spawnedUserId = input.candidateUserId
	nextState.lastReason = "accepted"
	nextState.lastObjectiveId = input.objectiveId

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
	}
end

return EmergencyReinforcementState
