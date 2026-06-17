--!strict

local RescueContractQueueState = {}

export type QueueStatus = "pending" | "accepted" | "resolved" | "expired"

export type QueueEntry = {
	queueEntryId: string,
	operationId: string,
	capturedUserId: number,
	realmId: string,
	sessionId: string,
	rewardHint: string,
	dangerRating: number,
	expiration: number,
	rescuerUserId: number,
	targetRealmOwnerUserId: number,
	entryRouteId: string,
	entryRouteKind: string,
	createdAt: number,
	status: QueueStatus,
	acceptedAt: number?,
	acceptedByUserId: number?,
	resolvedAt: number?,
	resolvedReason: string?,
	storeReceiptId: string?,
}

export type ValidationResult = {
	ok: boolean,
	reason: string?,
	entry: QueueEntry?,
}

export type State = {
	entriesById: { [string]: QueueEntry },
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function cloneEntry(entry: QueueEntry): QueueEntry
	return {
		queueEntryId = entry.queueEntryId,
		operationId = entry.operationId,
		capturedUserId = entry.capturedUserId,
		realmId = entry.realmId,
		sessionId = entry.sessionId,
		rewardHint = entry.rewardHint,
		dangerRating = entry.dangerRating,
		expiration = entry.expiration,
		rescuerUserId = entry.rescuerUserId,
		targetRealmOwnerUserId = entry.targetRealmOwnerUserId,
		entryRouteId = entry.entryRouteId,
		entryRouteKind = entry.entryRouteKind,
		createdAt = entry.createdAt,
		status = entry.status,
		acceptedAt = entry.acceptedAt,
		acceptedByUserId = entry.acceptedByUserId,
		resolvedAt = entry.resolvedAt,
		resolvedReason = entry.resolvedReason,
		storeReceiptId = entry.storeReceiptId,
	}
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) or value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isValidStatus(value: any): boolean
	return value == "pending" or value == "accepted" or value == "resolved" or value == "expired"
end

function RescueContractQueueState.ValidateEntry(input: any): ValidationResult
	if type(input) ~= "table" then
		return { ok = false, reason = "entry_invalid", entry = nil }
	end
	if not isNonEmptyString(input.queueEntryId) then
		return { ok = false, reason = "queue_entry_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.operationId) then
		return { ok = false, reason = "operation_id_invalid", entry = nil }
	end
	if not isPositiveInteger(input.capturedUserId) then
		return { ok = false, reason = "captured_user_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.realmId) then
		return { ok = false, reason = "realm_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.sessionId) then
		return { ok = false, reason = "session_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.rewardHint) then
		return { ok = false, reason = "reward_hint_invalid", entry = nil }
	end
	if not isFiniteNumber(input.dangerRating) or input.dangerRating < 0 or input.dangerRating > 1 then
		return { ok = false, reason = "danger_rating_invalid", entry = nil }
	end
	if not isFiniteNumber(input.createdAt) or input.createdAt < 0 then
		return { ok = false, reason = "created_at_invalid", entry = nil }
	end
	if not isFiniteNumber(input.expiration) or input.expiration <= input.createdAt then
		return { ok = false, reason = "expiration_invalid", entry = nil }
	end
	if not isPositiveInteger(input.rescuerUserId) then
		return { ok = false, reason = "rescuer_user_id_invalid", entry = nil }
	end
	if not isPositiveInteger(input.targetRealmOwnerUserId) then
		return { ok = false, reason = "target_realm_owner_user_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.entryRouteId) then
		return { ok = false, reason = "entry_route_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.entryRouteKind) then
		return { ok = false, reason = "entry_route_kind_invalid", entry = nil }
	end

	local status = if input.status == nil then "pending" else input.status
	if not isValidStatus(status) then
		return { ok = false, reason = "status_invalid", entry = nil }
	end

	local acceptedAt = input.acceptedAt
	if acceptedAt ~= nil and not isFiniteNumber(acceptedAt) then
		return { ok = false, reason = "accepted_at_invalid", entry = nil }
	end
	local acceptedByUserId = input.acceptedByUserId
	if acceptedByUserId ~= nil and not isPositiveInteger(acceptedByUserId) then
		return { ok = false, reason = "accepted_by_user_id_invalid", entry = nil }
	end
	local resolvedAt = input.resolvedAt
	if resolvedAt ~= nil and not isFiniteNumber(resolvedAt) then
		return { ok = false, reason = "resolved_at_invalid", entry = nil }
	end
	local storeReceiptId = input.storeReceiptId
	if storeReceiptId ~= nil and not isNonEmptyString(storeReceiptId) then
		return { ok = false, reason = "store_receipt_id_invalid", entry = nil }
	end

	local entry: QueueEntry = {
		queueEntryId = input.queueEntryId,
		operationId = input.operationId,
		capturedUserId = input.capturedUserId,
		realmId = input.realmId,
		sessionId = input.sessionId,
		rewardHint = input.rewardHint,
		dangerRating = input.dangerRating,
		expiration = input.expiration,
		rescuerUserId = input.rescuerUserId,
		targetRealmOwnerUserId = input.targetRealmOwnerUserId,
		entryRouteId = input.entryRouteId,
		entryRouteKind = input.entryRouteKind,
		createdAt = input.createdAt,
		status = status,
		acceptedAt = acceptedAt,
		acceptedByUserId = acceptedByUserId,
		resolvedAt = resolvedAt,
		resolvedReason = if type(input.resolvedReason) == "string" then input.resolvedReason else nil,
		storeReceiptId = storeReceiptId,
	}

	return {
		ok = true,
		reason = nil,
		entry = entry,
	}
end

function RescueContractQueueState.NewEntry(input: any): ValidationResult
	return RescueContractQueueState.ValidateEntry(input)
end

function RescueContractQueueState.IsExpired(entry: QueueEntry, nowAt: number): boolean
	local validation = RescueContractQueueState.ValidateEntry(entry)
	if not validation.ok then
		return true
	end
	if not isFiniteNumber(nowAt) then
		return true
	end
	local validatedEntry = validation.entry :: QueueEntry
	if validatedEntry.status ~= "pending" then
		return false
	end
	return nowAt >= validatedEntry.expiration
end

local function cloneState(state: State): State
	local entriesById: { [string]: QueueEntry } = {}
	for queueEntryId, entry in pairs(state.entriesById) do
		entriesById[queueEntryId] = cloneEntry(entry)
	end
	return {
		entriesById = entriesById,
	}
end

function RescueContractQueueState.NewState(): State
	return {
		entriesById = {},
	}
end

function RescueContractQueueState.PruneExpired(state: State, nowAt: number): (State, { QueueEntry })
	if not isFiniteNumber(nowAt) then
		return cloneState(state), {}
	end

	local nextState = cloneState(state)
	local expired: { QueueEntry } = {}
	for queueEntryId, entry in pairs(nextState.entriesById) do
		if entry.status == "pending" and entry.expiration <= nowAt then
			entry.status = "expired"
			entry.resolvedAt = nowAt
			entry.resolvedReason = "expired"
			table.insert(expired, cloneEntry(entry))
			nextState.entriesById[queueEntryId] = entry
		end
	end

	return nextState, expired
end

function RescueContractQueueState.UpsertPending(state: State, entry: QueueEntry): State
	local nextState = cloneState(state)
	nextState.entriesById[entry.queueEntryId] = cloneEntry(entry)
	return nextState
end

function RescueContractQueueState.GetPendingEntries(state: State): { QueueEntry }
	local pending: { QueueEntry } = {}
	for _, entry in pairs(state.entriesById) do
		if entry.status == "pending" then
			table.insert(pending, cloneEntry(entry))
		end
	end

	table.sort(pending, function(a, b)
		if a.createdAt == b.createdAt then
			return a.queueEntryId < b.queueEntryId
		end
		return a.createdAt < b.createdAt
	end)

	return pending
end

function RescueContractQueueState.GetEntries(state: State): { QueueEntry }
	local entries: { QueueEntry } = {}
	for _, entry in pairs(state.entriesById) do
		table.insert(entries, cloneEntry(entry))
	end

	table.sort(entries, function(a, b)
		if a.createdAt == b.createdAt then
			return a.queueEntryId < b.queueEntryId
		end
		return a.createdAt < b.createdAt
	end)

	return entries
end

function RescueContractQueueState.GetEntry(state: State, queueEntryId: string): QueueEntry?
	if type(queueEntryId) ~= "string" or queueEntryId == "" then
		return nil
	end
	local entry = state.entriesById[queueEntryId]
	if entry == nil then
		return nil
	end
	return cloneEntry(entry)
end

function RescueContractQueueState.MarkAccepted(
	state: State,
	queueEntryId: string,
	acceptedByUserId: number,
	nowAt: number
): (State, QueueEntry?, boolean)
	local nextState = cloneState(state)
	local entry = nextState.entriesById[queueEntryId]
	if entry == nil then
		return nextState, nil, false
	end
	if entry.status ~= "pending" then
		return nextState, cloneEntry(entry), false
	end

	entry.status = "accepted"
	entry.acceptedByUserId = acceptedByUserId
	entry.acceptedAt = nowAt
	nextState.entriesById[queueEntryId] = entry
	return nextState, cloneEntry(entry), true
end

function RescueContractQueueState.MarkResolvedByContract(
	state: State,
	rescuerUserId: number,
	capturedUserId: number,
	resolvedReason: string,
	nowAt: number
): State
	local nextState = cloneState(state)
	for queueEntryId, entry in pairs(nextState.entriesById) do
		if
			entry.status == "pending"
			and entry.rescuerUserId == rescuerUserId
			and entry.capturedUserId == capturedUserId
		then
			entry.status = "resolved"
			entry.resolvedReason = resolvedReason
			entry.resolvedAt = nowAt
			nextState.entriesById[queueEntryId] = entry
		end
	end
	return nextState
end

function RescueContractQueueState.MarkResolvedForParticipant(
	state: State,
	participantUserId: number,
	resolvedReason: string,
	nowAt: number
): State
	local nextState = cloneState(state)
	for queueEntryId, entry in pairs(nextState.entriesById) do
		if
			entry.status == "pending"
			and (entry.rescuerUserId == participantUserId or entry.capturedUserId == participantUserId)
		then
			entry.status = "resolved"
			entry.resolvedReason = resolvedReason
			entry.resolvedAt = nowAt
			nextState.entriesById[queueEntryId] = entry
		end
	end
	return nextState
end

return RescueContractQueueState
