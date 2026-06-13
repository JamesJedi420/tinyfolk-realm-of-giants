--!strict

local CaptivityEscapeProgressState: any = {}

CaptivityEscapeProgressState.Phases = {
	active = "active",
	suppressed = "suppressed",
	ready = "ready",
}

export type ProgressState = {
	progress: number,
	required: number,
	lastProgressAt: number?,
	struggleCooldownEndsAt: number?,
	assistCooldownEndsAt: number?,
	suppressed: boolean,
	lastReason: string?,
}

export type Snapshot = {
	progress: number,
	required: number,
	phase: string,
	suppressed: boolean,
	struggleCooldownEndsAt: number?,
	assistCooldownEndsAt: number?,
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
local DEFAULT_STRUGGLE_DELTA = 1
local DEFAULT_ASSIST_DELTA = 1
local DEFAULT_DECAY_INTERVAL = 2.5
local DEFAULT_DECAY_AMOUNT = 1

do
	local ok, captureConfig = pcall(require, "../Config/CaptureConfig")
	if ok and type(captureConfig) == "table" then
		local configAny = captureConfig :: any
		if type(configAny.StruggleProgressRequired) == "number" and configAny.StruggleProgressRequired > 0 then
			DEFAULT_REQUIRED = configAny.StruggleProgressRequired
		end
		if type(configAny.StruggleProgressPerAction) == "number" and configAny.StruggleProgressPerAction > 0 then
			DEFAULT_STRUGGLE_DELTA = configAny.StruggleProgressPerAction
		end
		if type(configAny.AllyAssistProgressBonus) == "number" and configAny.AllyAssistProgressBonus > 0 then
			DEFAULT_ASSIST_DELTA = configAny.AllyAssistProgressBonus
		end
		if
			type(configAny.StruggleProgressDecayIntervalSeconds) == "number"
			and configAny.StruggleProgressDecayIntervalSeconds > 0
		then
			DEFAULT_DECAY_INTERVAL = configAny.StruggleProgressDecayIntervalSeconds
		end
		if type(configAny.StruggleProgressDecayAmount) == "number" and configAny.StruggleProgressDecayAmount > 0 then
			DEFAULT_DECAY_AMOUNT = configAny.StruggleProgressDecayAmount
		end
	end
end

local function finiteNonNegative(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return fallback
	end
	return value
end

local function positiveInteger(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	local floored = math.floor(value)
	if floored <= 0 then
		return fallback
	end
	return floored
end

local function cloneState(state: ProgressState): ProgressState
	return {
		progress = state.progress,
		required = state.required,
		lastProgressAt = state.lastProgressAt,
		struggleCooldownEndsAt = state.struggleCooldownEndsAt,
		assistCooldownEndsAt = state.assistCooldownEndsAt,
		suppressed = state.suppressed,
		lastReason = state.lastReason,
	}
end

function CaptivityEscapeProgressState.NewState(config: any?, at: number?): ProgressState
	local required =
		positiveInteger(if config ~= nil then (config :: any).StruggleProgressRequired else nil, DEFAULT_REQUIRED)
	return {
		progress = 0,
		required = required,
		lastProgressAt = finiteNonNegative(at, 0),
		struggleCooldownEndsAt = nil,
		assistCooldownEndsAt = nil,
		suppressed = false,
		lastReason = nil,
	}
end

function CaptivityEscapeProgressState.Snapshot(state: ProgressState): Snapshot
	local isReady = state.progress >= state.required and state.suppressed ~= true
	local phase = if state.suppressed
		then CaptivityEscapeProgressState.Phases.suppressed
		elseif isReady then CaptivityEscapeProgressState.Phases.ready
		else CaptivityEscapeProgressState.Phases.active
	return {
		progress = state.progress,
		required = state.required,
		phase = phase,
		suppressed = state.suppressed,
		struggleCooldownEndsAt = state.struggleCooldownEndsAt,
		assistCooldownEndsAt = state.assistCooldownEndsAt,
		lastReason = state.lastReason,
		isReady = isReady,
	}
end

local function applyProgressGain(state: ProgressState, delta: number, at: number, reason: string): Result
	local nextState = cloneState(state)
	nextState.progress = math.min(nextState.progress + delta, nextState.required)
	nextState.lastProgressAt = at
	nextState.lastReason = reason
	local snapshot = CaptivityEscapeProgressState.Snapshot(nextState)
	local completed = snapshot.isReady == true
	if completed then
		nextState.lastReason = "escape_ready"
	end
	return {
		accepted = true,
		reason = if completed then "escape_ready" else reason,
		state = nextState,
		snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
		completed = completed,
	}
end

function CaptivityEscapeProgressState.ResolveStruggle(state: ProgressState, input: any, config: any?): Result
	local nextState = cloneState(state)
	local at = finiteNonNegative(if type(input) == "table" then input.now else nil, 0)
	local allyBonusPerAlly =
		finiteNonNegative(if config ~= nil then (config :: any).StruggleAllyProgressBonusPerAlly else nil, 0)
	local allyBonus = finiteNonNegative(if type(input) == "table" then input.nearbyAllyCount else nil, 0)
		* allyBonusPerAlly

	if nextState.suppressed == true then
		nextState.lastReason = "escape_suppressed_contained"
		return {
			accepted = false,
			reason = "escape_suppressed_contained",
			state = nextState,
			snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
			completed = false,
		}
	end

	if type(nextState.struggleCooldownEndsAt) == "number" and at < (nextState.struggleCooldownEndsAt :: number) then
		nextState.lastReason = "struggle_cooldown"
		return {
			accepted = false,
			reason = "struggle_cooldown",
			state = nextState,
			snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
			completed = false,
		}
	end

	local struggleDelta = finiteNonNegative(
		if config ~= nil then (config :: any).StruggleProgressPerAction else nil,
		DEFAULT_STRUGGLE_DELTA
	)
	local cooldownSeconds =
		finiteNonNegative(if config ~= nil then (config :: any).StruggleActionCooldownSeconds else nil, 0.35)
	nextState.struggleCooldownEndsAt = at + cooldownSeconds

	return applyProgressGain(nextState, struggleDelta + allyBonus, at, "struggle_progress")
end

function CaptivityEscapeProgressState.ResolveAllyAssist(state: ProgressState, input: any, config: any?): Result
	local nextState = cloneState(state)
	local at = finiteNonNegative(if type(input) == "table" then input.now else nil, 0)

	if nextState.suppressed == true then
		nextState.lastReason = "escape_suppressed_contained"
		return {
			accepted = false,
			reason = "escape_suppressed_contained",
			state = nextState,
			snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
			completed = false,
		}
	end

	if type(nextState.assistCooldownEndsAt) == "number" and at < (nextState.assistCooldownEndsAt :: number) then
		nextState.lastReason = "ally_assist_cooldown"
		return {
			accepted = false,
			reason = "ally_assist_cooldown",
			state = nextState,
			snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
			completed = false,
		}
	end

	local assistDelta =
		finiteNonNegative(if config ~= nil then (config :: any).AllyAssistProgressBonus else nil, DEFAULT_ASSIST_DELTA)
	local cooldownSeconds =
		finiteNonNegative(if config ~= nil then (config :: any).AllyAssistCooldownSeconds else nil, 0.5)
	nextState.assistCooldownEndsAt = at + cooldownSeconds

	return applyProgressGain(nextState, assistDelta, at, "ally_assist_progress")
end

function CaptivityEscapeProgressState.ResolveDecay(state: ProgressState, now: any, config: any?): Result
	local nextState = cloneState(state)
	local at = finiteNonNegative(now, 0)

	if nextState.suppressed == true or nextState.progress <= 0 then
		return {
			accepted = true,
			reason = "decay_not_applicable",
			state = nextState,
			snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
			completed = false,
		}
	end

	local decayInterval = finiteNonNegative(
		if config ~= nil then (config :: any).StruggleProgressDecayIntervalSeconds else nil,
		DEFAULT_DECAY_INTERVAL
	)
	local decayAmount = finiteNonNegative(
		if config ~= nil then (config :: any).StruggleProgressDecayAmount else nil,
		DEFAULT_DECAY_AMOUNT
	)
	local lastAt = finiteNonNegative(nextState.lastProgressAt, at)
	local elapsed = at - lastAt
	if elapsed < decayInterval then
		return {
			accepted = true,
			reason = "decay_not_due",
			state = nextState,
			snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
			completed = false,
		}
	end

	local decaySteps = math.floor(elapsed / decayInterval)
	if decaySteps <= 0 then
		return {
			accepted = true,
			reason = "decay_not_due",
			state = nextState,
			snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
			completed = false,
		}
	end

	nextState.progress = math.max(0, nextState.progress - (decaySteps * decayAmount))
	nextState.lastProgressAt = lastAt + (decaySteps * decayInterval)
	nextState.lastReason = "progress_decayed"
	return {
		accepted = true,
		reason = "progress_decayed",
		state = nextState,
		snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
		completed = false,
	}
end

function CaptivityEscapeProgressState.ResolveSuppression(state: ProgressState, now: any): Result
	local nextState = cloneState(state)
	nextState.progress = 0
	nextState.suppressed = true
	nextState.lastProgressAt = finiteNonNegative(now, finiteNonNegative(nextState.lastProgressAt, 0))
	nextState.struggleCooldownEndsAt = nil
	nextState.assistCooldownEndsAt = nil
	nextState.lastReason = "containment_suppressed"
	return {
		accepted = true,
		reason = "containment_suppressed",
		state = nextState,
		snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
		completed = false,
	}
end

function CaptivityEscapeProgressState.ResolveAntiGuardingCounterplay(state: ProgressState, now: any): Result
	local nextState = cloneState(state)
	local at = finiteNonNegative(now, 0)
	nextState.suppressed = false
	nextState.progress = nextState.required
	nextState.lastProgressAt = at
	nextState.struggleCooldownEndsAt = nil
	nextState.assistCooldownEndsAt = nil
	nextState.lastReason = "anti_guarding_counterplay"
	local snapshot = CaptivityEscapeProgressState.Snapshot(nextState)
	return {
		accepted = true,
		reason = "anti_guarding_counterplay",
		state = nextState,
		snapshot = snapshot,
		completed = snapshot.isReady == true,
	}
end

function CaptivityEscapeProgressState.ResolveReset(state: ProgressState, now: any, reason: string?): Result
	local nextState = cloneState(state)
	local resolvedReason = if type(reason) == "string" then reason else "progress_reset"
	nextState.progress = 0
	nextState.suppressed = false
	nextState.lastProgressAt = finiteNonNegative(now, 0)
	nextState.struggleCooldownEndsAt = nil
	nextState.assistCooldownEndsAt = nil
	nextState.lastReason = resolvedReason
	return {
		accepted = true,
		reason = resolvedReason,
		state = nextState,
		snapshot = CaptivityEscapeProgressState.Snapshot(nextState),
		completed = false,
	}
end

return CaptivityEscapeProgressState
