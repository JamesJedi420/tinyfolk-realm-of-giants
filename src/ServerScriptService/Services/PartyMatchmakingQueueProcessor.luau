--!strict

local PartyMatchmakingQueueProcessor: any = {}

export type ProcessOutcome = {
	processed: number,
	matched: number,
	expired: number,
	failed: number,
	retryDeferred: number,
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

local function makeOutcome(): ProcessOutcome
	return {
		processed = 0,
		matched = 0,
		expired = 0,
		failed = 0,
		retryDeferred = 0,
		duplicatesSkipped = 0,
		cleanupDeferred = 0,
	}
end

function PartyMatchmakingQueueProcessor.Create(deps: any?): any
	local depsAny = deps
	local queueStore = if type(depsAny) == "table" then depsAny.queueStore else nil
	local queueState = if type(depsAny) == "table" then depsAny.queueState else nil
	local idempotencyStore = if type(depsAny) == "table" then depsAny.idempotencyStore else nil
	local listLiveRealmAvailability = if type(depsAny) == "table" then depsAny.listLiveRealmAvailability else nil
	local selectMatchmakingTarget = if type(depsAny) == "table" then depsAny.selectMatchmakingTarget else nil
	local admissionApi = if type(depsAny) == "table" then depsAny.admissionApi else nil
	local tinyfolkPartyApi = if type(depsAny) == "table" then depsAny.tinyfolkPartyApi else nil
	local onOutcome = if type(depsAny) == "table" then depsAny.onOutcome else nil
	local nowFn = if type(depsAny) == "table" and type(depsAny.now) == "function" then depsAny.now else defaultNow

	local processor: any = {}

	local function tryBeginProcessing(operationId: string): any
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

	local function markOperationCompleted(operationId: string)
		if type(idempotencyStore) ~= "table" or type(idempotencyStore.MarkCompleted) ~= "function" then
			return
		end
		pcall(idempotencyStore.MarkCompleted, operationId)
	end

	local function releaseOperationProcessing(operationId: string)
		if type(idempotencyStore) ~= "table" or type(idempotencyStore.ReleaseProcessing) ~= "function" then
			return
		end
		pcall(idempotencyStore.ReleaseProcessing, operationId)
	end

	local function removeReceipt(receiptId: string): boolean
		if type(queueStore) ~= "table" or type(queueStore.Remove) ~= "function" then
			return false
		end
		local ok, result = pcall(queueStore.Remove, receiptId)
		return ok and type(result) == "table" and result.accepted == true
	end

	local function publishOutcome(entry: any, receiptId: string?)
		if type(onOutcome) == "function" then
			pcall(onOutcome, entry, receiptId)
		end
	end

	local function validatePartyMembersStillMatch(entry: any): (boolean, string?)
		if type(tinyfolkPartyApi) ~= "table" or type(tinyfolkPartyApi.ResolveMatchmakingQueueContext) ~= "function" then
			return true, nil
		end

		local leaderUserId = entry.leaderUserId
		if type(leaderUserId) ~= "number" then
			return false, "party_members_invalid"
		end

		local ok, context = pcall(tinyfolkPartyApi.ResolveMatchmakingQueueContext, leaderUserId)
		if not ok or type(context) ~= "table" or context.accepted ~= true then
			local reason = if type(context) == "table" and type(context.reason) == "string"
				then context.reason
				else "party_context_invalid"
			return false, reason
		end
		if context.partyId ~= entry.partyId then
			return false, "party_members_changed"
		end
		if type(context.partyMemberUserIds) ~= "table" or #context.partyMemberUserIds ~= entry.partySize then
			return false, "party_members_changed"
		end

		for index, memberUserId in ipairs(entry.partyMemberUserIds) do
			if context.partyMemberUserIds[index] ~= memberUserId then
				return false, "party_members_changed"
			end
		end

		return true, nil
	end

	local function resolveAvailability(): { any }?
		if type(listLiveRealmAvailability) ~= "function" then
			return nil
		end
		local ok, availability = pcall(listLiveRealmAvailability, 25, nowFn())
		if ok and type(availability) == "table" then
			return availability
		end
		return nil
	end

	local function resolveMatchTarget(entry: any, availability: { any }): (string?, string?)
		if type(selectMatchmakingTarget) == "function" then
			local ok, snapshot =
				pcall(selectMatchmakingTarget, availability, entry.desiredActivity, entry.skillBand, entry.toolTier)
			if ok and type(snapshot) == "table" and type(snapshot.realmId) == "string" and snapshot.realmId ~= "" then
				return snapshot.realmId, "matcher"
			end
		end
		return nil, "target_realm_unavailable"
	end

	local function requestAdmission(entry: any, targetRealmId: string): (boolean, string?)
		if type(admissionApi) ~= "table" or type(admissionApi.RequestPartyMatchAdmission) ~= "function" then
			return false, "admission_api_unavailable"
		end

		local ok, result = pcall(admissionApi.RequestPartyMatchAdmission, {
			operationId = string.format("party_matchmaking_admission_%s", entry.operationId),
			partyId = entry.partyId,
			targetRealmId = targetRealmId,
			partyMemberUserIds = entry.partyMemberUserIds,
			entryType = "direct_invite",
		})
		if not ok or type(result) ~= "table" or result.accepted ~= true then
			local reason = if type(result) == "table" and type(result.reason) == "string"
				then result.reason
				else "admission_enqueue_failed"
			return false, reason
		end
		return true, "accepted"
	end

	function processor.ProcessBatch(maxItems: any): ProcessOutcome
		local outcome = makeOutcome()
		if not isFiniteNumber(maxItems) or maxItems <= 0 or maxItems % 1 ~= 0 then
			return outcome
		end
		if type(queueStore) ~= "table" or type(queueStore.ReadBatch) ~= "function" then
			return outcome
		end
		if type(queueState) ~= "table" then
			return outcome
		end

		local readResult = queueStore.ReadBatch(maxItems)
		if type(readResult) ~= "table" or readResult.accepted ~= true or type(readResult.items) ~= "table" then
			return outcome
		end

		local nowAt = nowFn()
		local availability = resolveAvailability()

		for _, item in ipairs(readResult.items) do
			outcome.processed += 1
			local receiptId = item.receiptId
			local entry = item.entry
			if type(receiptId) ~= "string" or type(entry) ~= "table" then
				outcome.failed += 1
				if type(receiptId) == "string" then
					removeReceipt(receiptId)
				end
				continue
			end

			local beginResult = tryBeginProcessing(entry.operationId)
			if beginResult.accepted == true and beginResult.status == "completed" then
				outcome.duplicatesSkipped += 1
				removeReceipt(receiptId)
				continue
			end
			if beginResult.accepted ~= true then
				outcome.duplicatesSkipped += 1
				outcome.retryDeferred += 1
				continue
			end

			if queueState.IsExpired(entry, nowAt) == true then
				local expiredResult = queueState.WithExpiry(entry, nowAt, "expired")
				if expiredResult.ok == true and expiredResult.entry ~= nil then
					outcome.expired += 1
					publishOutcome(expiredResult.entry, receiptId)
				else
					outcome.failed += 1
				end
				removeReceipt(receiptId)
				markOperationCompleted(entry.operationId)
				continue
			end

			local membersValid, membersReason = validatePartyMembersStillMatch(entry)
			if membersValid ~= true then
				local expiredResult = queueState.WithExpiry(entry, nowAt, membersReason or "party_members_changed")
				if expiredResult.ok == true and expiredResult.entry ~= nil then
					outcome.expired += 1
					publishOutcome(expiredResult.entry, receiptId)
				else
					outcome.failed += 1
				end
				removeReceipt(receiptId)
				markOperationCompleted(entry.operationId)
				continue
			end

			if availability == nil then
				outcome.retryDeferred += 1
				releaseOperationProcessing(entry.operationId)
				continue
			end

			local targetRealmId, _matchPath = resolveMatchTarget(entry, availability)
			if targetRealmId == nil then
				outcome.retryDeferred += 1
				releaseOperationProcessing(entry.operationId)
				continue
			end

			local admissionAccepted, admissionReason = requestAdmission(entry, targetRealmId)
			if admissionAccepted ~= true then
				outcome.failed += 1
				local expiredResult = queueState.WithExpiry(entry, nowAt, admissionReason or "admission_enqueue_failed")
				if expiredResult.ok == true and expiredResult.entry ~= nil then
					publishOutcome(expiredResult.entry, receiptId)
				end
				removeReceipt(receiptId)
				markOperationCompleted(entry.operationId)
				continue
			end

			local matchedResult = queueState.WithMatch(entry, targetRealmId, nowAt)
			if matchedResult.ok == true and matchedResult.entry ~= nil then
				outcome.matched += 1
				publishOutcome(matchedResult.entry, receiptId)
			else
				outcome.failed += 1
			end
			removeReceipt(receiptId)
			markOperationCompleted(entry.operationId)
		end

		return outcome
	end

	return processor
end

return PartyMatchmakingQueueProcessor
