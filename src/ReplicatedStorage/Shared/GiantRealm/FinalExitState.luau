--!strict

local FinalExitState: any = {}

FinalExitState.Phases = {
	Dormant = "Dormant",
	Powered = "Powered",
	Opening = "Opening",
	Open = "Open",
	Blocked = "Blocked",
	Resolved = "Resolved",
}

export type State = {
	routeId: string,
	phase: string,
	poweredAt: number?,
	poweredEndsAt: number?,
	openingStartedAt: number?,
	openingEndsAt: number?,
	openStartedAt: number?,
	blockedAt: number?,
	blockedEndsAt: number?,
	blockedByUserId: number?,
	resolvedAt: number?,
	resolvedByUserId: number?,
	lastReason: string?,
}

export type Snapshot = {
	routeId: string,
	phase: string,
	poweredAt: number?,
	poweredEndsAt: number?,
	openingStartedAt: number?,
	openingEndsAt: number?,
	openStartedAt: number?,
	blockedAt: number?,
	blockedEndsAt: number?,
	blockedByUserId: number?,
	resolvedAt: number?,
	resolvedByUserId: number?,
	lastReason: string?,
	isEscapeOpen: boolean,
	isResolved: boolean,
}

export type Transition = {
	accepted: boolean,
	reason: string,
	state: State,
}

local function isFiniteNonNegative(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return value >= 0
end

local function normalizeDuration(value: any, fallback: number): number
	if not isFiniteNonNegative(value) then
		return fallback
	end
	return math.max(0, math.floor(value))
end

local function normalizeRouteId(value: any): string
	if type(value) == "string" and value ~= "" then
		return value
	end
	return "EscapeRoute_A"
end

local function isValidUserId(value: any): boolean
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

local function cloneState(state: State): State
	return {
		routeId = state.routeId,
		phase = state.phase,
		poweredAt = state.poweredAt,
		poweredEndsAt = state.poweredEndsAt,
		openingStartedAt = state.openingStartedAt,
		openingEndsAt = state.openingEndsAt,
		openStartedAt = state.openStartedAt,
		blockedAt = state.blockedAt,
		blockedEndsAt = state.blockedEndsAt,
		blockedByUserId = state.blockedByUserId,
		resolvedAt = state.resolvedAt,
		resolvedByUserId = state.resolvedByUserId,
		lastReason = state.lastReason,
	}
end

local function transition(state: State, accepted: boolean, reason: string): Transition
	state.lastReason = reason
	return {
		accepted = accepted,
		reason = reason,
		state = state,
	}
end

local function getPoweredDuration(config: any): number
	return normalizeDuration(
		if type(config) == "table" then config.PoweredDurationSeconds or config.FinalExitPoweredDurationSeconds else nil,
		2
	)
end

local function getOpeningDuration(config: any): number
	return normalizeDuration(
		if type(config) == "table" then config.OpeningDurationSeconds or config.FinalExitOpeningDurationSeconds else nil,
		3
	)
end

local function getBlockedDuration(config: any): number
	return normalizeDuration(
		if type(config) == "table" then config.BlockedDurationSeconds or config.FinalExitBlockedDurationSeconds else nil,
		4
	)
end

local function getReopenDuration(config: any): number
	return normalizeDuration(
		if type(config) == "table" then config.ReopenDurationSeconds or config.FinalExitReopenDurationSeconds else nil,
		2
	)
end

function FinalExitState.NewState(config: any?): State
	return {
		routeId = normalizeRouteId(if type(config) == "table" then config.RouteId else nil),
		phase = FinalExitState.Phases.Dormant,
		poweredAt = nil,
		poweredEndsAt = nil,
		openingStartedAt = nil,
		openingEndsAt = nil,
		openStartedAt = nil,
		blockedAt = nil,
		blockedEndsAt = nil,
		blockedByUserId = nil,
		resolvedAt = nil,
		resolvedByUserId = nil,
		lastReason = nil,
	}
end

function FinalExitState.GetSnapshot(state: State): Snapshot
	return {
		routeId = state.routeId,
		phase = state.phase,
		poweredAt = state.poweredAt,
		poweredEndsAt = state.poweredEndsAt,
		openingStartedAt = state.openingStartedAt,
		openingEndsAt = state.openingEndsAt,
		openStartedAt = state.openStartedAt,
		blockedAt = state.blockedAt,
		blockedEndsAt = state.blockedEndsAt,
		blockedByUserId = state.blockedByUserId,
		resolvedAt = state.resolvedAt,
		resolvedByUserId = state.resolvedByUserId,
		lastReason = state.lastReason,
		isEscapeOpen = state.phase == FinalExitState.Phases.Open,
		isResolved = state.phase == FinalExitState.Phases.Resolved,
	}
end

function FinalExitState.MarkObjectiveThresholdMet(state: State, config: any, now: number): Transition
	local nextState = cloneState(state)
	if not isFiniteNonNegative(now) then
		return transition(nextState, false, "time_invalid")
	end

	if nextState.phase ~= FinalExitState.Phases.Dormant then
		return transition(nextState, false, "threshold_already_met")
	end

	nextState.phase = FinalExitState.Phases.Powered
	nextState.poweredAt = now
	nextState.poweredEndsAt = now + getPoweredDuration(config)
	nextState.blockedAt = nil
	nextState.blockedEndsAt = nil
	nextState.blockedByUserId = nil
	return transition(nextState, true, "powered")
end

function FinalExitState.ResolveTime(state: State, config: any, now: number): Transition
	local nextState = cloneState(state)
	if not isFiniteNonNegative(now) then
		return transition(nextState, false, "time_invalid")
	end

	if nextState.phase == FinalExitState.Phases.Powered then
		if type(nextState.poweredEndsAt) ~= "number" or now < nextState.poweredEndsAt then
			return transition(nextState, false, "waiting_powered")
		end

		nextState.phase = FinalExitState.Phases.Opening
		nextState.openingStartedAt = now
		nextState.openingEndsAt = now + getOpeningDuration(config)
		return transition(nextState, true, "opening_started")
	end

	if nextState.phase == FinalExitState.Phases.Opening then
		if type(nextState.openingEndsAt) ~= "number" or now < nextState.openingEndsAt then
			return transition(nextState, false, "waiting_opening")
		end

		nextState.phase = FinalExitState.Phases.Open
		nextState.openStartedAt = now
		return transition(nextState, true, "open")
	end

	if nextState.phase == FinalExitState.Phases.Blocked then
		if type(nextState.blockedEndsAt) ~= "number" or now < nextState.blockedEndsAt then
			return transition(nextState, false, "waiting_blocked")
		end

		nextState.phase = FinalExitState.Phases.Opening
		nextState.openingStartedAt = now
		nextState.openingEndsAt = now + getReopenDuration(config)
		nextState.blockedAt = nil
		nextState.blockedEndsAt = nil
		nextState.blockedByUserId = nil
		return transition(nextState, true, "reopening")
	end

	return transition(nextState, false, "no_time_transition")
end

function FinalExitState.ApplyBlockInterruption(
	state: State,
	config: any,
	blockedByUserId: number?,
	now: number
): Transition
	local nextState = cloneState(state)
	if not isFiniteNonNegative(now) then
		return transition(nextState, false, "time_invalid")
	end
	if not isValidUserId(blockedByUserId) then
		return transition(nextState, false, "blocked_by_user_id_invalid")
	end

	if nextState.phase ~= FinalExitState.Phases.Open and nextState.phase ~= FinalExitState.Phases.Opening then
		return transition(nextState, false, "phase_not_interruptible")
	end

	nextState.phase = FinalExitState.Phases.Blocked
	nextState.blockedAt = now
	nextState.blockedEndsAt = now + getBlockedDuration(config)
	nextState.blockedByUserId = blockedByUserId
	return transition(nextState, true, "blocked")
end

function FinalExitState.ResolveEscape(state: State, escapedByUserId: number?, now: number): Transition
	local nextState = cloneState(state)
	if not isFiniteNonNegative(now) then
		return transition(nextState, false, "time_invalid")
	end
	if nextState.phase ~= FinalExitState.Phases.Open then
		return transition(nextState, false, "exit_not_open")
	end

	nextState.phase = FinalExitState.Phases.Resolved
	nextState.resolvedAt = now
	nextState.resolvedByUserId = if type(escapedByUserId) == "number" then escapedByUserId else nil
	return transition(nextState, true, "resolved")
end

return FinalExitState
