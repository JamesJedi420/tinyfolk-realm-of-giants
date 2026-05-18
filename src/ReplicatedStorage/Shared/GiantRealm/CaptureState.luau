--!strict

local CaptureState = {}

export type CaptureRecord = {
	custodianUserId: number,
	targetUserId: number,
	startedAt: number,
	expiresAt: number,
}

export type State = {
	captureByTarget: { [number]: CaptureRecord? },
	custodianByTarget: { [number]: number? },
	lastReason: string?,
}

export type RequestInput = {
	now: number,
	custodianUserId: number,
	targetUserId: number,
	custodianRole: string?,
	targetRole: string?,
	custodianAlive: boolean,
	targetDowned: boolean,
	inRange: boolean,
	custodyWindowSeconds: number,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	state: State,
	record: CaptureRecord?,
}

local function validNumber(value: any): boolean
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

local function validNow(now: any): boolean
	if not validNumber(now) then
		return false
	end
	return now >= 0
end

local function cloneState(state: State): State
	local captureByTarget: { [number]: CaptureRecord? } = {}
	for targetUserId, record in pairs(state.captureByTarget) do
		if record ~= nil then
			captureByTarget[targetUserId] = {
				custodianUserId = record.custodianUserId,
				targetUserId = record.targetUserId,
				startedAt = record.startedAt,
				expiresAt = record.expiresAt,
			}
		end
	end

	local custodianByTarget: { [number]: number? } = {}
	for targetUserId, custodianUserId in pairs(state.custodianByTarget) do
		custodianByTarget[targetUserId] = custodianUserId
	end

	return {
		captureByTarget = captureByTarget,
		custodianByTarget = custodianByTarget,
		lastReason = state.lastReason,
	}
end

function CaptureState.NewState(): State
	return {
		captureByTarget = {},
		custodianByTarget = {},
		lastReason = nil,
	}
end

local function pruneExpiredInPlace(nextState: State, now: number)
	local expiredTargets: { number } = {}

	for targetUserId, record in pairs(nextState.captureByTarget) do
		if record ~= nil then
			if record.expiresAt <= now then
				table.insert(expiredTargets, targetUserId)
			end
		end
	end

	for _, targetUserId in ipairs(expiredTargets) do
		local record = nextState.captureByTarget[targetUserId]
		if record ~= nil then
			nextState.custodianByTarget[targetUserId] = nil
			nextState.captureByTarget[targetUserId] = nil
		end
	end
end

function CaptureState.PruneExpired(state: State, now: number): State
	if not validNow(now) then
		return cloneState(state)
	end

	local nextState = cloneState(state)
	pruneExpiredInPlace(nextState, now)
	return nextState
end

function CaptureState.ResolveRequest(state: State, input: RequestInput): TransitionResult
	local nextState = cloneState(state)

	if not validNow(input.now) then
		nextState.lastReason = "invalid_now"
		return { accepted = false, reason = "invalid_now", state = nextState, record = nil }
	end

	pruneExpiredInPlace(nextState, input.now)

	if input.custodianRole ~= "Giant" then
		nextState.lastReason = "custodian_not_giant"
		return { accepted = false, reason = "custodian_not_giant", state = nextState, record = nil }
	end

	if input.targetRole ~= "Tinyfolk" then
		nextState.lastReason = "target_not_tinyfolk"
		return { accepted = false, reason = "target_not_tinyfolk", state = nextState, record = nil }
	end

	if input.custodianAlive ~= true then
		nextState.lastReason = "custodian_not_alive"
		return { accepted = false, reason = "custodian_not_alive", state = nextState, record = nil }
	end

	if input.targetDowned ~= true then
		nextState.lastReason = "target_not_downed"
		return { accepted = false, reason = "target_not_downed", state = nextState, record = nil }
	end

	if input.inRange ~= true then
		nextState.lastReason = "target_out_of_range"
		return { accepted = false, reason = "target_out_of_range", state = nextState, record = nil }
	end

	if nextState.captureByTarget[input.targetUserId] ~= nil then
		nextState.lastReason = "target_already_captured"
		return { accepted = false, reason = "target_already_captured", state = nextState, record = nil }
	end

	if nextState.custodianByTarget[input.custodianUserId] ~= nil then
		nextState.lastReason = "custodian_already_holding"
		return { accepted = false, reason = "custodian_already_holding", state = nextState, record = nil }
	end

	local custodyWindowSeconds = if validNumber(input.custodyWindowSeconds) and input.custodyWindowSeconds > 0
		then input.custodyWindowSeconds
		else 0

	local record: CaptureRecord = {
		custodianUserId = input.custodianUserId,
		targetUserId = input.targetUserId,
		startedAt = input.now,
		expiresAt = input.now + custodyWindowSeconds,
	}

	nextState.captureByTarget[input.targetUserId] = record
	nextState.custodianByTarget[input.targetUserId] = input.custodianUserId
	nextState.lastReason = "accepted"

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		record = record,
	}
end

function CaptureState.ResolveRelease(state: State, input: { now: number, targetUserId: number }): TransitionResult
	local nextState = cloneState(state)

	if not validNow(input.now) then
		nextState.lastReason = "invalid_now"
		return { accepted = false, reason = "invalid_now", state = nextState, record = nil }
	end

	pruneExpiredInPlace(nextState, input.now)

	local record = nextState.captureByTarget[input.targetUserId]
	if record == nil then
		nextState.lastReason = "capture_missing"
		return { accepted = false, reason = "capture_missing", state = nextState, record = nil }
	end

	nextState.captureByTarget[input.targetUserId] = nil
	nextState.custodianByTarget[input.targetUserId] = nil
	nextState.lastReason = "released"

	return {
		accepted = true,
		reason = "released",
		state = nextState,
		record = record,
	}
end

function CaptureState.GetTargetCapture(state: State, targetUserId: number): CaptureRecord?
	return state.captureByTarget[targetUserId]
end

function CaptureState.GetCustodianCapture(state: State, custodianUserId: number): CaptureRecord?
	for targetUserId, record in pairs(state.captureByTarget) do
		if record ~= nil and record.custodianUserId == custodianUserId then
			return record
		end
	end
	return nil
end

function CaptureState.GetAllCaptures(state: State): { CaptureRecord }
	local captures: { CaptureRecord } = {}
	for _, record in pairs(state.captureByTarget) do
		if record ~= nil then
			table.insert(captures, {
				custodianUserId = record.custodianUserId,
				targetUserId = record.targetUserId,
				startedAt = record.startedAt,
				expiresAt = record.expiresAt,
			})
		end
	end

	table.sort(captures, function(a: CaptureRecord, b: CaptureRecord)
		if a.custodianUserId == b.custodianUserId then
			return a.targetUserId < b.targetUserId
		end
		return a.custodianUserId < b.custodianUserId
	end)

	return captures
end

function CaptureState.RemovePlayer(state: State, userId: number): State
	local nextState = cloneState(state)

	local removedTargets: { [number]: boolean } = {}
	for targetUserId, record in pairs(nextState.captureByTarget) do
		if record ~= nil then
			if record.custodianUserId == userId or targetUserId == userId then
				removedTargets[targetUserId] = true
				nextState.captureByTarget[targetUserId] = nil
			end
		end
	end

	for targetUserId, custodianUserId in pairs(nextState.custodianByTarget) do
		if targetUserId == userId or custodianUserId == userId or removedTargets[targetUserId] == true then
			nextState.custodianByTarget[targetUserId] = nil
		end
	end

	return nextState
end

return CaptureState
