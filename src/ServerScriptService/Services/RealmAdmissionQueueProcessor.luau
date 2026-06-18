--!strict

local RealmAdmissionQueueProcessor: any = {}
local globalEnv: any = getfenv()

local RealmAdmissionLocationCaller = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAdmissionLocationCaller"))
	else (require :: any)("./RealmAdmissionLocationCaller")

local TINYFOLK_PARTY_ID_PREFIX = "tinyfolk_party:"

export type ProcessOutcome = {
	processed: number,
	succeeded: number,
	expired: number,
	retryDeferred: number,
	failed: number,
	duplicatesSkipped: number,
	cleanupDeferred: number,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function defaultNow(): number
	return os.clock()
end

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function isTinyfolkPartyId(partyId: any): boolean
	return type(partyId) == "string" and string.sub(partyId, 1, #TINYFOLK_PARTY_ID_PREFIX) == TINYFOLK_PARTY_ID_PREFIX
end

local function makeOutcome(): ProcessOutcome
	return {
		processed = 0,
		succeeded = 0,
		expired = 0,
		retryDeferred = 0,
		failed = 0,
		duplicatesSkipped = 0,
		cleanupDeferred = 0,
	}
end

function RealmAdmissionQueueProcessor.Create(deps: any?): any
	local depsAny = deps
	local queueStore = if type(depsAny) == "table" then depsAny.queueStore else nil
	local queueState = if type(depsAny) == "table" then depsAny.queueState else nil
	local capacityApi = if type(depsAny) == "table" then depsAny.capacityApi else nil
	local teleportDispatcher = if type(depsAny) == "table" then depsAny.teleportDispatcher else nil
	local operationLock = if type(depsAny) == "table" then depsAny.operationLock else nil
	local idempotencyStore = if type(depsAny) == "table" then depsAny.idempotencyStore else nil
	local partyResolver = if type(depsAny) == "table" then depsAny.partyResolver else nil
	local tinyfolkPartyApi = if type(depsAny) == "table" then depsAny.tinyfolkPartyApi else nil
	local nowFn = if type(depsAny) == "table" and type(depsAny.now) == "function" then depsAny.now else defaultNow

	local processor: any = {}

	local function tryAcquireOperationLock(operationId: string): boolean
		if type(operationLock) ~= "table" or type(operationLock.TryAcquire) ~= "function" then
			return true
		end
		local ok, acquired = pcall(operationLock.TryAcquire, operationId)
		if not ok then
			return false
		end
		return acquired == true
	end

	local function releaseOperationLock(operationId: string)
		if type(operationLock) ~= "table" or type(operationLock.Release) ~= "function" then
			return
		end
		pcall(operationLock.Release, operationId)
	end

	local function reserveCapacity(entry: any, nowAt: number): any
		if type(capacityApi) ~= "table" or type(capacityApi.ReserveTinyfolkSlots) ~= "function" then
			return {
				accepted = false,
				reason = "capacity_api_unavailable",
			}
		end
		return capacityApi.ReserveTinyfolkSlots(entry.targetRealmId, entry.partySize, nowAt)
	end

	local function releaseReservedCapacity(entry: any, nowAt: number)
		if type(capacityApi) ~= "table" or type(capacityApi.ReleaseReservedSlots) ~= "function" then
			return
		end
		pcall(capacityApi.ReleaseReservedSlots, entry.targetRealmId, entry.partySize, nowAt)
	end

	local function dispatchTeleport(entry: any): any
		if type(teleportDispatcher) ~= "table" or type(teleportDispatcher.Dispatch) ~= "function" then
			return {
				ok = false,
				retryable = true,
				reason = "teleport_dispatcher_unavailable",
			}
		end
		local ok, result = pcall(teleportDispatcher.Dispatch, entry)
		if not ok then
			return {
				ok = false,
				retryable = true,
				reason = "teleport_dispatch_failed",
			}
		end
		if type(result) ~= "table" then
			return {
				ok = false,
				retryable = true,
				reason = "teleport_dispatch_result_invalid",
			}
		end
		return result
	end

	local function removeFromQueue(receiptId: string): boolean
		if type(queueStore) ~= "table" or type(queueStore.Remove) ~= "function" then
			return false
		end
		local removeResult = queueStore.Remove(receiptId)
		if type(removeResult) ~= "table" then
			return false
		end
		return removeResult.accepted == true
	end

	local function tryBeginProcessing(operationId: any): any
		if type(idempotencyStore) ~= "table" or type(idempotencyStore.TryBegin) ~= "function" then
			return {
				accepted = true,
				status = "begun",
				reason = "accepted",
			}
		end
		local ok, result = pcall(idempotencyStore.TryBegin, operationId)
		if not ok or type(result) ~= "table" then
			return {
				accepted = false,
				status = nil,
				reason = "idempotency_try_begin_failed",
			}
		end
		return result
	end

	local function markCompleted(operationId: any): boolean
		if type(idempotencyStore) ~= "table" or type(idempotencyStore.MarkCompleted) ~= "function" then
			return true
		end
		local ok, result = pcall(idempotencyStore.MarkCompleted, operationId)
		return ok and type(result) == "table" and result.accepted == true
	end

	local function releaseProcessing(operationId: any)
		if type(idempotencyStore) ~= "table" or type(idempotencyStore.ReleaseProcessing) ~= "function" then
			return
		end
		pcall(idempotencyStore.ReleaseProcessing, operationId)
	end

	local function unregisterParty(partyId: any)
		if type(partyId) ~= "string" or partyId == "" then
			return
		end
		if type(partyResolver) ~= "table" or type((partyResolver :: any).UnregisterParty) ~= "function" then
			return
		end
		pcall((partyResolver :: any).UnregisterParty, partyId)
	end

	local function resolveTinyfolkPartyApi(): any?
		if type(tinyfolkPartyApi) == "table" then
			return tinyfolkPartyApi
		end
		return getGlobalTable("_TinyfolkPartyService_QueryAPI")
	end

	local function resolvePartyMemberUserIds(entry: any): { number }?
		if type(entry) ~= "table" or type(entry.partyMemberUserIds) ~= "table" then
			return nil
		end
		if #entry.partyMemberUserIds <= 0 then
			return nil
		end
		return entry.partyMemberUserIds
	end

	local function abortAdmissionLocation(entry: any, nowAt: number)
		local memberUserIds = resolvePartyMemberUserIds(entry)
		if memberUserIds == nil then
			return
		end
		RealmAdmissionLocationCaller.ApplyAbortRollbackForMembers(memberUserIds, {
			now = math.floor(nowAt),
		})
	end

	local function resolveTransferredUserIds(entry: any, dispatchResult: any): { number }?
		if type(dispatchResult) == "table" and type(dispatchResult.transferredUserIds) == "table" then
			return dispatchResult.transferredUserIds
		end
		if type(entry) ~= "table" or type(entry.partyId) ~= "string" then
			return nil
		end
		if type(partyResolver) ~= "table" or type((partyResolver :: any).ResolvePartyMemberUserIds) ~= "function" then
			return nil
		end
		local ok, members = pcall((partyResolver :: any).ResolvePartyMemberUserIds, entry.partyId, entry)
		if not ok or type(members) ~= "table" then
			return nil
		end
		return members
	end

	local function notifyPartyTransferOutcome(entry: any, dispatchResult: any, at: number): any?
		if type(entry) ~= "table" or not isTinyfolkPartyId(entry.partyId) then
			return nil
		end

		local partyApi = resolveTinyfolkPartyApi()
		if type(partyApi) ~= "table" or type((partyApi :: any).HandleTransferOutcome) ~= "function" then
			return nil
		end

		local transferredUserIds = resolveTransferredUserIds(entry, dispatchResult)
		if type(transferredUserIds) ~= "table" or #transferredUserIds <= 0 then
			return nil
		end

		local ok, result = pcall(function()
			return (partyApi :: any).HandleTransferOutcome({
				partyId = entry.partyId,
				transferredUserIds = transferredUserIds,
				at = at,
			})
		end)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end

	local function shouldUnregisterPartyAfterTransfer(entry: any, transferOutcome: any): boolean
		if not isTinyfolkPartyId(if type(entry) == "table" then entry.partyId else nil) then
			return true
		end
		if type(transferOutcome) ~= "table" or transferOutcome.accepted ~= true then
			return true
		end
		return transferOutcome.dissolved == true
	end

	function processor.ProcessBatch(maxItems: any): ProcessOutcome
		local outcome = makeOutcome()
		if not isFiniteNumber(maxItems) or maxItems <= 0 or maxItems % 1 ~= 0 then
			outcome.failed += 1
			return outcome
		end
		if type(queueStore) ~= "table" or type(queueStore.ReadBatch) ~= "function" then
			outcome.failed += 1
			return outcome
		end

		local readResult = queueStore.ReadBatch(maxItems)
		if type(readResult) ~= "table" or readResult.accepted ~= true then
			outcome.failed += 1
			return outcome
		end

		for _, queued in ipairs(readResult.items) do
			outcome.processed += 1

			if type(queued) ~= "table" or type(queued.receiptId) ~= "string" then
				outcome.failed += 1
				continue
			end
			if queued.entry == nil then
				outcome.failed += 1
				continue
			end

			local entry = queued.entry
			local nowAt = nowFn()
			if type(queueState) ~= "table" or type(queueState.IsExpired) ~= "function" then
				if not removeFromQueue(queued.receiptId) then
					outcome.failed += 1
				else
					outcome.failed += 1
				end
				continue
			end
			if queueState.IsExpired(entry, nowAt) then
				if removeFromQueue(queued.receiptId) then
					abortAdmissionLocation(entry, nowAt)
					unregisterParty(entry.partyId)
					outcome.expired += 1
				else
					outcome.failed += 1
				end
				continue
			end

			if not tryAcquireOperationLock(entry.operationId) then
				outcome.retryDeferred += 1
				continue
			end

			local beginResult = tryBeginProcessing(entry.operationId)
			if beginResult.accepted == true and beginResult.status == "completed" then
				if removeFromQueue(queued.receiptId) then
					unregisterParty(entry.partyId)
					outcome.duplicatesSkipped += 1
				else
					outcome.cleanupDeferred += 1
				end
				releaseOperationLock(entry.operationId)
				continue
			end
			if beginResult.accepted ~= true then
				releaseOperationLock(entry.operationId)
				outcome.retryDeferred += 1
				continue
			end

			local reserveResult = reserveCapacity(entry, nowAt)
			if reserveResult.accepted ~= true then
				releaseProcessing(entry.operationId)
				releaseOperationLock(entry.operationId)
				outcome.retryDeferred += 1
				continue
			end

			local dispatchResult = dispatchTeleport(entry)
			if dispatchResult.ok == true then
				if not markCompleted(entry.operationId) then
					releaseOperationLock(entry.operationId)
					outcome.cleanupDeferred += 1
					continue
				end
				if not removeFromQueue(queued.receiptId) then
					releaseOperationLock(entry.operationId)
					outcome.cleanupDeferred += 1
					continue
				end
				local transferOutcome = notifyPartyTransferOutcome(entry, dispatchResult, nowAt)
				if shouldUnregisterPartyAfterTransfer(entry, transferOutcome) then
					unregisterParty(entry.partyId)
				end
				releaseOperationLock(entry.operationId)
				outcome.succeeded += 1
				continue
			end

			releaseReservedCapacity(entry, nowAt)
			if dispatchResult.retryable == true then
				releaseProcessing(entry.operationId)
				releaseOperationLock(entry.operationId)
				outcome.retryDeferred += 1
			else
				if not markCompleted(entry.operationId) then
					releaseProcessing(entry.operationId)
					releaseOperationLock(entry.operationId)
					outcome.retryDeferred += 1
					continue
				end
				if not removeFromQueue(queued.receiptId) then
					releaseOperationLock(entry.operationId)
					outcome.cleanupDeferred += 1
					continue
				end
				abortAdmissionLocation(entry, nowAt)
				unregisterParty(entry.partyId)
				releaseOperationLock(entry.operationId)
				outcome.failed += 1
			end
		end

		return outcome
	end

	return processor
end

return RealmAdmissionQueueProcessor
