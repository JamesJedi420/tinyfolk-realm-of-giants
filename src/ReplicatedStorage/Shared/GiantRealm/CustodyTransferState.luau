--!strict

local CaptivityDurationState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("CaptivityDurationState"))
	else (require :: any)("./CaptivityDurationState")

local CapturePersistenceRules = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("CapturePersistenceRules"))
	else (require :: any)("./CapturePersistenceRules")

local CustodyTransferState: any = {}

export type TransferTerms = {
	targetUserId: number,
	outgoingCustodianUserId: number,
	incomingCustodianUserId: number,
	captivityAnchorAt: number,
	custodyExpiresAt: number,
	absoluteDeadlineAt: number,
	containmentPhase: string,
	containedAt: number?,
	remainingSeconds: number,
	endConditions: { string },
}

export type TransferRequest = {
	requestId: string,
	terms: TransferTerms,
	requestedAt: number,
	requestExpiresAt: number,
	outgoingConfirmedAt: number,
	incomingConfirmedAt: number?,
}

export type State = {
	pendingByRequestId: { [string]: TransferRequest? },
	pendingRequestIdByTargetUserId: { [number]: string? },
	lastReason: string?,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	state: State,
	request: TransferRequest?,
	terms: TransferTerms?,
}

local END_CONDITIONS: { string } = {
	CapturePersistenceRules.CustodyEndReasons.escaped,
	CapturePersistenceRules.CustodyEndReasons.rescued,
	CapturePersistenceRules.CustodyEndReasons.released,
	CapturePersistenceRules.CustodyEndReasons.timeout,
	CapturePersistenceRules.CustodyEndReasons.safe_return,
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

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
end

local function validNow(now: any): boolean
	return isFiniteNumber(now) and (now :: number) >= 0
end

local function cloneTerms(terms: TransferTerms): TransferTerms
	local endConditions: { string } = {}
	for _, endCondition in ipairs(terms.endConditions) do
		table.insert(endConditions, endCondition)
	end

	return {
		targetUserId = terms.targetUserId,
		outgoingCustodianUserId = terms.outgoingCustodianUserId,
		incomingCustodianUserId = terms.incomingCustodianUserId,
		captivityAnchorAt = terms.captivityAnchorAt,
		custodyExpiresAt = terms.custodyExpiresAt,
		absoluteDeadlineAt = terms.absoluteDeadlineAt,
		containmentPhase = terms.containmentPhase,
		containedAt = terms.containedAt,
		remainingSeconds = terms.remainingSeconds,
		endConditions = endConditions,
	}
end

local function cloneRequest(request: TransferRequest): TransferRequest
	return {
		requestId = request.requestId,
		terms = cloneTerms(request.terms),
		requestedAt = request.requestedAt,
		requestExpiresAt = request.requestExpiresAt,
		outgoingConfirmedAt = request.outgoingConfirmedAt,
		incomingConfirmedAt = request.incomingConfirmedAt,
	}
end

local function cloneState(state: State): State
	local pendingByRequestId: { [string]: TransferRequest? } = {}
	for requestId, request in pairs(state.pendingByRequestId) do
		if request ~= nil then
			pendingByRequestId[requestId] = cloneRequest(request)
		end
	end

	return {
		pendingByRequestId = pendingByRequestId,
		pendingRequestIdByTargetUserId = table.clone(state.pendingRequestIdByTargetUserId),
		lastReason = state.lastReason,
	}
end

function CustodyTransferState.NewState(): State
	return {
		pendingByRequestId = {},
		pendingRequestIdByTargetUserId = {},
		lastReason = nil,
	}
end

local function pruneExpiredInPlace(nextState: State, now: number)
	local expiredRequestIds: { string } = {}

	for requestId, request in pairs(nextState.pendingByRequestId) do
		if request ~= nil and request.requestExpiresAt <= now then
			table.insert(expiredRequestIds, requestId)
		end
	end

	for _, requestId in ipairs(expiredRequestIds) do
		local request = nextState.pendingByRequestId[requestId]
		if request ~= nil then
			nextState.pendingRequestIdByTargetUserId[request.terms.targetUserId] = nil
			nextState.pendingByRequestId[requestId] = nil
		end
	end
end

function CustodyTransferState.PruneExpired(state: State, now: number): State
	if not validNow(now) then
		return cloneState(state)
	end

	local nextState = cloneState(state)
	pruneExpiredInPlace(nextState, now)
	return nextState
end

function CustodyTransferState.GetEndConditions(): { string }
	local endConditions: { string } = {}
	for _, endCondition in ipairs(END_CONDITIONS) do
		table.insert(endConditions, endCondition)
	end
	return endConditions
end

function CustodyTransferState.BuildTerms(input: any, config: any?): TransferTerms?
	if type(input) ~= "table" then
		return nil
	end

	local record = input.record
	local incomingCustodianUserId = input.incomingCustodianUserId
	local now = input.now
	if type(record) ~= "table" or not isPositiveInteger(incomingCustodianUserId) or not validNow(now) then
		return nil
	end

	local anchorAt = if isFiniteNumber(record.captivityAnchorAt) then record.captivityAnchorAt else record.startedAt
	if not isFiniteNumber(anchorAt) or not isFiniteNumber(record.expiresAt) then
		return nil
	end

	local absoluteDeadlineAt = CaptivityDurationState.ResolveAbsoluteDeadline(record, config)
	if not isFiniteNumber(absoluteDeadlineAt) then
		return nil
	end

	local remainingSeconds = math.max(0, (absoluteDeadlineAt :: number) - (now :: number))
	local containmentPhase = if type(record.containmentPhase) == "string"
		then record.containmentPhase
		else CaptivityDurationState.Phases.captured

	return {
		targetUserId = record.targetUserId,
		outgoingCustodianUserId = record.custodianUserId,
		incomingCustodianUserId = incomingCustodianUserId,
		captivityAnchorAt = anchorAt :: number,
		custodyExpiresAt = record.expiresAt,
		absoluteDeadlineAt = absoluteDeadlineAt :: number,
		containmentPhase = containmentPhase,
		containedAt = if isFiniteNumber(record.containedAt) then record.containedAt else nil,
		remainingSeconds = remainingSeconds,
		endConditions = CustodyTransferState.GetEndConditions(),
	}
end

function CustodyTransferState.TermsMatchCaptureRecord(terms: any, record: any): boolean
	if type(terms) ~= "table" or type(record) ~= "table" then
		return false
	end

	if terms.targetUserId ~= record.targetUserId then
		return false
	end
	if terms.outgoingCustodianUserId ~= record.custodianUserId then
		return false
	end

	local anchorAt = if isFiniteNumber(record.captivityAnchorAt) then record.captivityAnchorAt else record.startedAt
	if terms.captivityAnchorAt ~= anchorAt then
		return false
	end
	if terms.custodyExpiresAt ~= record.expiresAt then
		return false
	end

	local containmentPhase = if type(record.containmentPhase) == "string"
		then record.containmentPhase
		else CaptivityDurationState.Phases.captured
	if terms.containmentPhase ~= containmentPhase then
		return false
	end

	local containedAt = if isFiniteNumber(record.containedAt) then record.containedAt else nil
	if terms.containedAt ~= containedAt then
		return false
	end

	return true
end

function CustodyTransferState.GetPendingByTargetUserId(state: State, targetUserId: number): TransferRequest?
	local requestId = state.pendingRequestIdByTargetUserId[targetUserId]
	if type(requestId) ~= "string" then
		return nil
	end
	local request = state.pendingByRequestId[requestId]
	if request == nil then
		return nil
	end
	return cloneRequest(request)
end

function CustodyTransferState.GetPendingByRequestId(state: State, requestId: string): TransferRequest?
	local request = state.pendingByRequestId[requestId]
	if request == nil then
		return nil
	end
	return cloneRequest(request)
end

function CustodyTransferState.ResolveRequest(state: State, input: any, config: any?): TransitionResult
	local nextState = cloneState(state)

	if type(input) ~= "table" then
		nextState.lastReason = "transfer_input_invalid"
		return { accepted = false, reason = "transfer_input_invalid", state = nextState, request = nil, terms = nil }
	end

	local now = input.now
	local outgoingCustodianUserId = input.outgoingCustodianUserId
	local incomingCustodianUserId = input.incomingCustodianUserId
	local targetUserId = input.targetUserId
	local record = input.record
	local requestExpirySeconds = input.requestExpirySeconds
	local requestId = input.requestId

	if not validNow(now) then
		nextState.lastReason = "transfer_now_invalid"
		return { accepted = false, reason = "transfer_now_invalid", state = nextState, request = nil, terms = nil }
	end
	if not isPositiveInteger(outgoingCustodianUserId) then
		nextState.lastReason = "outgoing_custodian_invalid"
		return { accepted = false, reason = "outgoing_custodian_invalid", state = nextState, request = nil, terms = nil }
	end
	if not isPositiveInteger(incomingCustodianUserId) then
		nextState.lastReason = "incoming_custodian_invalid"
		return { accepted = false, reason = "incoming_custodian_invalid", state = nextState, request = nil, terms = nil }
	end
	if not isPositiveInteger(targetUserId) then
		nextState.lastReason = "target_user_id_invalid"
		return { accepted = false, reason = "target_user_id_invalid", state = nextState, request = nil, terms = nil }
	end
	if outgoingCustodianUserId == incomingCustodianUserId then
		nextState.lastReason = "transfer_custodian_unchanged"
		return {
			accepted = false,
			reason = "transfer_custodian_unchanged",
			state = nextState,
			request = nil,
			terms = nil,
		}
	end
	if type(record) ~= "table" then
		nextState.lastReason = "capture_record_invalid"
		return { accepted = false, reason = "capture_record_invalid", state = nextState, request = nil, terms = nil }
	end
	if record.targetUserId ~= targetUserId then
		nextState.lastReason = "target_mismatch"
		return { accepted = false, reason = "target_mismatch", state = nextState, request = nil, terms = nil }
	end
	if record.custodianUserId ~= outgoingCustodianUserId then
		nextState.lastReason = "custodian_mismatch"
		return { accepted = false, reason = "custodian_mismatch", state = nextState, request = nil, terms = nil }
	end
	if type(requestId) ~= "string" or requestId == "" then
		nextState.lastReason = "request_id_invalid"
		return { accepted = false, reason = "request_id_invalid", state = nextState, request = nil, terms = nil }
	end
	if not isFiniteNumber(requestExpirySeconds) or (requestExpirySeconds :: number) <= 0 then
		nextState.lastReason = "request_expiry_invalid"
		return { accepted = false, reason = "request_expiry_invalid", state = nextState, request = nil, terms = nil }
	end

	pruneExpiredInPlace(nextState, now)

	if nextState.pendingRequestIdByTargetUserId[targetUserId] ~= nil then
		nextState.lastReason = "transfer_already_pending"
		return { accepted = false, reason = "transfer_already_pending", state = nextState, request = nil, terms = nil }
	end

	local transferPreview = CaptivityDurationState.ResolveTransfer({
		record = record,
		newCustodianUserId = incomingCustodianUserId,
		now = now,
	}, config)
	if transferPreview.accepted ~= true then
		nextState.lastReason = transferPreview.reason
		return {
			accepted = false,
			reason = transferPreview.reason,
			state = nextState,
			request = nil,
			terms = nil,
		}
	end

	local terms = CustodyTransferState.BuildTerms({
		record = record,
		incomingCustodianUserId = incomingCustodianUserId,
		now = now,
	}, config)
	if terms == nil then
		nextState.lastReason = "transfer_terms_invalid"
		return { accepted = false, reason = "transfer_terms_invalid", state = nextState, request = nil, terms = nil }
	end

	local request: TransferRequest = {
		requestId = requestId,
		terms = terms,
		requestedAt = now,
		requestExpiresAt = now + (requestExpirySeconds :: number),
		outgoingConfirmedAt = now,
		incomingConfirmedAt = nil,
	}

	nextState.pendingByRequestId[requestId] = request
	nextState.pendingRequestIdByTargetUserId[targetUserId] = requestId
	nextState.lastReason = "transfer_requested"

	return {
		accepted = true,
		reason = "transfer_requested",
		state = nextState,
		request = cloneRequest(request),
		terms = cloneTerms(terms),
	}
end

function CustodyTransferState.ResolveConfirm(state: State, input: any, config: any?): TransitionResult
	local nextState = cloneState(state)

	if type(input) ~= "table" then
		nextState.lastReason = "transfer_input_invalid"
		return { accepted = false, reason = "transfer_input_invalid", state = nextState, request = nil, terms = nil }
	end

	local now = input.now
	local incomingCustodianUserId = input.incomingCustodianUserId
	local requestId = input.requestId
	local record = input.record

	if not validNow(now) then
		nextState.lastReason = "transfer_now_invalid"
		return { accepted = false, reason = "transfer_now_invalid", state = nextState, request = nil, terms = nil }
	end
	if not isPositiveInteger(incomingCustodianUserId) then
		nextState.lastReason = "incoming_custodian_invalid"
		return { accepted = false, reason = "incoming_custodian_invalid", state = nextState, request = nil, terms = nil }
	end
	if type(requestId) ~= "string" or requestId == "" then
		nextState.lastReason = "request_id_invalid"
		return { accepted = false, reason = "request_id_invalid", state = nextState, request = nil, terms = nil }
	end
	if type(record) ~= "table" then
		nextState.lastReason = "capture_record_invalid"
		return { accepted = false, reason = "capture_record_invalid", state = nextState, request = nil, terms = nil }
	end

	pruneExpiredInPlace(nextState, now)

	local pending = nextState.pendingByRequestId[requestId]
	if pending == nil then
		nextState.lastReason = "transfer_request_missing"
		return { accepted = false, reason = "transfer_request_missing", state = nextState, request = nil, terms = nil }
	end
	if pending.requestExpiresAt <= now then
		nextState.pendingRequestIdByTargetUserId[pending.terms.targetUserId] = nil
		nextState.pendingByRequestId[requestId] = nil
		nextState.lastReason = "transfer_request_expired"
		return { accepted = false, reason = "transfer_request_expired", state = nextState, request = nil, terms = nil }
	end
	if pending.terms.incomingCustodianUserId ~= incomingCustodianUserId then
		nextState.lastReason = "incoming_custodian_mismatch"
		return {
			accepted = false,
			reason = "incoming_custodian_mismatch",
			state = nextState,
			request = nil,
			terms = nil,
		}
	end
	if not CustodyTransferState.TermsMatchCaptureRecord(pending.terms, record) then
		nextState.lastReason = "transfer_terms_changed"
		return { accepted = false, reason = "transfer_terms_changed", state = nextState, request = nil, terms = nil }
	end

	local transferPreview = CaptivityDurationState.ResolveTransfer({
		record = record,
		newCustodianUserId = incomingCustodianUserId,
		now = now,
	}, config)
	if transferPreview.accepted ~= true then
		nextState.lastReason = transferPreview.reason
		return {
			accepted = false,
			reason = transferPreview.reason,
			state = nextState,
			request = nil,
			terms = nil,
		}
	end

	local settledRequest = cloneRequest(pending)
	settledRequest.incomingConfirmedAt = now
	local settledTerms = cloneTerms(pending.terms)

	nextState.pendingRequestIdByTargetUserId[pending.terms.targetUserId] = nil
	nextState.pendingByRequestId[requestId] = nil
	nextState.lastReason = "transfer_confirmed"

	return {
		accepted = true,
		reason = "transfer_confirmed",
		state = nextState,
		request = settledRequest,
		terms = settledTerms,
	}
end

function CustodyTransferState.ResolveCancel(state: State, input: any): TransitionResult
	local nextState = cloneState(state)

	if type(input) ~= "table" then
		nextState.lastReason = "transfer_input_invalid"
		return { accepted = false, reason = "transfer_input_invalid", state = nextState, request = nil, terms = nil }
	end

	local now = input.now
	local requestId = input.requestId
	local actorUserId = input.actorUserId

	if not validNow(now) then
		nextState.lastReason = "transfer_now_invalid"
		return { accepted = false, reason = "transfer_now_invalid", state = nextState, request = nil, terms = nil }
	end
	if type(requestId) ~= "string" or requestId == "" then
		nextState.lastReason = "request_id_invalid"
		return { accepted = false, reason = "request_id_invalid", state = nextState, request = nil, terms = nil }
	end
	if not isPositiveInteger(actorUserId) then
		nextState.lastReason = "actor_user_id_invalid"
		return { accepted = false, reason = "actor_user_id_invalid", state = nextState, request = nil, terms = nil }
	end

	pruneExpiredInPlace(nextState, now)

	local pending = nextState.pendingByRequestId[requestId]
	if pending == nil then
		nextState.lastReason = "transfer_request_missing"
		return { accepted = false, reason = "transfer_request_missing", state = nextState, request = nil, terms = nil }
	end

	if
		actorUserId ~= pending.terms.outgoingCustodianUserId
		and actorUserId ~= pending.terms.incomingCustodianUserId
	then
		nextState.lastReason = "transfer_cancel_unauthorized"
		return {
			accepted = false,
			reason = "transfer_cancel_unauthorized",
			state = nextState,
			request = nil,
			terms = nil,
		}
	end

	nextState.pendingRequestIdByTargetUserId[pending.terms.targetUserId] = nil
	nextState.pendingByRequestId[requestId] = nil
	nextState.lastReason = "transfer_cancelled"

	return {
		accepted = true,
		reason = "transfer_cancelled",
		state = nextState,
		request = cloneRequest(pending),
		terms = cloneTerms(pending.terms),
	}
end

function CustodyTransferState.RemovePlayer(state: State, userId: number): State
	local nextState = cloneState(state)
	local cancelledRequestIds: { string } = {}

	for requestId, request in pairs(nextState.pendingByRequestId) do
		if request ~= nil then
			if
				request.terms.outgoingCustodianUserId == userId
				or request.terms.incomingCustodianUserId == userId
				or request.terms.targetUserId == userId
			then
				table.insert(cancelledRequestIds, requestId)
			end
		end
	end

	for _, requestId in ipairs(cancelledRequestIds) do
		local request = nextState.pendingByRequestId[requestId]
		if request ~= nil then
			nextState.pendingRequestIdByTargetUserId[request.terms.targetUserId] = nil
			nextState.pendingByRequestId[requestId] = nil
		end
	end

	return nextState
end

return CustodyTransferState
