--!strict

local FallbackEscapeState: any = {}

FallbackEscapeState.Phases = {
	Inactive = "Inactive",
	Searching = "Searching",
	Open = "Open",
	Closed = "Closed",
	Resolved = "Resolved",
}

export type State = {
	routeId: string,
	phase: string,
	activatedAt: number?,
	opensAt: number?,
	openStartedAt: number?,
	closedAt: number?,
	closedEndsAt: number?,
	closedByUserId: number?,
	resolvedAt: number?,
	resolvedByUserId: number?,
	lastActiveTinyfolkUserId: number?,
	lastReason: string?,
}

local function isFiniteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value >= 0
end

local function isValidUserId(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value % 1 == 0 and value > 0
end

local function duration(value: any, fallback: number): number
	if not isFiniteNonNegative(value) then
		return fallback
	end
	return math.max(0, math.floor(value))
end

local function routeId(value: any): string
	if type(value) == "string" and value ~= "" then
		return value
	end
	return "EscapeRoute_Fallback"
end

local function cloneState(state: State): State
	return {
		routeId = state.routeId,
		phase = state.phase,
		activatedAt = state.activatedAt,
		opensAt = state.opensAt,
		openStartedAt = state.openStartedAt,
		closedAt = state.closedAt,
		closedEndsAt = state.closedEndsAt,
		closedByUserId = state.closedByUserId,
		resolvedAt = state.resolvedAt,
		resolvedByUserId = state.resolvedByUserId,
		lastActiveTinyfolkUserId = state.lastActiveTinyfolkUserId,
		lastReason = state.lastReason,
	}
end

local function transition(state: State, accepted: boolean, reason: string): any
	state.lastReason = reason
	return {
		accepted = accepted,
		reason = reason,
		state = state,
	}
end

local function openDelay(config: any): number
	return duration(if type(config) == "table" then config.OpenDelaySeconds else nil, 2)
end

local function closeDuration(config: any): number
	return duration(if type(config) == "table" then config.CloseDurationSeconds else nil, 4)
end

function FallbackEscapeState.NewState(config: any?): State
	return {
		routeId = routeId(if type(config) == "table" then config.RouteId else nil),
		phase = FallbackEscapeState.Phases.Inactive,
		activatedAt = nil,
		opensAt = nil,
		openStartedAt = nil,
		closedAt = nil,
		closedEndsAt = nil,
		closedByUserId = nil,
		resolvedAt = nil,
		resolvedByUserId = nil,
		lastActiveTinyfolkUserId = nil,
		lastReason = nil,
	}
end

function FallbackEscapeState.GetSnapshot(state: State): any
	return {
		routeId = state.routeId,
		phase = state.phase,
		activatedAt = state.activatedAt,
		opensAt = state.opensAt,
		openStartedAt = state.openStartedAt,
		closedAt = state.closedAt,
		closedEndsAt = state.closedEndsAt,
		closedByUserId = state.closedByUserId,
		resolvedAt = state.resolvedAt,
		resolvedByUserId = state.resolvedByUserId,
		lastActiveTinyfolkUserId = state.lastActiveTinyfolkUserId,
		lastReason = state.lastReason,
		isEscapeOpen = state.phase == FallbackEscapeState.Phases.Open,
		isResolved = state.phase == FallbackEscapeState.Phases.Resolved,
	}
end

function FallbackEscapeState.Refresh(state: State, config: any, activeTinyfolkUserIds: { number }, now: number): any
	local nextState = cloneState(state)
	if not isFiniteNonNegative(now) then
		return transition(nextState, false, "time_invalid")
	end
	if nextState.phase == FallbackEscapeState.Phases.Resolved then
		return transition(nextState, false, "resolved")
	end

	if type(activeTinyfolkUserIds) ~= "table" or #activeTinyfolkUserIds ~= 1 then
		if nextState.phase ~= FallbackEscapeState.Phases.Inactive then
			nextState.phase = FallbackEscapeState.Phases.Inactive
			nextState.activatedAt = nil
			nextState.opensAt = nil
			nextState.openStartedAt = nil
			nextState.closedAt = nil
			nextState.closedEndsAt = nil
			nextState.closedByUserId = nil
			nextState.lastActiveTinyfolkUserId = nil
			return transition(nextState, true, "inactive")
		end
		return transition(nextState, false, "not_last_tinyfolk")
	end

	local activeUserId = activeTinyfolkUserIds[1]
	if not isValidUserId(activeUserId) then
		return transition(nextState, false, "active_tinyfolk_user_id_invalid")
	end

	if nextState.phase == FallbackEscapeState.Phases.Inactive then
		nextState.phase = FallbackEscapeState.Phases.Searching
		nextState.activatedAt = now
		nextState.opensAt = now + openDelay(config)
		nextState.lastActiveTinyfolkUserId = activeUserId
		return transition(nextState, true, "searching")
	end

	nextState.lastActiveTinyfolkUserId = activeUserId
	if nextState.phase == FallbackEscapeState.Phases.Searching then
		if type(nextState.opensAt) ~= "number" or now < nextState.opensAt then
			return transition(nextState, false, "waiting_search")
		end
		nextState.phase = FallbackEscapeState.Phases.Open
		nextState.openStartedAt = now
		return transition(nextState, true, "open")
	end

	if nextState.phase == FallbackEscapeState.Phases.Closed then
		if type(nextState.closedEndsAt) ~= "number" or now < nextState.closedEndsAt then
			return transition(nextState, false, "waiting_closed")
		end
		nextState.phase = FallbackEscapeState.Phases.Open
		nextState.openStartedAt = now
		nextState.closedAt = nil
		nextState.closedEndsAt = nil
		nextState.closedByUserId = nil
		return transition(nextState, true, "reopened")
	end

	return transition(nextState, false, "no_transition")
end

function FallbackEscapeState.ApplyClose(state: State, config: any, closedByUserId: number?, now: number): any
	local nextState = cloneState(state)
	if not isFiniteNonNegative(now) then
		return transition(nextState, false, "time_invalid")
	end
	if not isValidUserId(closedByUserId) then
		return transition(nextState, false, "closed_by_user_id_invalid")
	end
	if nextState.phase ~= FallbackEscapeState.Phases.Searching and nextState.phase ~= FallbackEscapeState.Phases.Open then
		return transition(nextState, false, "phase_not_closeable")
	end

	nextState.phase = FallbackEscapeState.Phases.Closed
	nextState.closedAt = now
	nextState.closedEndsAt = now + closeDuration(config)
	nextState.closedByUserId = closedByUserId
	return transition(nextState, true, "closed")
end

function FallbackEscapeState.ResolveEscape(state: State, escapedByUserId: number?, now: number): any
	local nextState = cloneState(state)
	if not isFiniteNonNegative(now) then
		return transition(nextState, false, "time_invalid")
	end
	if nextState.phase ~= FallbackEscapeState.Phases.Open then
		return transition(nextState, false, "fallback_not_open")
	end

	nextState.phase = FallbackEscapeState.Phases.Resolved
	nextState.resolvedAt = now
	nextState.resolvedByUserId = if isValidUserId(escapedByUserId) then escapedByUserId else nil
	return transition(nextState, true, "resolved")
end

return FallbackEscapeState
