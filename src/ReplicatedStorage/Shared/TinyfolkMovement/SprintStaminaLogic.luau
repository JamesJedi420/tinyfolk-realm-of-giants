--!strict

local SprintStaminaLogic = {}

export type SprintConfig = {
	SprintMaxStamina: number,
	SprintDrainPerSecond: number,
	SprintRegenPerSecond: number,
	SprintExhaustedRecoveryThreshold: number,
	SprintWalkSpeedMultiplier: number,
	SprintMaxWalkSpeed: number?,
}

export type SprintState = {
	stamina: number?,
	requestedSprint: boolean?,
	isSprinting: boolean?,
	isExhausted: boolean?,
	lastUpdatedAt: number?,
	lastReason: string?,
}

export type SprintEvent = {
	now: number,
	requestedSprint: boolean,
	isTinyfolk: boolean,
	hasTrait: boolean,
	hasAliveHumanoid: boolean,
	hasRootPart: boolean,
}

export type SprintSnapshot = {
	stamina: number,
	maxStamina: number,
	staminaRatio: number,
	requestedSprint: boolean,
	isSprinting: boolean,
	isExhausted: boolean,
	isBreathless: boolean,
	canSprint: boolean,
	speedMultiplier: number,
	recoveryThreshold: number,
	reason: string,
}

export type SprintResult = {
	accepted: boolean,
	reason: string,
	snapshot: SprintSnapshot,
}

local DEFAULT_MAX_STAMINA = 100
local DEFAULT_DRAIN_PER_SECOND = 25
local DEFAULT_REGEN_PER_SECOND = 20
local DEFAULT_RECOVERY_THRESHOLD = 25
local DEFAULT_SPEED_MULTIPLIER = 1.25

local function positiveNumber(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return fallback
	end
	return value
end

local function clampNumber(value: number, minimum: number, maximum: number): number
	return math.max(minimum, math.min(maximum, value))
end

local function normalizeState(state: SprintState?, config: SprintConfig): SprintState
	local maxStamina = positiveNumber(config.SprintMaxStamina, DEFAULT_MAX_STAMINA)
	local sourceState: any = state or {}
	local stamina = clampNumber(positiveNumber(sourceState.stamina, maxStamina), 0, maxStamina)
	return {
		stamina = stamina,
		requestedSprint = sourceState.requestedSprint == true,
		isSprinting = sourceState.isSprinting == true,
		isExhausted = sourceState.isExhausted == true,
		lastUpdatedAt = sourceState.lastUpdatedAt,
		lastReason = sourceState.lastReason,
	}
end

function SprintStaminaLogic.Snapshot(state: SprintState?, config: SprintConfig): SprintSnapshot
	local normalized = normalizeState(state, config)
	local maxStamina = positiveNumber(config.SprintMaxStamina, DEFAULT_MAX_STAMINA)
	local recoveryThreshold =
		clampNumber(positiveNumber(config.SprintExhaustedRecoveryThreshold, DEFAULT_RECOVERY_THRESHOLD), 0, maxStamina)
	local stamina = clampNumber(normalized.stamina or maxStamina, 0, maxStamina)
	local staminaRatio = if maxStamina > 0 then stamina / maxStamina else 0
	local exhausted = normalized.isExhausted == true or stamina <= 0
	local breathless = exhausted and stamina <= 0
	local canSprint = normalized.requestedSprint == true and not breathless and stamina > 0
	local speedMultiplier = if canSprint
		then positiveNumber(config.SprintWalkSpeedMultiplier, DEFAULT_SPEED_MULTIPLIER)
		else 1

	return {
		stamina = stamina,
		maxStamina = maxStamina,
		staminaRatio = staminaRatio,
		requestedSprint = normalized.requestedSprint == true,
		isSprinting = canSprint == true,
		isExhausted = exhausted == true,
		isBreathless = breathless == true,
		canSprint = canSprint == true,
		speedMultiplier = speedMultiplier,
		recoveryThreshold = recoveryThreshold,
		reason = normalized.lastReason or "accepted",
	}
end

function SprintStaminaLogic.ResolveTick(
	state: SprintState?,
	config: SprintConfig,
	event: SprintEvent
): (SprintState, SprintResult)
	local nextState = normalizeState(state, config)
	local now = positiveNumber(event.now, 0)
	local maxStamina = positiveNumber(config.SprintMaxStamina, DEFAULT_MAX_STAMINA)
	local drainPerSecond = positiveNumber(config.SprintDrainPerSecond, DEFAULT_DRAIN_PER_SECOND)
	local regenPerSecond = positiveNumber(config.SprintRegenPerSecond, DEFAULT_REGEN_PER_SECOND)
	local recoveryThreshold =
		clampNumber(positiveNumber(config.SprintExhaustedRecoveryThreshold, DEFAULT_RECOVERY_THRESHOLD), 0, maxStamina)
	local requestedSprint = event.requestedSprint == true
	local validSprintContext = event.isTinyfolk and event.hasTrait and event.hasAliveHumanoid and event.hasRootPart
	local lastUpdatedAt = nextState.lastUpdatedAt or now
	local deltaSeconds = math.max(now - lastUpdatedAt, 0)
	local stamina = nextState.stamina or maxStamina

	if nextState.isSprinting == true and nextState.requestedSprint == true and validSprintContext then
		stamina = math.max(stamina - (deltaSeconds * drainPerSecond), 0)
	else
		stamina = math.min(stamina + (deltaSeconds * regenPerSecond), maxStamina)
	end

	local isExhausted = nextState.isExhausted == true or stamina <= 0
	if isExhausted and stamina >= recoveryThreshold then
		isExhausted = false
	end

	local canSprint = requestedSprint and validSprintContext and not isExhausted and stamina > 0
	local isSprinting = canSprint
	local reason = "accepted"
	if not validSprintContext then
		reason = "invalid_sprint_context"
	elseif requestedSprint and stamina <= 0 then
		reason = "stamina_empty"
	elseif requestedSprint and isExhausted then
		reason = "exhausted"
	end

	nextState.stamina = stamina
	nextState.requestedSprint = requestedSprint
	nextState.isSprinting = isSprinting
	nextState.isExhausted = isExhausted
	nextState.lastUpdatedAt = now
	nextState.lastReason = reason

	local snapshot: SprintSnapshot = {
		stamina = stamina,
		maxStamina = maxStamina,
		staminaRatio = if maxStamina > 0 then stamina / maxStamina else 0,
		requestedSprint = requestedSprint,
		isSprinting = isSprinting == true,
		isExhausted = isExhausted == true,
		isBreathless = (isExhausted == true and stamina <= 0) or false,
		canSprint = canSprint == true,
		speedMultiplier = if isSprinting
			then positiveNumber(config.SprintWalkSpeedMultiplier, DEFAULT_SPEED_MULTIPLIER)
			else 1,
		recoveryThreshold = recoveryThreshold,
		reason = reason,
	}

	return nextState, { accepted = reason == "accepted", reason = reason, snapshot = snapshot }
end

return SprintStaminaLogic
