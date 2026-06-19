--!strict

local PenRationingState = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function PenRationingState.ComputeFoodCostForInterval(
	activeCaptiveCount: number,
	foodPerCaptivePerInterval: number,
	foodMultiplier: number?
): number
	if not isFiniteNumber(activeCaptiveCount) or activeCaptiveCount <= 0 then
		return 0
	end
	if not isFiniteNumber(foodPerCaptivePerInterval) or foodPerCaptivePerInterval <= 0 then
		return 0
	end

	local resolvedMultiplier = 1
	if isFiniteNumber(foodMultiplier) and (foodMultiplier :: number) > 0 then
		resolvedMultiplier = foodMultiplier :: number
	end
	local rawCost = math.floor(activeCaptiveCount) * math.floor(foodPerCaptivePerInterval) * resolvedMultiplier
	local roundedCost = math.max(1, math.floor(rawCost + 0.5))
	return roundedCost
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

function PenRationingState.ComputeCaptureReadinessPercent(morale: number, sureThreshold: number): number
	if not isFiniteNumber(morale) or morale <= 0 then
		return 0
	end
	if not isFiniteNumber(sureThreshold) or sureThreshold <= 0 then
		return 100
	end
	if morale >= sureThreshold then
		return 100
	end
	return math.clamp(math.floor((morale / sureThreshold) * 100 + 0.5), 0, 100)
end

function PenRationingState.ResolveCaptureMoraleCheck(
	morale: number,
	custodianUserId: number,
	targetUserId: number,
	at: number,
	sureThreshold: number,
	intimidationBonus: number?
): { allowed: boolean, reason: string }
	if not isFiniteNumber(morale) or morale <= 0 then
		return { allowed = false, reason = "custodian_morale_depleted" }
	end

	local resolvedThreshold = if isFiniteNumber(sureThreshold) and sureThreshold > 0 then sureThreshold else 50
	if morale >= resolvedThreshold then
		return { allowed = true, reason = "accepted" }
	end

	if not isFiniteNumber(custodianUserId) or not isFiniteNumber(targetUserId) or not isFiniteNumber(at) then
		return { allowed = false, reason = "custodian_morale_shaken" }
	end

	local resolvedIntimidationBonus = 1
	if isFiniteNumber(intimidationBonus) and (intimidationBonus :: number) > 0 then
		resolvedIntimidationBonus = intimidationBonus :: number
	end

	local rollSeed = math.floor(custodianUserId) * 31 + math.floor(targetUserId) * 17 + math.floor(at * 1000)
	local roll = rollSeed % 100
	local effectiveRollMorale = math.clamp(math.floor(morale * resolvedIntimidationBonus), 0, 100)
	if roll < effectiveRollMorale then
		return { allowed = true, reason = "accepted" }
	end

	return { allowed = false, reason = "custodian_morale_shaken" }
end

function PenRationingState.ApplyCaptiveShortfallStreak(currentStreak: number, increment: boolean): number
	local safeCurrent = if isFiniteNumber(currentStreak) and currentStreak >= 0 then math.floor(currentStreak) else 0
	if increment then
		return safeCurrent + 1
	end
	return 0
end

function PenRationingState.IsCaptiveStarving(shortfallStreak: number, starvingThreshold: number): boolean
	if not isFiniteNumber(shortfallStreak) or shortfallStreak <= 0 then
		return false
	end
	local resolvedThreshold = if isFiniteNumber(starvingThreshold) and starvingThreshold > 0
		then math.floor(starvingThreshold)
		else 2
	return math.floor(shortfallStreak) >= resolvedThreshold
end

function PenRationingState.ApplyMoraleDelta(
	currentMorale: number,
	delta: number,
	minMorale: number,
	maxMorale: number
): number
	local safeCurrent = if isFiniteNumber(currentMorale) then currentMorale else minMorale
	local safeDelta = if isFiniteNumber(delta) then delta else 0
	return math.clamp(safeCurrent + safeDelta, minMorale, maxMorale)
end

function PenRationingState.ShouldForceStarvationRelease(
	consecutiveShortfallTicks: number,
	starvationReleaseThreshold: number
): boolean
	if not isFiniteNumber(consecutiveShortfallTicks) or consecutiveShortfallTicks <= 0 then
		return false
	end
	if not isFiniteNumber(starvationReleaseThreshold) or starvationReleaseThreshold <= 0 then
		return false
	end
	return consecutiveShortfallTicks >= math.floor(starvationReleaseThreshold)
end

function PenRationingState.SelectStarvationReleaseTarget(captures: { any }): number?
	if type(captures) ~= "table" or #captures == 0 then
		return nil
	end

	local oldestRecord: any = nil
	for _, record in ipairs(captures) do
		if type(record) == "table" and isFiniteNumber(record.targetUserId) and isFiniteNumber(record.startedAt) then
			if oldestRecord == nil or record.startedAt < oldestRecord.startedAt then
				oldestRecord = record
			end
		end
	end

	if oldestRecord == nil then
		return nil
	end
	return oldestRecord.targetUserId
end

return PenRationingState
