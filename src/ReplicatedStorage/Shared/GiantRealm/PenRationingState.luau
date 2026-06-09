--!strict

local PenRationingState = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function PenRationingState.ComputeFoodCostForInterval(
	activeCaptiveCount: number,
	foodPerCaptivePerInterval: number
): number
	if not isFiniteNumber(activeCaptiveCount) or activeCaptiveCount <= 0 then
		return 0
	end
	if not isFiniteNumber(foodPerCaptivePerInterval) or foodPerCaptivePerInterval <= 0 then
		return 0
	end

	return math.floor(activeCaptiveCount) * math.floor(foodPerCaptivePerInterval)
end

function PenRationingState.CountDueTicks(
	accumulatorSeconds: number,
	deltaSeconds: number,
	intervalSeconds: number
): (number, number)
	if not isFiniteNumber(accumulatorSeconds) or accumulatorSeconds < 0 then
		accumulatorSeconds = 0
	end
	if not isFiniteNumber(deltaSeconds) or deltaSeconds < 0 then
		deltaSeconds = 0
	end
	if not isFiniteNumber(intervalSeconds) or intervalSeconds <= 0 then
		return 0, accumulatorSeconds + deltaSeconds
	end

	local nextAccumulator = accumulatorSeconds + deltaSeconds
	local dueTicks = math.floor(nextAccumulator / intervalSeconds)
	nextAccumulator -= dueTicks * intervalSeconds
	return dueTicks, nextAccumulator
end

return PenRationingState
