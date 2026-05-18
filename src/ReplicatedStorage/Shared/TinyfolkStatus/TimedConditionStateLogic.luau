--!strict

local TimedConditionStateLogic: any = {}

export type TimedConditionState = any
export type FearSource = any
export type TickInput = any
export type Snapshot = any

local function cloneState(state: TimedConditionState?): TimedConditionState
	local nextState: TimedConditionState = {}
	if state ~= nil then
		nextState.fearExposure = state.fearExposure
		nextState.fearPanicUntil = state.fearPanicUntil
		nextState.bleedUntil = state.bleedUntil
		nextState.stunUntil = state.stunUntil
		nextState.fluxUntil = state.fluxUntil
		nextState.lastUpdatedAt = state.lastUpdatedAt
	end
	return nextState
end

local function clamp(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function getVector3Position(value: any)
	if value == nil then
		return nil
	end

	local x = value.X
	local y = value.Y
	local z = value.Z
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end

	return x, y, z
end

local function distanceBetween(a: any, b: any): number?
	local aPositionX, aPositionY, aPositionZ = getVector3Position(a)
	local bPositionX, bPositionY, bPositionZ = getVector3Position(b)
	if
		aPositionX == nil
		or aPositionY == nil
		or aPositionZ == nil
		or bPositionX == nil
		or bPositionY == nil
		or bPositionZ == nil
	then
		return nil
	end

	local dx = (aPositionX :: number) - (bPositionX :: number)
	local dy = (aPositionY :: number) - (bPositionY :: number)
	local dz = (aPositionZ :: number) - (bPositionZ :: number)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function normalizeConditionName(conditionName: any): string?
	if type(conditionName) ~= "string" then
		return nil
	end
	local lowered = string.lower(conditionName)
	if lowered == "bleed" or lowered == "stun" or lowered == "flux" then
		return lowered
	end
	return nil
end

local function getConditionUntil(state: TimedConditionState, conditionName: string): number?
	if conditionName == "bleed" then
		return state.bleedUntil
	end
	if conditionName == "stun" then
		return state.stunUntil
	end
	if conditionName == "flux" then
		return state.fluxUntil
	end
	return nil
end

local function setConditionUntil(state: TimedConditionState, conditionName: string, untilAt: number?)
	if conditionName == "bleed" then
		state.bleedUntil = untilAt
	elseif conditionName == "stun" then
		state.stunUntil = untilAt
	elseif conditionName == "flux" then
		state.fluxUntil = untilAt
	end
end

local function getConditionSummary(snapshot: any): string
	local activeConditions = {}
	if snapshot.fearPanic then
		table.insert(activeConditions, "Fear")
	elseif snapshot.fearActive then
		table.insert(activeConditions, "Exposure")
	end
	if snapshot.bleedActive then
		table.insert(activeConditions, "Bleed")
	end
	if snapshot.stunActive then
		table.insert(activeConditions, "Stun")
	end
	if snapshot.fluxActive then
		table.insert(activeConditions, "Flux")
	end
	return table.concat(activeConditions, ",")
end

function TimedConditionStateLogic.ApplyCondition(
	state: TimedConditionState?,
	conditionName: any,
	now: number,
	durationSeconds: any,
	maxDurationSeconds: number?
): TimedConditionState
	local nextState = cloneState(state)
	local normalizedName = normalizeConditionName(conditionName)
	if normalizedName == nil then
		return nextState
	end

	local duration = type(durationSeconds) == "number" and durationSeconds == durationSeconds and durationSeconds or 0
	if duration < 0 then
		duration = 0
	end
	local durationCap = if type(maxDurationSeconds) == "number"
			and maxDurationSeconds == maxDurationSeconds
			and maxDurationSeconds > 0
		then maxDurationSeconds
		else 30
	duration = math.min(duration, durationCap)
	setConditionUntil(nextState, normalizedName, now + duration)
	return nextState
end

function TimedConditionStateLogic.ClearCondition(state: TimedConditionState?, conditionName: any): TimedConditionState
	local nextState = cloneState(state)
	local normalizedName = normalizeConditionName(conditionName)
	if normalizedName == nil then
		return nextState
	end
	setConditionUntil(nextState, normalizedName, nil)
	return nextState
end

function TimedConditionStateLogic.ResolveTick(
	state: TimedConditionState?,
	config: any,
	input: TickInput
): (TimedConditionState, Snapshot)
	local nextState = cloneState(state)
	local now = input.now
	local lastUpdatedAt = nextState.lastUpdatedAt
	local deltaSeconds = 0
	if type(lastUpdatedAt) == "number" then
		deltaSeconds = math.max(now - lastUpdatedAt, 0)
	end

	local fearRadius = math.max(tonumber(config.FearRadiusStuds) or 0, 0)
	local fearTarget = 0
	local nearestDistance: number? = nil
	local nearestUserId: number? = nil

	if input.isTinyfolk and input.hasAliveHumanoid and input.hasRootPart and fearRadius > 0 then
		local fearSources = input.nearbyFearSources or {}
		for _, source in ipairs(fearSources) do
			local distance = distanceBetween(input.position, source.position)
			if distance ~= nil and (nearestDistance == nil or distance < nearestDistance) then
				nearestDistance = distance
				nearestUserId = source.userId
			end
		end

		if nearestDistance ~= nil then
			fearTarget = clamp(1 - (nearestDistance / fearRadius), 0, 1)
		end
	end

	local currentFear = clamp(tonumber(nextState.fearExposure) or 0, 0, 1)
	local fearRampSeconds = math.max(tonumber(config.FearRampSeconds) or 0.75, 0.01)
	local fearRecoverySeconds = math.max(tonumber(config.FearRecoverySeconds) or 1.5, 0.01)
	local nextFear = currentFear
	if lastUpdatedAt == nil then
		nextFear = fearTarget
	elseif fearTarget > currentFear then
		nextFear = math.min(currentFear + (deltaSeconds / fearRampSeconds), fearTarget)
	elseif fearTarget < currentFear then
		nextFear = math.max(currentFear - (deltaSeconds / fearRecoverySeconds), fearTarget)
	end
	nextFear = clamp(nextFear, 0, 1)
	nextState.fearExposure = nextFear
	nextState.lastUpdatedAt = now

	local panicThreshold = clamp(tonumber(config.FearPanicThreshold) or 0.75, 0, 1)
	local panicRecoveryThreshold = clamp(tonumber(config.FearPanicRecoveryThreshold) or 0.4, 0, 1)
	local panicDuration = math.max(tonumber(config.FearPanicDurationSeconds) or 4, 0)
	local panicUntil = nextState.fearPanicUntil
	local panicActive = false
	if type(panicUntil) == "number" and now < panicUntil then
		panicActive = true
	end
	if nextFear >= panicThreshold and nearestDistance ~= nil then
		panicUntil = math.max(type(panicUntil) == "number" and panicUntil or 0, now + panicDuration)
		panicActive = true
	elseif
		nextFear <= panicRecoveryThreshold
		and panicActive
		and type(panicUntil) == "number"
		and now >= panicUntil
	then
		panicUntil = nil
		panicActive = false
	elseif not panicActive and nextFear < panicThreshold then
		panicUntil = nil
	end
	nextState.fearPanicUntil = panicUntil

	local function isActive(untilAt: number?): boolean
		if type(untilAt) ~= "number" then
			return false
		end
		return now < untilAt
	end

	local snapshot: Snapshot = {
		fearExposure = nextFear,
		fearExposureRatio = nextFear,
		fearActive = nextFear > 0,
		fearPanic = panicActive,
		fearPanicUntil = panicUntil,
		fearNearestGiantUserId = nearestUserId,
		fearNearestGiantDistance = nearestDistance,
		conditionSummary = "",
		bleedActive = isActive(nextState.bleedUntil),
		bleedUntil = nextState.bleedUntil,
		stunActive = isActive(nextState.stunUntil),
		stunUntil = nextState.stunUntil,
		fluxActive = isActive(nextState.fluxUntil),
		fluxUntil = nextState.fluxUntil,
	}
	snapshot.conditionSummary = getConditionSummary(snapshot)

	return nextState, snapshot
end

function TimedConditionStateLogic.Snapshot(state: TimedConditionState?, now: number): Snapshot
	local activeState = cloneState(state)
	local function isActive(untilAt: number?): boolean
		if type(untilAt) ~= "number" then
			return false
		end
		return now < untilAt
	end

	local fearExposure = clamp(tonumber(activeState.fearExposure) or 0, 0, 1)
	local snapshot: Snapshot = {
		fearExposure = fearExposure,
		fearExposureRatio = fearExposure,
		fearActive = fearExposure > 0,
		fearPanic = isActive(activeState.fearPanicUntil),
		fearPanicUntil = activeState.fearPanicUntil,
		fearNearestGiantUserId = nil,
		fearNearestGiantDistance = nil,
		conditionSummary = "",
		bleedActive = isActive(activeState.bleedUntil),
		bleedUntil = activeState.bleedUntil,
		stunActive = isActive(activeState.stunUntil),
		stunUntil = activeState.stunUntil,
		fluxActive = isActive(activeState.fluxUntil),
		fluxUntil = activeState.fluxUntil,
	}
	snapshot.conditionSummary = getConditionSummary(snapshot)
	return snapshot
end

return TimedConditionStateLogic
