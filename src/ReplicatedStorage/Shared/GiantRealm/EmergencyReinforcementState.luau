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

	if type(input.candidateUserId) ~= "number" then
		nextState.lastReason = "reinforcement_candidate_missing"
		return { accepted = false, reason = "reinforcement_candidate_missing", state = nextState }
	end

	nextState.used = true
	nextState.callStartedAt = input.now
	nextState.cooldownEndsAt = input.now + input.callCooldownSeconds
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
