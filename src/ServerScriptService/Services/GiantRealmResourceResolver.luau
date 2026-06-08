--!strict

local GiantRealmResourceState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("GiantRealmResourceState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState")

local GiantRealmResourceResolver: any = {}

local DEFAULT_PAIR_RETENTION_SECONDS = 300
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

local function defaultNow(): number
	return os.clock()
end

local function makePairKey(ownerUserId: number, counterpartyUserId: number, sourceKind: string): string
	return string.format("%d|%d|%s", ownerUserId, counterpartyUserId, sourceKind)
end

function GiantRealmResourceResolver.Create(deps: any?): any
	local depsAny: any = if type(deps) == "table" then deps else {}
	local nowFn = if type(depsAny.now) == "function" then depsAny.now else defaultNow
	local pairRetentionSeconds = if isFiniteNumber(depsAny.pairRetentionSeconds)
			and depsAny.pairRetentionSeconds > 0
		then depsAny.pairRetentionSeconds
		else DEFAULT_PAIR_RETENTION_SECONDS
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

	local function getLedgerApi(): any?
		if type(depsAny.ledgerApi) == "table" then
			return depsAny.ledgerApi
		end
		return getGlobalApi("_GiantBuildModeService_QueryAPI")
	end

	local function getEventLogApi(): any?
		if type(depsAny.eventLogApi) == "table" then
			return depsAny.eventLogApi
		end
		return getGlobalApi("_EventLogService_QueryAPI")
	end

	local function readPairCount(pairKey: string, at: number): number
		local history = pairHistoryByKey[pairKey]
		if history == nil then
			return 0
		end
		if at - history.lastAt > pairRetentionSeconds then
			pairHistoryByKey[pairKey] = nil
			return 0
		end
		return history.count
	end

	local function writePairCount(pairKey: string, at: number, count: number)
		pairHistoryByKey[pairKey] = {
			count = count,
			lastAt = at,
		}
	end

	local function recordResourceLog(ownerUserId: number, at: number, result: any)
		local eventLogApi = getEventLogApi()
		if type(eventLogApi) ~= "table" or type(eventLogApi.RecordEvent) ~= "function" then
			return
		end
		pcall(eventLogApi.RecordEvent, "realm_resource_award", "Giant realm resource award processed", "info", at, {
			ownerUserId = ownerUserId,
			operationId = result.operationId,
			sourceKind = result.sourceKind,
			counterpartyUserId = result.counterpartyUserId,
			essence = result.essence,
			wood = result.wood,
			stone = result.stone,
			pairRewardCount = result.pairRewardCount,
			accepted = result.accepted,
			reason = result.reason,
		})
	end

	function resolver.Resolve(input: any): any
		if type(input) ~= "table" then
			return { accepted = false, reason = "input_invalid" }
		end

		local sourceKind = nonEmptyString(input.sourceKind)
		if sourceKind == nil then
			return { accepted = false, reason = "source_kind_invalid" }
		end
		local operationId = nonEmptyString(input.operationId)
		if operationId == nil then
			return { accepted = false, reason = "operation_id_invalid" }
		end
		if not isPositiveInteger(input.ownerUserId) then
			return { accepted = false, reason = "owner_user_id_invalid" }
		end

		local at = if isFiniteNumber(input.at) and input.at >= 0 then input.at else nowFn()
		local ledgerApi = getLedgerApi()
		if type(ledgerApi) ~= "table" or type(ledgerApi.ApplyResourceAward) ~= "function" then
			return { accepted = false, reason = "ledger_api_unavailable" }
		end

		local pairMultiplier = 1
		local pairRewardCount = 0
		if isPositiveInteger(input.counterpartyUserId) then
			local pairKey = makePairKey(input.ownerUserId, input.counterpartyUserId, sourceKind)
			local previousPairCount = readPairCount(pairKey, at)
			pairRewardCount = previousPairCount + 1
			pairMultiplier = PAIR_MULTIPLIERS[pairRewardCount] or 0
		end

		local amounts = GiantRealmResourceState.ComputeAwardAmounts(sourceKind, input.metadata, pairMultiplier)
		if amounts.accepted ~= true then
			return {
				accepted = true,
				reason = amounts.reason,
				operationId = operationId,
				sourceKind = sourceKind,
				awardGranted = false,
				pairRewardCount = pairRewardCount,
			}
		end

		local applyResult = ledgerApi.ApplyResourceAward({
			operationId = operationId,
			sourceKind = sourceKind,
			awardedAt = at,
			essence = amounts.essence,
			wood = amounts.wood,
			stone = amounts.stone,
			counterpartyUserId = input.counterpartyUserId,
		})
		if type(applyResult) ~= "table" then
			return { accepted = false, reason = "ledger_apply_failed", operationId = operationId }
		end
		if applyResult.accepted ~= true then
			return {
				accepted = false,
				reason = tostring(applyResult.reason or "ledger_apply_rejected"),
				operationId = operationId,
				sourceKind = sourceKind,
				awardGranted = false,
				pairRewardCount = pairRewardCount,
			}
		end
		if applyResult.duplicate == true then
			return {
				accepted = true,
				reason = "duplicate_operation",
				operationId = operationId,
				sourceKind = sourceKind,
				duplicate = true,
				awardGranted = false,
				pairRewardCount = pairRewardCount,
			}
		end

		if isPositiveInteger(input.counterpartyUserId) then
			local pairKey = makePairKey(input.ownerUserId, input.counterpartyUserId, sourceKind)
			writePairCount(pairKey, at, pairRewardCount)
		end

		local result = {
			accepted = true,
			reason = "accepted",
			operationId = operationId,
			sourceKind = sourceKind,
			duplicate = false,
			awardGranted = true,
			essence = amounts.essence,
			wood = amounts.wood,
			stone = amounts.stone,
			pairRewardCount = pairRewardCount,
			ledger = applyResult.ledger,
		}
		recordResourceLog(input.ownerUserId, at, result)
		return result
	end

	return resolver
end

return GiantRealmResourceResolver
