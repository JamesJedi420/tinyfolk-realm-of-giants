--!strict

local ContainmentZoneEscapeState: any = {}

export type ProgressState = {
	progress: number,
	required: number,
	lastProgressAt: number?,
	actionCooldownEndsAt: number?,
	lastReason: string?,
}

export type Snapshot = {
	progress: number,
	required: number,
	actionCooldownEndsAt: number?,
	lastReason: string?,
	isReady: boolean,
}

export type Result = {
	accepted: boolean,
	reason: string,
	state: ProgressState,
	snapshot: Snapshot,
	completed: boolean,
}

local DEFAULT_REQUIRED = 5
local DEFAULT_ACTION_DELTA = 1
local DEFAULT_COOLDOWN_SECONDS = 0.35

local function finiteNonNegative(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return fallback
	end
	return value
end

local function resolveRequired(config: any): number
	if type(config) == "table" and type(config.ContainmentEscapeProgressRequired) == "number" then
		return math.max(1, math.floor(config.ContainmentEscapeProgressRequired))
	end
	return DEFAULT_REQUIRED
end

local function resolveCooldown(config: any): number
	if type(config) == "table" and type(config.ContainmentEscapeActionCooldownSeconds) == "number" then
		return math.max(0, config.ContainmentEscapeActionCooldownSeconds)
	end
	return DEFAULT_COOLDOWN_SECONDS
end

local function snapshotFromState(state: ProgressState): Snapshot
	return {
		progress = state.progress,
		required = state.required,
		actionCooldownEndsAt = state.actionCooldownEndsAt,
		lastReason = state.lastReason,
		isReady = state.progress >= state.required,
	}
end

function ContainmentZoneEscapeState.NewState(config: any?, now: number?): ProgressState
	local resolvedNow = if type(now) == "number" then now else 0
	return {
		progress = 0,
		required = resolveRequired(config),
		lastProgressAt = resolvedNow,
		actionCooldownEndsAt = nil,
		lastReason = "initialized",
	}
end

function ContainmentZoneEscapeState.Snapshot(state: ProgressState?): Snapshot?
	if state == nil then
		return nil
	end
	return snapshotFromState(state)
end

function ContainmentZoneEscapeState.ResolveEscapeAction(state: ProgressState, now: number, config: any?): Result
	local resolvedNow = finiteNonNegative(now, 0)
	local nextState: ProgressState = {
		progress = state.progress,
		required = state.required,
		lastProgressAt = state.lastProgressAt,
		actionCooldownEndsAt = state.actionCooldownEndsAt,
		lastReason = state.lastReason,
	}

	if type(nextState.actionCooldownEndsAt) == "number" and resolvedNow < nextState.actionCooldownEndsAt then
		nextState.lastReason = "request_cooldown"
		return {
			accepted = false,
			reason = "request_cooldown",
			state = nextState,
			snapshot = snapshotFromState(nextState),
			completed = false,
		}
	end

	local cooldownSeconds = resolveCooldown(config)
	nextState.progress = math.min(nextState.required, nextState.progress + DEFAULT_ACTION_DELTA)
	nextState.lastProgressAt = resolvedNow
	nextState.actionCooldownEndsAt = resolvedNow + cooldownSeconds
	nextState.lastReason = "escape_progress"

	local completed = nextState.progress >= nextState.required
	return {
		accepted = true,
		reason = if completed then "contained_escape_completed" else "escape_progress",
		state = nextState,
		snapshot = snapshotFromState(nextState),
		completed = completed,
	}
end

function ContainmentZoneEscapeState.Clear(state: ProgressState?): ProgressState
	return ContainmentZoneEscapeState.NewState(nil, 0)
end

return ContainmentZoneEscapeState
