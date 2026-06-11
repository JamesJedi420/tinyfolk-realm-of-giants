--!strict

local ContainmentRewardResolver: any = {}
local GiantRealmResourceState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("GiantRealmResourceState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState")
local ReputationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Reputation")
			:WaitForChild("ReputationState")
	)
	else require("../../ReplicatedStorage/Shared/Reputation/ReputationState")

local DEFAULT_PAIR_RETENTION_SECONDS = 300
local CONTAINMENT_REWARD_SKILL_ID = "custody_stewardship"

local VALID_END_REASONS = {
	released = true,
	rescued = true,
	escaped = true,
	timeout = true,
	logout = true,
	safe_return = true,
	starvation = true,
}

local PAIR_MULTIPLIERS = { 1, 0.5, 0.25 }

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
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
	local recordsByOperationId: { [string]: string? } = {}
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
	local depsAny: any = if type(deps) == "table" then deps else {}
	local nowFn = if type(depsAny.now) == "function" then depsAny.now else defaultNow
	local pairRetentionSeconds = if isFiniteNumber(depsAny.pairRetentionSeconds)
			and depsAny.pairRetentionSeconds > 0
		then depsAny.pairRetentionSeconds
		else DEFAULT_PAIR_RETENTION_SECONDS
	local idempotencyStore = if type(depsAny.idempotencyStore) == "table"
		then depsAny.idempotencyStore
		else makeMemoryIdempotencyStore()
	local pairHistoryByKey: { [string]: { count: number, lastAt: number }? } = {}

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

	local function recordTrophy(metadata: any): any
		local trophyApi = if type(depsAny.trophyApi) == "table"
			then depsAny.trophyApi
			else getGlobalApi("_TrophyService_QueryAPI")
		if type(trophyApi) ~= "table" or type(trophyApi.RecordContainmentEnd) ~= "function" then
			return { accepted = false, reason = "trophy_api_unavailable" }
		end
		local ok, result = pcall(trophyApi.RecordContainmentEnd, metadata)
		if not ok or type(result) ~= "table" then
			return { accepted = false, reason = "trophy_request_failed" }
		end
		return result
	end

	local function recordGiantLevel(metadata: any): any
		local giantLevelApi = if type(depsAny.giantLevelApi) == "table"
			then depsAny.giantLevelApi
			else getGlobalApi("_GiantLevelService_QueryAPI")
		if type(giantLevelApi) ~= "table" or type(giantLevelApi.RecordContainmentEnd) ~= "function" then
			return { accepted = false, reason = "giant_level_api_unavailable" }
		end
		local ok, result = pcall(giantLevelApi.RecordContainmentEnd, metadata)
		if not ok or type(result) ~= "table" then
			return { accepted = false, reason = "giant_level_request_failed" }
		end
		return result
	end

	local function updateReputation(custodianUserId: number, metadata: any): any
		local gateway = if type(depsAny.profileGateway) == "table"
			then depsAny.profileGateway
			else getGlobalApi("_ProfilePersistenceGateway_QueryAPI")
		if type(gateway) ~= "table" or type(gateway.UpdateLoadedPlayerProfileData) ~= "function" then
			return {
				accepted = false,
				reason = "profile_gateway_unavailable",
				trackUpdates = {},
				unlockUpdates = {},
			}
		end

		local reputationResult: any = {
			accepted = false,
			reason = "profile_update_failed",
			trackUpdates = {},
			unlockUpdates = {},
		}
		local ok, result = pcall(gateway.UpdateLoadedPlayerProfileData, {
			UserId = custodianUserId,
		}, function(currentData: any): any
			if type(currentData) ~= "table" then
				return nil, "profile_data_invalid"
			end
			reputationResult = ReputationState.ApplyOutcome(currentData, {
				outcomeKind = ReputationState.OutcomeKinds.ContainmentCustodyEnd,
				now = metadata.endedAt,
				operationId = metadata.operationId,
				custodianUserId = metadata.custodianUserId,
				targetUserId = metadata.targetUserId,
				endReason = metadata.endReason,
			}, depsAny.traitRegistry)
			return reputationResult.profileData
		end)
		if not ok or type(result) ~= "table" or result.ok ~= true then
			return {
				accepted = false,
				reason = if type(result) == "table" and type(result.reason) == "string"
					then result.reason
					else "profile_update_failed",
				trackUpdates = reputationResult.trackUpdates or {},
				unlockUpdates = reputationResult.unlockUpdates or {},
			}
		end

		return reputationResult
	end

	local function getGiantRealmResourceResolver(): any?
		if type(depsAny.resourceResolver) == "table" and type(depsAny.resourceResolver.Resolve) == "function" then
			return depsAny.resourceResolver
		end

		local globalEnv: any = getfenv()
		local cached = if type(globalEnv) == "table" then globalEnv._GiantRealmResourceResolverInstance else nil
		if type(cached) == "table" and type(cached.Resolve) == "function" then
			return cached
		end

		local moduleValue: any = nil
		if script ~= nil and script.Parent ~= nil then
			local ok, loaded = pcall(function()
				return require(script.Parent:WaitForChild("GiantRealmResourceResolver"))
			end)
			if ok then
				moduleValue = loaded
			end
		else
			moduleValue = (require :: any)("./GiantRealmResourceResolver")
		end
		if type(moduleValue) ~= "table" or type(moduleValue.Create) ~= "function" then
			return nil
		end
		local created = moduleValue.Create({
			now = nowFn,
			pairRetentionSeconds = pairRetentionSeconds,
			eventLogApi = depsAny.eventLogApi,
			ledgerApi = depsAny.ledgerApi,
		})
		if type(globalEnv) == "table" then
			globalEnv._GiantRealmResourceResolverInstance = created
		end
		return created
	end

	local function getGiantLevelContainmentRewardMultiplier(): number
		local giantLevelApi = if type(depsAny.giantLevelApi) == "table"
			then depsAny.giantLevelApi
			else getGlobalApi("_GiantLevelService_QueryAPI")
		if type(giantLevelApi) ~= "table" or type(giantLevelApi.GetModifierSnapshot) ~= "function" then
			return 1
		end
		local ok, snapshot = pcall(giantLevelApi.GetModifierSnapshot)
		if not ok or type(snapshot) ~= "table" then
			return 1
		end
		local multiplier = snapshot.containmentRewardMultiplier
		if type(multiplier) ~= "number" or multiplier ~= multiplier or multiplier <= 0 then
			return 1
		end
		return multiplier
	end

	local function awardRealmResources(metadata: any)
		if metadata.rewardGranted ~= true and metadata.scoreAccepted ~= true then
			return
		end

		local resourceResolver = getGiantRealmResourceResolver()
		if resourceResolver == nil or type(resourceResolver.Resolve) ~= "function" then
			return
		end

		pcall(resourceResolver.Resolve, {
			sourceKind = GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd,
			operationId = string.format("realm-resource:%s", metadata.operationId),
			ownerUserId = metadata.custodianUserId,
			counterpartyUserId = metadata.targetUserId,
			at = metadata.endedAt,
			metadata = {
				endReason = metadata.endReason,
				contributionRatio = metadata.contributionRatio,
				levelRewardMultiplier = getGiantLevelContainmentRewardMultiplier(),
			},
		})
	end

	local function recordSkillUnlock(custodianPlayer: any): (boolean, string?)
		if type(custodianPlayer) ~= "table" then
			return false, "player_invalid"
		end

		local skillProgressionApi = if type(depsAny.skillProgressionApi) == "table"
			then depsAny.skillProgressionApi
			else getGlobalApi("_SkillProgressionService_QueryAPI")
		if type(skillProgressionApi) ~= "table" or type(skillProgressionApi.UnlockSkill) ~= "function" then
			return false, "skill_progression_api_unavailable"
		end

		local ok, result = pcall(skillProgressionApi.UnlockSkill, custodianPlayer, CONTAINMENT_REWARD_SKILL_ID)
		if not ok or type(result) ~= "table" then
			return false, "skill_unlock_failed"
		end
		if result.accepted == true then
			return true, "accepted"
		end
		if result.reason == "skill_already_unlocked" then
			return true, "skill_already_unlocked"
		end
		return false, tostring(result.reason or "skill_unlock_rejected")
	end

	local function recordReputationLog(userId: number, metadata: any, reputationResult: any)
		local eventLogApi = if type(depsAny.eventLogApi) == "table"
			then depsAny.eventLogApi
			else getGlobalApi("_EventLogService_QueryAPI")
		if type(eventLogApi) ~= "table" or type(eventLogApi.RecordEvent) ~= "function" then
			return
		end
		pcall(
			eventLogApi.RecordEvent,
			"reputation_update",
			"Containment reputation processed",
			"info",
			metadata.endedAt,
			{
				userId = userId,
				outcomeKind = ReputationState.OutcomeKinds.ContainmentCustodyEnd,
				operationId = metadata.operationId,
				endReason = metadata.endReason,
				targetUserId = metadata.targetUserId,
				trackUpdates = if type(reputationResult) == "table" then reputationResult.trackUpdates else {},
				unlockUpdates = if type(reputationResult) == "table" then reputationResult.unlockUpdates else {},
				reputationAccepted = if type(reputationResult) == "table" then reputationResult.accepted else false,
				reputationReason = if type(reputationResult) == "table"
					then reputationResult.reason
					else "reputation_result_invalid",
			}
		)
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
			local capMetadata = {
				operationId = operationId,
				custodianUserId = input.custodianUserId,
				targetUserId = input.targetUserId,
				endedAt = endedAt,
				endReason = endReason,
				heldSeconds = heldSeconds,
			}
			local trophyResult = recordTrophy(capMetadata)
			local giantLevelResult = recordGiantLevel(capMetadata)
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
				trophyAccepted = type(trophyResult) == "table" and trophyResult.accepted == true,
				giantLevelAccepted = type(giantLevelResult) == "table" and giantLevelResult.accepted == true,
			}
		end

		local contributionRatio = clamp(baseRatio * pairMultiplier, 0.25, 1)
		writePairCount(pairKey, endedAt, nextPairCount)
		local metadata = {
			operationId = operationId,
			custodianUserId = input.custodianUserId,
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
		local reputationResult = updateReputation(input.custodianUserId, metadata)
		local skillUnlockAccepted = false
		local skillUnlockReason: string? = "skill_unlock_skipped"
		if type(input.custodianPlayer) == "table" then
			skillUnlockAccepted, skillUnlockReason = recordSkillUnlock(input.custodianPlayer)
		end
		recordReputationLog(input.custodianUserId, metadata, reputationResult)
		local trophyResult = recordTrophy(metadata)
		local giantLevelResult = recordGiantLevel(metadata)
		local rewardGranted = type(scoreResult) == "table" and scoreResult.accepted == true
		awardRealmResources({
			operationId = operationId,
			custodianUserId = input.custodianUserId,
			targetUserId = input.targetUserId,
			endReason = endReason,
			endedAt = endedAt,
			contributionRatio = contributionRatio,
			rewardGranted = rewardGranted,
			scoreAccepted = rewardGranted,
		})

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
			reputationAccepted = reputationResult.accepted == true,
			reputationReason = reputationResult.reason,
			reputationTrackUpdates = reputationResult.trackUpdates,
			reputationUnlockUpdates = reputationResult.unlockUpdates,
			trophyAccepted = type(trophyResult) == "table" and trophyResult.accepted == true,
			trophyReason = if type(trophyResult) == "table" then trophyResult.reason else "trophy_result_invalid",
			giantLevelAccepted = type(giantLevelResult) == "table" and giantLevelResult.accepted == true,
			giantLevelReason = if type(giantLevelResult) == "table"
				then giantLevelResult.reason
				else "giant_level_result_invalid",
			skillUnlockAccepted = skillUnlockAccepted,
			skillUnlockReason = skillUnlockReason,
			skillUnlockId = CONTAINMENT_REWARD_SKILL_ID,
		}
	end

	return resolver
end

return ContainmentRewardResolver
