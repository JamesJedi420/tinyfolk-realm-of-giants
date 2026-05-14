--!strict

local PostCrossingBurstLogic = {}

export type BurstConfig = {
	BurstWalkSpeedBonus: number,
	BurstDurationSeconds: number,
	CooldownSeconds: number,
	SharedBurstCooldownSeconds: number,
	TraceCostDurationSeconds: number,
	TraceCostReason: string,
	MaxBurstWalkSpeed: number?,
}

export type BurstState = {
	burstActiveUntil: number?,
	burstCooldownUntil: number?,
	sharedBurstCooldownUntil: number?,
	traceCostUntil: number?,
	lastCrossingRouteId: string?,
	lastBurstReason: string?,
}

export type CrossingEvent = {
	now: number,
	validCrossing: boolean,
	routeId: string?,
	isTinyfolk: boolean,
	hasTrait: boolean,
	hasAliveHumanoid: boolean,
	hasRootPart: boolean,
	currentWalkSpeed: number?,
	baseWalkSpeed: number?,
}

export type BurstOutcome = {
	accepted: boolean,
	reason: string,
	targetWalkSpeed: number?,
	restoreWalkSpeed: number?,
	burstActiveUntil: number?,
	burstCooldownUntil: number?,
	sharedBurstCooldownUntil: number?,
	traceCostUntil: number?,
	traceCostReason: string?,
}

export type StateSnapshot = {
	burstActive: boolean,
	traceCostActive: boolean,
	burstActiveUntil: number?,
	burstCooldownUntil: number?,
	sharedBurstCooldownUntil: number?,
	traceCostUntil: number?,
	traceCostReason: string?,
	lastCrossingRouteId: string?,
	lastBurstReason: string?,
}

local function cloneState(state: BurstState?): BurstState
	if state == nil then
		return {}
	end

	return {
		burstActiveUntil = state.burstActiveUntil,
		burstCooldownUntil = state.burstCooldownUntil,
		sharedBurstCooldownUntil = state.sharedBurstCooldownUntil,
		traceCostUntil = state.traceCostUntil,
		lastCrossingRouteId = state.lastCrossingRouteId,
		lastBurstReason = state.lastBurstReason,
	}
end

local function positiveNumber(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return fallback
	end
	return value
end

local function resolveTargetWalkSpeed(config: BurstConfig, event: CrossingEvent): (number, number)
	local currentWalkSpeed = positiveNumber(event.currentWalkSpeed, 16)
	local baseWalkSpeed = positiveNumber(event.baseWalkSpeed, currentWalkSpeed)
	local target = baseWalkSpeed + positiveNumber(config.BurstWalkSpeedBonus, 0)
	local maxBurstWalkSpeed = config.MaxBurstWalkSpeed

	if type(maxBurstWalkSpeed) == "number" and maxBurstWalkSpeed == maxBurstWalkSpeed then
		target = math.min(target, maxBurstWalkSpeed)
	end

	if target < currentWalkSpeed then
		target = currentWalkSpeed
	end

	return target, currentWalkSpeed
end

function PostCrossingBurstLogic.ResolveCrossing(
	state: BurstState?,
	config: BurstConfig,
	event: CrossingEvent
): (BurstState, BurstOutcome)
	local nextState = cloneState(state)
	local now = event.now

	if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge or now < 0 then
		return nextState, { accepted = false, reason = "invalid_now" }
	end

	if not event.validCrossing then
		return nextState, { accepted = false, reason = "invalid_crossing" }
	end

	if not event.isTinyfolk then
		return nextState, { accepted = false, reason = "requester_not_tinyfolk" }
	end

	if not event.hasTrait then
		return nextState, { accepted = false, reason = "trait_not_enabled" }
	end

	if not event.hasAliveHumanoid then
		return nextState, { accepted = false, reason = "humanoid_not_alive" }
	end

	if not event.hasRootPart then
		return nextState, { accepted = false, reason = "humanoid_root_missing" }
	end

	if type(nextState.burstActiveUntil) == "number" and now < nextState.burstActiveUntil then
		return nextState, { accepted = false, reason = "burst_already_active" }
	end

	if type(nextState.burstCooldownUntil) == "number" and now < nextState.burstCooldownUntil then
		return nextState, { accepted = false, reason = "burst_cooldown" }
	end

	if type(nextState.sharedBurstCooldownUntil) == "number" and now < nextState.sharedBurstCooldownUntil then
		return nextState, { accepted = false, reason = "shared_burst_cooldown" }
	end

	local burstDuration = positiveNumber(config.BurstDurationSeconds, 0)
	local cooldownDuration = positiveNumber(config.CooldownSeconds, 0)
	local sharedCooldownDuration = positiveNumber(config.SharedBurstCooldownSeconds, cooldownDuration)
	local traceDuration = positiveNumber(config.TraceCostDurationSeconds, 0)
	local traceReason = if type(config.TraceCostReason) == "string" and config.TraceCostReason ~= ""
		then config.TraceCostReason
		else "PostCrossingBurst"

	local burstActiveUntil = now + burstDuration
	local burstCooldownUntil = now + cooldownDuration
	local sharedBurstCooldownUntil = now + sharedCooldownDuration
	local traceCostUntil = burstActiveUntil + traceDuration
	local targetWalkSpeed, restoreWalkSpeed = resolveTargetWalkSpeed(config, event)

	nextState.burstActiveUntil = burstActiveUntil
	nextState.burstCooldownUntil = burstCooldownUntil
	nextState.sharedBurstCooldownUntil = sharedBurstCooldownUntil
	nextState.traceCostUntil = traceCostUntil
	nextState.lastCrossingRouteId = event.routeId
	nextState.lastBurstReason = traceReason

	return nextState, {
		accepted = true,
		reason = "accepted",
		targetWalkSpeed = targetWalkSpeed,
		restoreWalkSpeed = restoreWalkSpeed,
		burstActiveUntil = burstActiveUntil,
		burstCooldownUntil = burstCooldownUntil,
		sharedBurstCooldownUntil = sharedBurstCooldownUntil,
		traceCostUntil = traceCostUntil,
		traceCostReason = traceReason,
	}
end

function PostCrossingBurstLogic.Snapshot(state: BurstState?, now: number): StateSnapshot
	local source = state or {}
	local burstActiveUntil = source.burstActiveUntil
	local traceCostUntil = source.traceCostUntil
	local burstActive = type(burstActiveUntil) == "number" and now < burstActiveUntil
	local traceCostActive = type(traceCostUntil) == "number" and now < traceCostUntil

	return {
		burstActive = burstActive,
		traceCostActive = traceCostActive,
		burstActiveUntil = burstActiveUntil,
		burstCooldownUntil = source.burstCooldownUntil,
		sharedBurstCooldownUntil = source.sharedBurstCooldownUntil,
		traceCostUntil = traceCostUntil,
		traceCostReason = if traceCostActive then source.lastBurstReason else nil,
		lastCrossingRouteId = source.lastCrossingRouteId,
		lastBurstReason = source.lastBurstReason,
	}
end

return PostCrossingBurstLogic
