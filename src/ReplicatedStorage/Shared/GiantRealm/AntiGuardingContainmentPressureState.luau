--!strict

local AntiGuardingContainmentPressureState = {}

AntiGuardingContainmentPressureState.Phases = {
	grace = "grace",
	accumulating = "accumulating",
	decaying = "decaying",
	ready = "ready",
	consumed = "consumed",
}

AntiGuardingContainmentPressureState.CounterplayOutcomes = {
	escape_progress_release = "escape_progress_release",
}

export type PressureState = {
	containedAt: number,
	pressure: number,
	lastTickAt: number?,
	counterplayConsumed: boolean,
	lastReason: string?,
}

export type Snapshot = {
	pressure: number,
	phase: string,
	graceEndsAt: number,
	counterplayReady: boolean,
	counterplayConsumed: boolean,
	lastReason: string?,
}

export type TickInput = {
	now: number,
	containedAt: number,
	custodianInProximity: boolean,
}

export type TickResult = {
	state: PressureState,
	snapshot: Snapshot,
	counterplayReady: boolean,
}

local DEFAULT_GRACE_WINDOW_SECONDS = 3
local DEFAULT_PROXIMITY_RADIUS_STUDS = 10
local DEFAULT_PRESSURE_FILL_SECONDS = 6
local DEFAULT_PRESSURE_DECAY_PER_SECOND = 0.2

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function finiteNonNegative(value: any, fallback: number): number
	if not isFiniteNumber(value) or (value :: number) < 0 then
		return fallback
	end
	return value :: number
end

local function positiveNumber(value: any, fallback: number): number
	if not isFiniteNumber(value) or (value :: number) <= 0 then
		return fallback
	end
	return value :: number
end

local function getGraceWindowSeconds(config: any): number
	return positiveNumber(
		if config ~= nil then (config :: any).AntiGuardingGraceWindowSeconds else nil,
		DEFAULT_GRACE_WINDOW_SECONDS
	)
end

local function getPressureFillSeconds(config: any): number
	return positiveNumber(
		if config ~= nil then (config :: any).AntiGuardingPressureFillSeconds else nil,
		DEFAULT_PRESSURE_FILL_SECONDS
	)
end

local function getPressureDecayPerSecond(config: any): number
	return positiveNumber(
		if config ~= nil then (config :: any).AntiGuardingPressureDecayPerSecond else nil,
		DEFAULT_PRESSURE_DECAY_PER_SECOND
	)
end

function AntiGuardingContainmentPressureState.GetProximityRadiusStuds(config: any): number
	return positiveNumber(
		if config ~= nil then (config :: any).AntiGuardingProximityRadiusStuds else nil,
		DEFAULT_PROXIMITY_RADIUS_STUDS
	)
end

function AntiGuardingContainmentPressureState.GetCounterplayOutcome(config: any): string
	local configured = if config ~= nil then (config :: any).AntiGuardingCounterplayOutcome else nil
	if type(configured) == "string" and configured ~= "" then
		return configured
	end
	return AntiGuardingContainmentPressureState.CounterplayOutcomes.escape_progress_release
end

local function cloneState(state: PressureState): PressureState
	return {
		containedAt = state.containedAt,
		pressure = state.pressure,
		lastTickAt = state.lastTickAt,
		counterplayConsumed = state.counterplayConsumed,
		lastReason = state.lastReason,
	}
end

function AntiGuardingContainmentPressureState.NewState(containedAt: number, at: number?): PressureState
	return {
		containedAt = containedAt,
		pressure = 0,
		lastTickAt = finiteNonNegative(at, containedAt),
		counterplayConsumed = false,
		lastReason = nil,
	}
end

local function resolvePhase(state: PressureState, now: number, graceEndsAt: number): string
	if state.counterplayConsumed == true then
		return AntiGuardingContainmentPressureState.Phases.consumed
	end
	if now < graceEndsAt then
		return AntiGuardingContainmentPressureState.Phases.grace
	end
	if state.pressure >= 1 then
		return AntiGuardingContainmentPressureState.Phases.ready
	end
	if state.lastReason == "pressure_decaying" then
		return AntiGuardingContainmentPressureState.Phases.decaying
	end
	return AntiGuardingContainmentPressureState.Phases.accumulating
end

function AntiGuardingContainmentPressureState.Snapshot(state: PressureState, now: number, config: any?): Snapshot
	local graceEndsAt = state.containedAt + getGraceWindowSeconds(config)
	local phase = resolvePhase(state, now, graceEndsAt)
	return {
		pressure = state.pressure,
		phase = phase,
		graceEndsAt = graceEndsAt,
		counterplayReady = phase == AntiGuardingContainmentPressureState.Phases.ready,
		counterplayConsumed = state.counterplayConsumed == true,
		lastReason = state.lastReason,
	}
end

function AntiGuardingContainmentPressureState.ResolveTick(
	state: PressureState,
	input: TickInput,
	config: any?
): TickResult
	local nextState = cloneState(state)
	local at = finiteNonNegative(input.now, nextState.containedAt)
	local containedAt = finiteNonNegative(input.containedAt, nextState.containedAt)
	nextState.containedAt = containedAt

	if nextState.counterplayConsumed == true then
		nextState.lastTickAt = at
		local snapshot = AntiGuardingContainmentPressureState.Snapshot(nextState, at, config)
		return {
			state = nextState,
			snapshot = snapshot,
			counterplayReady = false,
		}
	end

	local graceEndsAt = containedAt + getGraceWindowSeconds(config)
	local lastTickAt = finiteNonNegative(nextState.lastTickAt, containedAt)
	local delta = math.max(0, at - lastTickAt)
	nextState.lastTickAt = at

	if at < graceEndsAt then
		nextState.pressure = 0
		nextState.lastReason = "grace_window"
		local snapshot = AntiGuardingContainmentPressureState.Snapshot(nextState, at, config)
		return {
			state = nextState,
			snapshot = snapshot,
			counterplayReady = false,
		}
	end

	if delta > 0 then
		if input.custodianInProximity == true then
			local fillSeconds = getPressureFillSeconds(config)
			nextState.pressure = math.min(1, nextState.pressure + (delta / fillSeconds))
			nextState.lastReason = if nextState.pressure >= 1 then "pressure_ready" else "pressure_accumulating"
		else
			local decayRate = getPressureDecayPerSecond(config)
			nextState.pressure = math.max(0, nextState.pressure - (delta * decayRate))
			nextState.lastReason = if nextState.pressure > 0 then "pressure_decaying" else "pressure_idle"
		end
	end

	local snapshot = AntiGuardingContainmentPressureState.Snapshot(nextState, at, config)
	return {
		state = nextState,
		snapshot = snapshot,
		counterplayReady = snapshot.counterplayReady == true,
	}
end

function AntiGuardingContainmentPressureState.ResolveCounterplayConsumed(
	state: PressureState,
	at: number
): PressureState
	local nextState = cloneState(state)
	nextState.counterplayConsumed = true
	nextState.pressure = 1
	nextState.lastTickAt = finiteNonNegative(at, nextState.containedAt)
	nextState.lastReason = "counterplay_consumed"
	return nextState
end

function AntiGuardingContainmentPressureState.IsCustodianInProximity(distanceStuds: any, config: any?): boolean
	if not isFiniteNumber(distanceStuds) then
		return false
	end
	return (distanceStuds :: number) <= AntiGuardingContainmentPressureState.GetProximityRadiusStuds(config)
end

return AntiGuardingContainmentPressureState
