--!strict

local RescueContractQueueState = {}

export type QueueStatus = "pending" | "accepted" | "resolved" | "expired"

export type QueueEntry = {
	queueEntryId: string,
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
	}
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
