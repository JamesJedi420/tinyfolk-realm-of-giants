--!strict

local ContainmentRewardResolver: any = {}

local DEFAULT_PAIR_RETENTION_SECONDS = 300

local VALID_END_REASONS = {
	released = true,
	rescued = true,
	escaped = true,
	timeout = true,
	logout = true,
	safe_return = true,
}

local PAIR_MULTIPLIERS = { 1, 0.5, 0.25 }

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value % 1 == 0
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
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

local function defaultNow(): number
	return os.clock()
end

local function makeMemoryIdempotencyStore(): any
	local recordsByOperationId: { [string]: string } = {}
	return {
		TryBegin = function(operationId: any): any
			local id = nonEmptyString(operationId)
			if id == nil then
				return { accepted = false, reason = "operation_id_invalid" }
			end
			local status = recordsByOperationId[id]
			if status == "completed" then
				return { accepted = true, reason = "accepted", status = "completed" }
			end
			if status == "processing" then
				return { accepted = false, reason = "already_processing", status = "processing" }
			end
			recordsByOperationId[id] = "processing"
			return { accepted = true, reason = "accepted", status = "begun" }
		end,
		MarkCompleted = function(operationId: any): any
			local id = nonEmptyString(operationId)
			if id == nil then
				return { accepted = false, reason = "operation_id_invalid" }
			end
			recordsByOperationId[id] = "completed"
			return { accepted = true, reason = "accepted", status = "completed" }
		end,
		ReleaseProcessing = function(operationId: any): any
			local id = nonEmptyString(operationId)
			if id ~= nil and recordsByOperationId[id] == "processing" then
				recordsByOperationId[id] = nil
			end
			return { accepted = true, reason = "accepted", status = "released" }
		end,
	}
end

local function makeOperationId(input: any): string?
	local explicit = nonEmptyString(input.operationId)
	if explicit ~= nil then
		return explicit
	end
	if not isPositiveInteger(input.custodianUserId) or not isPositiveInteger(input.targetUserId) then
		return nil
	end
	local endReason = nonEmptyString(input.endReason)
	if endReason == nil or VALID_END_REASONS[endReason] ~= true then
		return nil
	end
	if not isFiniteNumber(input.captureStartedAt) or input.captureStartedAt < 0 then
		return nil
	end
	return string.format(
		"containment-%s-%d-%d-%d",
		endReason,
		input.custodianUserId,
		input.targetUserId,
		math.floor(input.captureStartedAt * 1000 + 0.5)
	)
end

local function makePairKey(custodianUserId: number, targetUserId: number): string
	return string.format("%d|%d", custodianUserId, targetUserId)
end

function ContainmentRewardResolver.Create(deps: any?): any
	local depsAny = if type(deps) == "table" then deps else {}
	local nowFn = if type(depsAny.now) == "function" then depsAny.now else defaultNow
	local pairRetentionSeconds = if isFiniteNumber(depsAny.pairRetentionSeconds)
			and depsAny.pairRetentionSeconds > 0
		then depsAny.pairRetentionSeconds
		else DEFAULT_PAIR_RETENTION_SECONDS
	local idempotencyStore = if type(depsAny.idempotencyStore) == "table"
		then depsAny.idempotencyStore
		else makeMemoryIdempotencyStore()
	local pairHistoryByKey: { [string]: { count: number, lastAt: number } } = {}

	local resolver: any = {}

	local function getGlobalApi(name: string): any?
		local globalEnv: any = getfenv()
		if type(globalEnv) == "table" and type(rawget(globalEnv, name)) == "table" then
			return rawget(globalEnv, name)
		end
		if type(_G) == "table" and type(rawget(_G, name)) == "table" then
			return rawget(_G, name)
		end
		return nil
	end

	local function requestScore(custodianUserId: number, endedAt: number, metadata: any): any
		local scoreApi = if type(depsAny.scoreApi) == "table"
			then depsAny.scoreApi
			else getGlobalApi("_ScoreService_QueryAPI")
		if type(scoreApi) ~= "table" or type(scoreApi.RequestScoreEvent) ~= "function" then
			return { accepted = false, reason = "score_api_unavailable" }
		end
		local ok, result = pcall(scoreApi.RequestScoreEvent, custodianUserId, "containment_reward", endedAt, metadata)
		if not ok or type(result) ~= "table" then
			return { accepted = false, reason = "score_request_failed" }
		end
		return result
	end

	local function readPairCount(pairKey: string, endedAt: number): number
		local history = pairHistoryByKey[pairKey]
		if history == nil then
			return 0
		end
		if endedAt - history.lastAt > pairRetentionSeconds then
			pairHistoryByKey[pairKey] = nil
			return 0
		end
		return history.count
	end

	local function writePairCount(pairKey: string, endedAt: number, count: number)
		pairHistoryByKey[pairKey] = {
			count = count,
			lastAt = endedAt,
		}
	end

	function resolver.Resolve(input: any): any
		if type(input) ~= "table" then
			return { accepted = false, reason = "input_invalid" }
		end
		if not isPositiveInteger(input.custodianUserId) then
			return { accepted = false, reason = "custodian_user_id_invalid" }
		end
		if not isPositiveInteger(input.targetUserId) then
			return { accepted = false, reason = "target_user_id_invalid" }
		end
		local endReason = nonEmptyString(input.endReason)
		if endReason == nil or VALID_END_REASONS[endReason] ~= true then
			return { accepted = false, reason = "end_reason_invalid" }
		end
		local captureStartedAt = input.captureStartedAt
		if not isFiniteNumber(captureStartedAt) or captureStartedAt < 0 then
			return { accepted = false, reason = "capture_started_at_invalid" }
		end
		local endedAt = if isFiniteNumber(input.endedAt) and input.endedAt >= 0 then input.endedAt else nowFn()
		local custodyWindowSeconds = if isFiniteNumber(input.custodyWindowSeconds)
				and input.custodyWindowSeconds > 0
			then input.custodyWindowSeconds
			else 1
		local operationId = makeOperationId(input)
		if operationId == nil then
			return { accepted = false, reason = "operation_id_invalid" }
		end

		local beginOk, beginResult = pcall(idempotencyStore.TryBegin, operationId)
		if not beginOk or type(beginResult) ~= "table" then
			return { accepted = false, reason = "idempotency_try_begin_failed", operationId = operationId }
		end
		if beginResult.accepted == true and beginResult.status == "completed" then
			return {
				accepted = true,
				reason = "duplicate_completed",
				operationId = operationId,
				duplicate = true,
				rewardGranted = false,
				endReason = endReason,
			}
		end
		if beginResult.accepted ~= true then
			return {
				accepted = false,
				reason = tostring(beginResult.reason or "already_processing"),
				operationId = operationId,
				duplicate = beginResult.status == "processing",
				rewardGranted = false,
				endReason = endReason,
			}
		end

		local pairKey = makePairKey(input.custodianUserId, input.targetUserId)
		local previousPairCount = readPairCount(pairKey, endedAt)
		local nextPairCount = previousPairCount + 1
		local pairMultiplier = PAIR_MULTIPLIERS[nextPairCount]
		local heldSeconds = math.max(0, endedAt - captureStartedAt)
		local baseRatio = clamp(heldSeconds / custodyWindowSeconds, 0.25, 1)

		if pairMultiplier == nil then
			local completedOk, completedResult = pcall(idempotencyStore.MarkCompleted, operationId)
			if not completedOk or type(completedResult) ~= "table" or completedResult.accepted ~= true then
				return {
					accepted = false,
					reason = "idempotency_mark_completed_failed",
					operationId = operationId,
					cleanupDebt = true,
					rewardGranted = false,
					endReason = endReason,
				}
			end
			return {
				accepted = true,
				reason = "pair_reward_cap_reached",
				operationId = operationId,
				duplicate = false,
				rewardGranted = false,
				heldSeconds = heldSeconds,
				contributionRatio = 0,
				pairRewardCount = nextPairCount,
				endReason = endReason,
			}
		end

		local contributionRatio = clamp(baseRatio * pairMultiplier, 0.25, 1)
		writePairCount(pairKey, endedAt, nextPairCount)
		local metadata = {
			operationId = operationId,
			targetUserId = input.targetUserId,
			endReason = endReason,
			captureStartedAt = captureStartedAt,
			captureExpiresAt = input.captureExpiresAt,
			endedAt = endedAt,
			heldSeconds = heldSeconds,
			contributionRatio = contributionRatio,
			pairRewardCount = nextPairCount,
		}
		local scoreResult = requestScore(input.custodianUserId, endedAt, metadata)

		local completedOk, completedResult = pcall(idempotencyStore.MarkCompleted, operationId)
		if not completedOk or type(completedResult) ~= "table" or completedResult.accepted ~= true then
			return {
				accepted = false,
				reason = "idempotency_mark_completed_failed",
				operationId = operationId,
				cleanupDebt = true,
				rewardGranted = type(scoreResult) == "table" and scoreResult.accepted == true,
				scoreAccepted = type(scoreResult) == "table" and scoreResult.accepted == true,
				scoreReason = if type(scoreResult) == "table" then scoreResult.reason else "score_result_invalid",
				heldSeconds = heldSeconds,
				contributionRatio = contributionRatio,
				pairRewardCount = nextPairCount,
				endReason = endReason,
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			operationId = operationId,
			duplicate = false,
			rewardGranted = type(scoreResult) == "table" and scoreResult.accepted == true,
			scoreAccepted = type(scoreResult) == "table" and scoreResult.accepted == true,
			scoreReason = if type(scoreResult) == "table" then scoreResult.reason else "score_result_invalid",
			heldSeconds = heldSeconds,
			contributionRatio = contributionRatio,
			pairRewardCount = nextPairCount,
			endReason = endReason,
		}
	end

	return resolver
end

return ContainmentRewardResolver
