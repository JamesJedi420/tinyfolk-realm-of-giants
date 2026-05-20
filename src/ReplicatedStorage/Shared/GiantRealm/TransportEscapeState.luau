--!strict

local TransportEscapeState: any = {}

TransportEscapeState.ComponentStates = {
	Needed = "Needed",
	Held = "Held",
	Dropped = "Dropped",
	Installed = "Installed",
	Lost = "Lost",
	Recovered = "Recovered",
	Blocked = "Blocked",
	Delivered = "Delivered",
}

TransportEscapeState.EndpointPhases = {
	Idle = "Idle",
	Assembling = "Assembling",
	Assembled = "Assembled",
	Boarding = "Boarding",
	Startup = "Startup",
	Launched = "Launched",
	Departed = "Departed",
}

export type ComponentRecord = {
	componentId: string,
	required: boolean,
	state: string,
	holderUserId: number?,
	installedByUserId: number?,
	lastUpdatedAt: number?,
}

export type State = {
	endpointId: string,
	phase: string,
	capacity: number,
	operatorRequired: boolean,
	startupDurationSeconds: number,
	launchDurationSeconds: number,
	maxStartupInterruptions: number,
	startupInterruptionsUsed: number,
	componentsById: { [string]: ComponentRecord },
	boardedByUserId: { [number]: boolean? },
	boardedOrder: { number },
	operatorUserId: number?,
	startupEndsAt: number?,
	launchEndsAt: number?,
	departedAt: number?,
	lastReason: string?,
	lastAlert: any?,
}

export type Transition = {
	accepted: boolean,
	reason: string,
	state: State,
	alert: any?,
}

local function cloneComponent(component: ComponentRecord): ComponentRecord
	return {
		componentId = component.componentId,
		required = component.required,
		state = component.state,
		holderUserId = component.holderUserId,
		installedByUserId = component.installedByUserId,
		lastUpdatedAt = component.lastUpdatedAt,
	}
end

local function cloneState(state: State): State
	local componentsById: { [string]: ComponentRecord } = {}
	for componentId, component in pairs(state.componentsById) do
		componentsById[componentId] = cloneComponent(component)
	end

	local boardedByUserId: { [number]: boolean? } = {}
	for userId, value in pairs(state.boardedByUserId) do
		boardedByUserId[userId] = value
	end

	local boardedOrder: { number } = {}
	for _, userId in ipairs(state.boardedOrder) do
		table.insert(boardedOrder, userId)
	end

	return {
		endpointId = state.endpointId,
		phase = state.phase,
		capacity = state.capacity,
		operatorRequired = state.operatorRequired,
		startupDurationSeconds = state.startupDurationSeconds,
		launchDurationSeconds = state.launchDurationSeconds,
		maxStartupInterruptions = state.maxStartupInterruptions,
		startupInterruptionsUsed = state.startupInterruptionsUsed,
		componentsById = componentsById,
		boardedByUserId = boardedByUserId,
		boardedOrder = boardedOrder,
		operatorUserId = state.operatorUserId,
		startupEndsAt = state.startupEndsAt,
		launchEndsAt = state.launchEndsAt,
		departedAt = state.departedAt,
		lastReason = state.lastReason,
		lastAlert = state.lastAlert,
	}
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return string.len(value) > 0
end

local function normalizePositiveInt(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.max(1, math.floor(value))
end

local function normalizeNonNegativeInt(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.max(0, math.floor(value))
end

local function validNow(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	if value < 0 then
		return false
	end
	return true
end

local function countRequiredComponents(state: State): number
	local count = 0
	for _, component in pairs(state.componentsById) do
		if component.required == true then
			count += 1
		end
	end
	return count
end

local function isSatisfied(component: ComponentRecord): boolean
	return component.state == TransportEscapeState.ComponentStates.Installed
		or component.state == TransportEscapeState.ComponentStates.Delivered
end

local function countSatisfiedRequiredComponents(state: State): number
	local count = 0
	for _, component in pairs(state.componentsById) do
		if component.required == true and isSatisfied(component) then
			count += 1
		end
	end
	return count
end

local function countBoarded(state: State): number
	return #state.boardedOrder
end

local function isAssemblyReady(state: State): boolean
	local requiredCount = countRequiredComponents(state)
	if requiredCount <= 0 then
		return false
	end
	return countSatisfiedRequiredComponents(state) >= requiredCount
end

local function resolveAssemblyPhase(state: State)
	if state.phase == TransportEscapeState.EndpointPhases.Departed then
		return
	end
	if
		state.phase == TransportEscapeState.EndpointPhases.Startup
		or state.phase == TransportEscapeState.EndpointPhases.Launched
	then
		return
	end

	if isAssemblyReady(state) then
		if
			state.phase == TransportEscapeState.EndpointPhases.Idle
			or state.phase == TransportEscapeState.EndpointPhases.Assembling
		then
			state.phase = TransportEscapeState.EndpointPhases.Assembled
		end
	else
		if countRequiredComponents(state) > 0 then
			state.phase = TransportEscapeState.EndpointPhases.Assembling
		else
			state.phase = TransportEscapeState.EndpointPhases.Idle
		end
	end
end

local function transition(state: State, accepted: boolean, reason: string, alert: any?): Transition
	state.lastReason = reason
	state.lastAlert = alert
	return {
		accepted = accepted,
		reason = reason,
		state = state,
		alert = alert,
	}
end

local function mutateComponentState(
	state: State,
	componentId: string,
	nextComponentState: string,
	holderUserId: number?,
	installedByUserId: number?,
	at: number?
): Transition
	local nextState = cloneState(state)
	local component = nextState.componentsById[componentId]
	if component == nil then
		return transition(nextState, false, "component_not_found", nil)
	end

	component.state = nextComponentState
	component.holderUserId = holderUserId
	component.installedByUserId = installedByUserId
	component.lastUpdatedAt = if validNow(at) then at else nil
	nextState.componentsById[componentId] = component

	resolveAssemblyPhase(nextState)
	local alert = {
		kind = "transport_component_state_changed",
		componentId = componentId,
		componentState = nextComponentState,
		satisfiedRequiredCount = countSatisfiedRequiredComponents(nextState),
		requiredComponentCount = countRequiredComponents(nextState),
		phase = nextState.phase,
	}

	return transition(nextState, true, "accepted", alert)
end

function TransportEscapeState.NewState(config: any?): State
	local configAny = config
	local endpointId = if type(configAny) == "table" and isNonEmptyString(configAny.EndpointId)
		then configAny.EndpointId
		else "TransportEndpoint_A"

	return {
		endpointId = endpointId,
		phase = TransportEscapeState.EndpointPhases.Idle,
		capacity = normalizePositiveInt(if type(configAny) == "table" then configAny.Capacity else nil, 4),
		operatorRequired = if type(configAny) == "table" and configAny.OperatorRequired == false then false else true,
		startupDurationSeconds = normalizePositiveInt(
			if type(configAny) == "table" then configAny.StartupDurationSeconds else nil,
			5
		),
		launchDurationSeconds = normalizePositiveInt(
			if type(configAny) == "table" then configAny.LaunchDurationSeconds else nil,
			2
		),
		maxStartupInterruptions = normalizeNonNegativeInt(
			if type(configAny) == "table" then configAny.MaxStartupInterruptions else nil,
			2
		),
		startupInterruptionsUsed = 0,
		componentsById = {},
		boardedByUserId = {},
		boardedOrder = {},
		operatorUserId = nil,
		startupEndsAt = nil,
		launchEndsAt = nil,
		departedAt = nil,
		lastReason = nil,
		lastAlert = nil,
	}
end

function TransportEscapeState.RegisterRequiredComponent(state: State, componentId: string): Transition
	local nextState = cloneState(state)
	if not isNonEmptyString(componentId) then
		return transition(nextState, false, "component_id_invalid", nil)
	end

	if nextState.componentsById[componentId] ~= nil then
		return transition(nextState, false, "component_already_registered", nil)
	end

	nextState.componentsById[componentId] = {
		componentId = componentId,
		required = true,
		state = TransportEscapeState.ComponentStates.Needed,
		holderUserId = nil,
		installedByUserId = nil,
		lastUpdatedAt = nil,
	}

	resolveAssemblyPhase(nextState)
	return transition(nextState, true, "component_registered", nil)
end

function TransportEscapeState.SetComponentHeld(
	state: State,
	componentId: string,
	holderUserId: number,
	at: number?
): Transition
	if type(holderUserId) ~= "number" then
		return transition(cloneState(state), false, "holder_user_id_invalid", nil)
	end
	return mutateComponentState(state, componentId, TransportEscapeState.ComponentStates.Held, holderUserId, nil, at)
end

function TransportEscapeState.SetComponentDropped(state: State, componentId: string, at: number?): Transition
	return mutateComponentState(state, componentId, TransportEscapeState.ComponentStates.Dropped, nil, nil, at)
end

function TransportEscapeState.SetComponentInstalled(
	state: State,
	componentId: string,
	installedByUserId: number,
	at: number?
): Transition
	if type(installedByUserId) ~= "number" then
		return transition(cloneState(state), false, "installed_by_user_id_invalid", nil)
	end
	return mutateComponentState(
		state,
		componentId,
		TransportEscapeState.ComponentStates.Installed,
		nil,
		installedByUserId,
		at
	)
end

function TransportEscapeState.SetComponentLost(state: State, componentId: string, at: number?): Transition
	return mutateComponentState(state, componentId, TransportEscapeState.ComponentStates.Lost, nil, nil, at)
end

function TransportEscapeState.SetComponentRecovered(
	state: State,
	componentId: string,
	holderUserId: number,
	at: number?
): Transition
	if type(holderUserId) ~= "number" then
		return transition(cloneState(state), false, "holder_user_id_invalid", nil)
	end
	return mutateComponentState(
		state,
		componentId,
		TransportEscapeState.ComponentStates.Recovered,
		holderUserId,
		nil,
		at
	)
end

function TransportEscapeState.SetComponentBlocked(state: State, componentId: string, at: number?): Transition
	return mutateComponentState(state, componentId, TransportEscapeState.ComponentStates.Blocked, nil, nil, at)
end

function TransportEscapeState.SetComponentDelivered(
	state: State,
	componentId: string,
	deliveredByUserId: number,
	at: number?
): Transition
	if type(deliveredByUserId) ~= "number" then
		return transition(cloneState(state), false, "delivered_by_user_id_invalid", nil)
	end
	return mutateComponentState(
		state,
		componentId,
		TransportEscapeState.ComponentStates.Delivered,
		nil,
		deliveredByUserId,
		at
	)
end

function TransportEscapeState.BoardPassenger(
	state: State,
	userId: number,
	options: { asOperator: boolean? }?
): Transition
	local nextState = cloneState(state)
	if type(userId) ~= "number" then
		return transition(nextState, false, "user_id_invalid", nil)
	end

	if
		nextState.phase == TransportEscapeState.EndpointPhases.Startup
		or nextState.phase == TransportEscapeState.EndpointPhases.Launched
		or nextState.phase == TransportEscapeState.EndpointPhases.Departed
	then
		return transition(nextState, false, "boarding_closed", nil)
	end

	if not isAssemblyReady(nextState) then
		return transition(nextState, false, "transport_not_assembled", nil)
	end

	if nextState.boardedByUserId[userId] == true then
		return transition(nextState, false, "already_boarded", nil)
	end

	if countBoarded(nextState) >= nextState.capacity then
		return transition(nextState, false, "transport_full", nil)
	end

	nextState.boardedByUserId[userId] = true
	table.insert(nextState.boardedOrder, userId)

	local asOperator = false
	local optionsAny = options :: any
	if type(optionsAny) == "table" and optionsAny.asOperator == true then
		asOperator = true
	end
	if asOperator then
		if nextState.operatorUserId ~= nil then
			return transition(nextState, false, "operator_already_assigned", nil)
		end
		nextState.operatorUserId = userId
	end

	nextState.phase = TransportEscapeState.EndpointPhases.Boarding
	local alert = {
		kind = "transport_boarding_changed",
		boardedCount = countBoarded(nextState),
		capacity = nextState.capacity,
		operatorUserId = nextState.operatorUserId,
	}
	return transition(nextState, true, "accepted", alert)
end

function TransportEscapeState.UnboardPassenger(state: State, userId: number): Transition
	local nextState = cloneState(state)
	if type(userId) ~= "number" then
		return transition(nextState, false, "user_id_invalid", nil)
	end

	if
		nextState.phase == TransportEscapeState.EndpointPhases.Startup
		or nextState.phase == TransportEscapeState.EndpointPhases.Launched
	then
		return transition(nextState, false, "cannot_unboard_during_launch", nil)
	end

	if nextState.boardedByUserId[userId] ~= true then
		return transition(nextState, false, "not_boarded", nil)
	end

	nextState.boardedByUserId[userId] = nil
	local remaining: { number } = {}
	for _, boardedUserId in ipairs(nextState.boardedOrder) do
		if boardedUserId ~= userId then
			table.insert(remaining, boardedUserId)
		end
	end
	nextState.boardedOrder = remaining

	if nextState.operatorUserId == userId then
		nextState.operatorUserId = nil
	end

	nextState.phase = TransportEscapeState.EndpointPhases.Boarding
	local alert = {
		kind = "transport_boarding_changed",
		boardedCount = countBoarded(nextState),
		capacity = nextState.capacity,
		operatorUserId = nextState.operatorUserId,
	}
	return transition(nextState, true, "accepted", alert)
end

function TransportEscapeState.StartStartup(state: State, operatorUserId: number?, now: number): Transition
	local nextState = cloneState(state)
	if not validNow(now) then
		return transition(nextState, false, "invalid_now", nil)
	end

	if
		nextState.phase == TransportEscapeState.EndpointPhases.Departed
		or nextState.phase == TransportEscapeState.EndpointPhases.Launched
	then
		return transition(nextState, false, "startup_unavailable", nil)
	end

	if not isAssemblyReady(nextState) then
		return transition(nextState, false, "transport_not_assembled", nil)
	end

	if countBoarded(nextState) <= 0 then
		return transition(nextState, false, "no_passengers_boarded", nil)
	end

	if nextState.operatorRequired then
		if type(operatorUserId) ~= "number" then
			return transition(nextState, false, "operator_required", nil)
		end
		if nextState.boardedByUserId[operatorUserId] ~= true then
			return transition(nextState, false, "operator_not_boarded", nil)
		end
		nextState.operatorUserId = operatorUserId
	end

	nextState.phase = TransportEscapeState.EndpointPhases.Startup
	nextState.startupEndsAt = now + nextState.startupDurationSeconds
	nextState.launchEndsAt = nil
	local alert = {
		kind = "transport_startup_started",
		startupEndsAt = nextState.startupEndsAt,
		interruptionsRemaining = math.max(0, nextState.maxStartupInterruptions - nextState.startupInterruptionsUsed),
	}
	return transition(nextState, true, "accepted", alert)
end

function TransportEscapeState.InterruptStartup(state: State, now: number): Transition
	local nextState = cloneState(state)
	if not validNow(now) then
		return transition(nextState, false, "invalid_now", nil)
	end

	if nextState.phase ~= TransportEscapeState.EndpointPhases.Startup then
		return transition(nextState, false, "startup_not_active", nil)
	end

	if type(nextState.startupEndsAt) ~= "number" or now >= (nextState.startupEndsAt :: number) then
		return transition(nextState, false, "startup_already_resolved", nil)
	end

	if nextState.startupInterruptionsUsed >= nextState.maxStartupInterruptions then
		return transition(nextState, false, "interrupt_limit_reached", nil)
	end

	nextState.startupInterruptionsUsed += 1
	nextState.phase = TransportEscapeState.EndpointPhases.Boarding
	nextState.startupEndsAt = nil

	local alert = {
		kind = "transport_startup_interrupted",
		interruptionsUsed = nextState.startupInterruptionsUsed,
		interruptionsRemaining = math.max(0, nextState.maxStartupInterruptions - nextState.startupInterruptionsUsed),
	}

	return transition(nextState, true, "accepted", alert)
end

function TransportEscapeState.ResolveTime(state: State, now: number): Transition
	local nextState = cloneState(state)
	if not validNow(now) then
		return transition(nextState, false, "invalid_now", nil)
	end

	if nextState.phase == TransportEscapeState.EndpointPhases.Startup then
		if type(nextState.startupEndsAt) == "number" and now >= (nextState.startupEndsAt :: number) then
			nextState.phase = TransportEscapeState.EndpointPhases.Launched
			nextState.launchEndsAt = now + nextState.launchDurationSeconds
			nextState.startupEndsAt = nil
			local alert = {
				kind = "transport_launch_started",
				launchEndsAt = nextState.launchEndsAt,
			}
			return transition(nextState, true, "launch_started", alert)
		end
		return transition(nextState, true, "no_change", nil)
	end

	if nextState.phase == TransportEscapeState.EndpointPhases.Launched then
		if type(nextState.launchEndsAt) == "number" and now >= (nextState.launchEndsAt :: number) then
			nextState.phase = TransportEscapeState.EndpointPhases.Departed
			nextState.departedAt = now
			nextState.launchEndsAt = nil
			local alert = {
				kind = "transport_departed",
				departedAt = now,
			}
			return transition(nextState, true, "departed", alert)
		end
		return transition(nextState, true, "no_change", nil)
	end

	return transition(nextState, true, "no_change", nil)
end

function TransportEscapeState.ResolveDepartureOutcome(state: State, candidateTinyfolkUserIds: { number }): any
	local boardedEscapedUserIds: { number } = {}
	local unboardedRemainingUserIds: { number } = {}

	local boardedSet = state.boardedByUserId
	for _, userId in ipairs(candidateTinyfolkUserIds) do
		if boardedSet[userId] == true then
			table.insert(boardedEscapedUserIds, userId)
		else
			table.insert(unboardedRemainingUserIds, userId)
		end
	end

	table.sort(boardedEscapedUserIds)
	table.sort(unboardedRemainingUserIds)

	return {
		phase = state.phase,
		canResolve = state.phase == TransportEscapeState.EndpointPhases.Departed,
		boardedEscapedUserIds = boardedEscapedUserIds,
		unboardedRemainingUserIds = unboardedRemainingUserIds,
	}
end

function TransportEscapeState.GetSnapshot(state: State): any
	local componentIds: { string } = {}
	local components: { [string]: any } = {}
	for componentId, component in pairs(state.componentsById) do
		table.insert(componentIds, componentId)
		components[componentId] = {
			state = component.state,
			required = component.required,
			holderUserId = component.holderUserId,
			installedByUserId = component.installedByUserId,
			lastUpdatedAt = component.lastUpdatedAt,
		}
	end
	table.sort(componentIds)

	local boardedUserIds: { number } = {}
	for _, userId in ipairs(state.boardedOrder) do
		table.insert(boardedUserIds, userId)
	end

	return {
		endpointId = state.endpointId,
		phase = state.phase,
		capacity = state.capacity,
		operatorRequired = state.operatorRequired,
		operatorUserId = state.operatorUserId,
		boardedCount = countBoarded(state),
		boardedUserIds = boardedUserIds,
		requiredComponentCount = countRequiredComponents(state),
		satisfiedRequiredCount = countSatisfiedRequiredComponents(state),
		assemblyReady = isAssemblyReady(state),
		startupInterruptionsUsed = state.startupInterruptionsUsed,
		startupInterruptionsRemaining = math.max(0, state.maxStartupInterruptions - state.startupInterruptionsUsed),
		startupEndsAt = state.startupEndsAt,
		launchEndsAt = state.launchEndsAt,
		departedAt = state.departedAt,
		componentIds = componentIds,
		components = components,
		lastReason = state.lastReason,
		lastAlert = state.lastAlert,
	}
end

return TransportEscapeState
