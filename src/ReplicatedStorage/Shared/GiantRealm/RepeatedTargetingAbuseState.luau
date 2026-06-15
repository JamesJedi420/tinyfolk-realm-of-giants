--!strict

local RepeatedTargetingAbuseConfig = require("../Config/RepeatedTargetingAbuseConfig")

local RepeatedTargetingAbuseState = {}

RepeatedTargetingAbuseState.EventKinds = {
	CaptureStart = "capture_start",
	CustodyEnd = "custody_end",
	CustodyTransfer = "custody_transfer",
	PairRewardCap = "pair_reward_cap",
}

RepeatedTargetingAbuseState.PatternKinds = {
	PairRepeatTargeting = "pair_repeat_targeting",
	TargetCustodyLoop = "target_custody_loop",
	CustodyTransferLoop = "custody_transfer_loop",
	ShortCustodyCycle = "short_custody_cycle",
	PairRewardCapReached = "pair_reward_cap_reached",
}

export type EventEntry = {
	at: number,
	kind: string,
	custodianUserId: number?,
	endReason: string?,
	outgoingCustodianUserId: number?,
	incomingCustodianUserId: number?,
	pairRewardCount: number?,
}

export type SuspiciousLoopRecord = {
	sequence: number,
	at: number,
	patternKind: string,
	targetUserId: number,
	custodianUserId: number?,
	outgoingCustodianUserId: number?,
	incomingCustodianUserId: number?,
	eventCount: number,
	windowSeconds: number,
	detectionKey: string,
	operationId: string?,
}

export type CustodyBlockRecord = {
	blockKey: string,
	patternKind: string,
	custodianUserId: number?,
	targetUserId: number?,
	outgoingCustodianUserId: number?,
	incomingCustodianUserId: number?,
	startedAt: number,
	expiresAt: number,
}

export type State = {
	pairEventsByKey: { [string]: { EventEntry } },
	targetEventsByUserId: { [number]: { EventEntry } },
	transferEventsByTargetUserId: { [number]: { EventEntry } },
	suspiciousLoops: { SuspiciousLoopRecord },
	lastDetectionAtByKey: { [string]: number? },
	activeCustodyBlocks: { [string]: CustodyBlockRecord },
	sequence: number,
	lastReason: string?,
}

export type RecordInput = {
	now: number,
	kind: string,
	targetUserId: number,
	custodianUserId: number?,
	endReason: string?,
	outgoingCustodianUserId: number?,
	incomingCustodianUserId: number?,
	pairRewardCount: number?,
	operationId: string?,
}

export type RecordResult = {
	accepted: boolean,
	reason: string,
	state: State,
	detections: { SuspiciousLoopRecord },
}

export type CustodyBlockInput = {
	custodianUserId: number,
	targetUserId: number,
	incomingCustodianUserId: number?,
	outgoingCustodianUserId: number?,
	interactionKind: string?,
	now: number,
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
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function positiveNumber(value: any, fallback: number): number
	if not isFiniteNumber(value) or (value :: number) <= 0 then
		return fallback
	end
	return value :: number
end

local function maxSuspiciousLoopRecords(config: any): number
	local configured = if config ~= nil then (config :: any).MaxSuspiciousLoopRecords else nil
	if type(configured) == "number" and configured >= 1 then
		return math.max(1, math.floor(configured))
	end
	return RepeatedTargetingAbuseConfig.MaxSuspiciousLoopRecords
end

local function makePairKey(custodianUserId: number, targetUserId: number): string
	return string.format("%d|%d", custodianUserId, targetUserId)
end

local function makeCustodianPairKey(a: number, b: number): string
	if a <= b then
		return string.format("%d|%d", a, b)
	end
	return string.format("%d|%d", b, a)
end

local function cloneEventEntry(entry: EventEntry): EventEntry
	return {
		at = entry.at,
		kind = entry.kind,
		custodianUserId = entry.custodianUserId,
		endReason = entry.endReason,
		outgoingCustodianUserId = entry.outgoingCustodianUserId,
		incomingCustodianUserId = entry.incomingCustodianUserId,
		pairRewardCount = entry.pairRewardCount,
	}
end

local function cloneSuspiciousLoop(record: SuspiciousLoopRecord): SuspiciousLoopRecord
	return {
		sequence = record.sequence,
		at = record.at,
		patternKind = record.patternKind,
		targetUserId = record.targetUserId,
		custodianUserId = record.custodianUserId,
		outgoingCustodianUserId = record.outgoingCustodianUserId,
		incomingCustodianUserId = record.incomingCustodianUserId,
		eventCount = record.eventCount,
		windowSeconds = record.windowSeconds,
		detectionKey = record.detectionKey,
		operationId = record.operationId,
	}
end

local function cloneState(state: State): State
	local pairEventsByKey: { [string]: { EventEntry } } = {}
	for key, events in pairs(state.pairEventsByKey) do
		local clonedEvents: { EventEntry } = {}
		for _, eventEntry in ipairs(events) do
			table.insert(clonedEvents, cloneEventEntry(eventEntry))
		end
		pairEventsByKey[key] = clonedEvents
	end

	local targetEventsByUserId: { [number]: { EventEntry } } = {}
	for userId, events in pairs(state.targetEventsByUserId) do
		local clonedEvents: { EventEntry } = {}
		for _, eventEntry in ipairs(events) do
			table.insert(clonedEvents, cloneEventEntry(eventEntry))
		end
		targetEventsByUserId[userId] = clonedEvents
	end

	local transferEventsByTargetUserId: { [number]: { EventEntry } } = {}
	for userId, events in pairs(state.transferEventsByTargetUserId) do
		local clonedEvents: { EventEntry } = {}
		for _, eventEntry in ipairs(events) do
			table.insert(clonedEvents, cloneEventEntry(eventEntry))
		end
		transferEventsByTargetUserId[userId] = clonedEvents
	end

	local suspiciousLoops: { SuspiciousLoopRecord } = {}
	for _, record in ipairs(state.suspiciousLoops) do
		table.insert(suspiciousLoops, cloneSuspiciousLoop(record))
	end

	local lastDetectionAtByKey: { [string]: number? } = table.clone(state.lastDetectionAtByKey)

	local activeCustodyBlocks: { [string]: CustodyBlockRecord } = {}
	for key, block in pairs(state.activeCustodyBlocks) do
		activeCustodyBlocks[key] = {
			blockKey = block.blockKey,
			patternKind = block.patternKind,
			custodianUserId = block.custodianUserId,
			targetUserId = block.targetUserId,
			outgoingCustodianUserId = block.outgoingCustodianUserId,
			incomingCustodianUserId = block.incomingCustodianUserId,
			startedAt = block.startedAt,
			expiresAt = block.expiresAt,
		}
	end

	return {
		pairEventsByKey = pairEventsByKey,
		targetEventsByUserId = targetEventsByUserId,
		transferEventsByTargetUserId = transferEventsByTargetUserId,
		suspiciousLoops = suspiciousLoops,
		lastDetectionAtByKey = lastDetectionAtByKey,
		activeCustodyBlocks = activeCustodyBlocks,
		sequence = state.sequence,
		lastReason = state.lastReason,
	}
end

local function pruneEvents(events: { EventEntry }, now: number, windowSeconds: number): { EventEntry }
	local output: { EventEntry } = {}
	for _, eventEntry in ipairs(events) do
		if now - eventEntry.at <= windowSeconds then
			table.insert(output, cloneEventEntry(eventEntry))
		end
	end
	return output
end

local function countEventsInWindow(
	events: { EventEntry },
	now: number,
	windowSeconds: number,
	kindFilter: string?
): number
	local count = 0
	for _, eventEntry in ipairs(events) do
		if now - eventEntry.at <= windowSeconds then
			if kindFilter == nil or eventEntry.kind == kindFilter then
				count += 1
			end
		end
	end
	return count
end

local function resolveCustodianUserId(input: RecordInput): number?
	if isPositiveInteger(input.custodianUserId) then
		return input.custodianUserId
	end
	if input.kind == RepeatedTargetingAbuseState.EventKinds.CustodyTransfer then
		if isPositiveInteger(input.incomingCustodianUserId) then
			return input.incomingCustodianUserId
		end
	end
	return nil
end

local function isCustodyBlockPatternEnabled(patternKind: string, config: any): boolean
	local patterns = if config ~= nil and type((config :: any).CustodyBlockPatterns) == "table"
		then (config :: any).CustodyBlockPatterns
		else RepeatedTargetingAbuseConfig.CustodyBlockPatterns
	if type(patterns) ~= "table" then
		return false
	end
	return patterns[patternKind] == true
end

local function custodyBlockDuration(config: any): number
	return positiveNumber(
		if config ~= nil then (config :: any).CustodyBlockDurationSeconds else nil,
		RepeatedTargetingAbuseConfig.CustodyBlockDurationSeconds
	)
end

local function registerCustodyBlocksFromDetection(state: State, detection: SuspiciousLoopRecord, config: any): State
	if not isCustodyBlockPatternEnabled(detection.patternKind, config) then
		return state
	end

	local duration = custodyBlockDuration(config)
	local expiresAt = detection.at + duration
	local kinds = RepeatedTargetingAbuseState.PatternKinds

	if detection.patternKind == kinds.PairRepeatTargeting or detection.patternKind == kinds.ShortCustodyCycle then
		if isPositiveInteger(detection.custodianUserId) then
			local custodianId = detection.custodianUserId :: number
			local key = string.format("pair:%d:%d", custodianId, detection.targetUserId)
			state.activeCustodyBlocks[key] = {
				blockKey = key,
				patternKind = detection.patternKind,
				custodianUserId = custodianId,
				targetUserId = detection.targetUserId,
				outgoingCustodianUserId = nil,
				incomingCustodianUserId = nil,
				startedAt = detection.at,
				expiresAt = expiresAt,
			}
		end
		return state
	end

	if detection.patternKind == kinds.TargetCustodyLoop then
		local key = string.format("target:%d", detection.targetUserId)
		state.activeCustodyBlocks[key] = {
			blockKey = key,
			patternKind = detection.patternKind,
			custodianUserId = detection.custodianUserId,
			targetUserId = detection.targetUserId,
			outgoingCustodianUserId = nil,
			incomingCustodianUserId = nil,
			startedAt = detection.at,
			expiresAt = expiresAt,
		}
		return state
	end

	if detection.patternKind == kinds.CustodyTransferLoop then
		if
			isPositiveInteger(detection.outgoingCustodianUserId)
			and isPositiveInteger(detection.incomingCustodianUserId)
		then
			local outgoingCustodianUserId = detection.outgoingCustodianUserId :: number
			local incomingCustodianUserId = detection.incomingCustodianUserId :: number
			local transferKey = string.format(
				"transfer:%d:%d:%d",
				detection.targetUserId,
				outgoingCustodianUserId,
				incomingCustodianUserId
			)
			state.activeCustodyBlocks[transferKey] = {
				blockKey = transferKey,
				patternKind = detection.patternKind,
				custodianUserId = nil,
				targetUserId = detection.targetUserId,
				outgoingCustodianUserId = outgoingCustodianUserId,
				incomingCustodianUserId = incomingCustodianUserId,
				startedAt = detection.at,
				expiresAt = expiresAt,
			}
			local outgoingPairKey = string.format("pair:%d:%d", outgoingCustodianUserId, detection.targetUserId)
			state.activeCustodyBlocks[outgoingPairKey] = {
				blockKey = outgoingPairKey,
				patternKind = detection.patternKind,
				custodianUserId = outgoingCustodianUserId,
				targetUserId = detection.targetUserId,
				outgoingCustodianUserId = outgoingCustodianUserId,
				incomingCustodianUserId = incomingCustodianUserId,
				startedAt = detection.at,
				expiresAt = expiresAt,
			}
		end
	end

	return state
end

function RepeatedTargetingAbuseState.NewState(): State
	return {
		pairEventsByKey = {},
		targetEventsByUserId = {},
		transferEventsByTargetUserId = {},
		suspiciousLoops = {},
		lastDetectionAtByKey = {},
		activeCustodyBlocks = {},
		sequence = 0,
		lastReason = nil,
	}
end

local function appendDetection(
	state: State,
	config: any,
	detection: SuspiciousLoopRecord
): (State, SuspiciousLoopRecord?)
	local nextState = cloneState(state)
	local cooldownSeconds = positiveNumber(
		if config ~= nil then (config :: any).DetectionLogCooldownSeconds else nil,
		RepeatedTargetingAbuseConfig.DetectionLogCooldownSeconds
	)
	local lastAt = nextState.lastDetectionAtByKey[detection.detectionKey]
	if type(lastAt) == "number" and (detection.at - lastAt) < cooldownSeconds then
		nextState.lastReason = "detection_cooldown_active"
		return nextState, nil
	end

	nextState.sequence += 1
	local record = cloneSuspiciousLoop(detection)
	record.sequence = nextState.sequence
	table.insert(nextState.suspiciousLoops, record)
	while #nextState.suspiciousLoops > maxSuspiciousLoopRecords(config) do
		table.remove(nextState.suspiciousLoops, 1)
	end
	nextState.lastDetectionAtByKey[detection.detectionKey] = detection.at
	nextState.lastReason = "detection_recorded"
	nextState = registerCustodyBlocksFromDetection(nextState, record, config)
	return nextState, record
end

local function evaluatePairRepeatTargeting(
	state: State,
	config: any,
	input: RecordInput,
	pairKey: string
): SuspiciousLoopRecord?
	if input.kind ~= RepeatedTargetingAbuseState.EventKinds.CaptureStart then
		return nil
	end
	if not isPositiveInteger(input.custodianUserId) then
		return nil
	end

	local windowSeconds = positiveNumber(
		if config ~= nil then (config :: any).PairRepeatWindowSeconds else nil,
		RepeatedTargetingAbuseConfig.PairRepeatWindowSeconds
	)
	local threshold = positiveNumber(
		if config ~= nil then (config :: any).PairRepeatCaptureThreshold else nil,
		RepeatedTargetingAbuseConfig.PairRepeatCaptureThreshold
	)
	local events = state.pairEventsByKey[pairKey] or {}
	local count =
		countEventsInWindow(events, input.now, windowSeconds, RepeatedTargetingAbuseState.EventKinds.CaptureStart)
	if count < threshold then
		return nil
	end

	return {
		sequence = 0,
		at = input.now,
		patternKind = RepeatedTargetingAbuseState.PatternKinds.PairRepeatTargeting,
		targetUserId = input.targetUserId,
		custodianUserId = input.custodianUserId,
		outgoingCustodianUserId = nil,
		incomingCustodianUserId = nil,
		eventCount = count,
		windowSeconds = windowSeconds,
		detectionKey = string.format("%s:%s", RepeatedTargetingAbuseState.PatternKinds.PairRepeatTargeting, pairKey),
		operationId = input.operationId,
	}
end

local function evaluateTargetCustodyLoop(state: State, config: any, input: RecordInput): SuspiciousLoopRecord?
	local windowSeconds = positiveNumber(
		if config ~= nil then (config :: any).TargetCustodyLoopWindowSeconds else nil,
		RepeatedTargetingAbuseConfig.TargetCustodyLoopWindowSeconds
	)
	local threshold = positiveNumber(
		if config ~= nil then (config :: any).TargetCustodyLoopThreshold else nil,
		RepeatedTargetingAbuseConfig.TargetCustodyLoopThreshold
	)
	local events = state.targetEventsByUserId[input.targetUserId] or {}
	local count = countEventsInWindow(events, input.now, windowSeconds, nil)
	if count < threshold then
		return nil
	end

	return {
		sequence = 0,
		at = input.now,
		patternKind = RepeatedTargetingAbuseState.PatternKinds.TargetCustodyLoop,
		targetUserId = input.targetUserId,
		custodianUserId = resolveCustodianUserId(input),
		outgoingCustodianUserId = input.outgoingCustodianUserId,
		incomingCustodianUserId = input.incomingCustodianUserId,
		eventCount = count,
		windowSeconds = windowSeconds,
		detectionKey = string.format(
			"%s:%d",
			RepeatedTargetingAbuseState.PatternKinds.TargetCustodyLoop,
			input.targetUserId
		),
		operationId = input.operationId,
	}
end

local function evaluateTransferLoop(state: State, config: any, input: RecordInput): SuspiciousLoopRecord?
	if input.kind ~= RepeatedTargetingAbuseState.EventKinds.CustodyTransfer then
		return nil
	end
	if not isPositiveInteger(input.outgoingCustodianUserId) or not isPositiveInteger(input.incomingCustodianUserId) then
		return nil
	end

	local outgoingCustodianUserId = input.outgoingCustodianUserId :: number
	local incomingCustodianUserId = input.incomingCustodianUserId :: number
	local windowSeconds = positiveNumber(
		if config ~= nil then (config :: any).TransferLoopWindowSeconds else nil,
		RepeatedTargetingAbuseConfig.TransferLoopWindowSeconds
	)
	local threshold = positiveNumber(
		if config ~= nil then (config :: any).TransferLoopThreshold else nil,
		RepeatedTargetingAbuseConfig.TransferLoopThreshold
	)
	local events = state.transferEventsByTargetUserId[input.targetUserId] or {}
	local custodianPairKey = makeCustodianPairKey(outgoingCustodianUserId, incomingCustodianUserId)
	local count = 0
	for _, eventEntry in ipairs(events) do
		if input.now - eventEntry.at > windowSeconds then
			continue
		end
		if
			isPositiveInteger(eventEntry.outgoingCustodianUserId)
			and isPositiveInteger(eventEntry.incomingCustodianUserId)
		then
			local eventPairKey = makeCustodianPairKey(
				eventEntry.outgoingCustodianUserId :: number,
				eventEntry.incomingCustodianUserId :: number
			)
			if eventPairKey == custodianPairKey then
				count += 1
			end
		end
	end
	if count < threshold then
		return nil
	end

	return {
		sequence = 0,
		at = input.now,
		patternKind = RepeatedTargetingAbuseState.PatternKinds.CustodyTransferLoop,
		targetUserId = input.targetUserId,
		custodianUserId = nil,
		outgoingCustodianUserId = outgoingCustodianUserId,
		incomingCustodianUserId = incomingCustodianUserId,
		eventCount = count,
		windowSeconds = windowSeconds,
		detectionKey = string.format(
			"%s:%d:%s",
			RepeatedTargetingAbuseState.PatternKinds.CustodyTransferLoop,
			input.targetUserId,
			custodianPairKey
		),
		operationId = input.operationId,
	}
end

local function evaluateShortCustodyCycle(
	state: State,
	config: any,
	input: RecordInput,
	pairKey: string
): SuspiciousLoopRecord?
	if input.kind ~= RepeatedTargetingAbuseState.EventKinds.CustodyEnd then
		return nil
	end
	if not isPositiveInteger(input.custodianUserId) then
		return nil
	end

	local windowSeconds = positiveNumber(
		if config ~= nil then (config :: any).ShortCycleWindowSeconds else nil,
		RepeatedTargetingAbuseConfig.ShortCycleWindowSeconds
	)
	local maxCycleSeconds = positiveNumber(
		if config ~= nil then (config :: any).ShortCycleMaxSeconds else nil,
		RepeatedTargetingAbuseConfig.ShortCycleMaxSeconds
	)
	local threshold = positiveNumber(
		if config ~= nil then (config :: any).ShortCycleThreshold else nil,
		RepeatedTargetingAbuseConfig.ShortCycleThreshold
	)
	local events = state.pairEventsByKey[pairKey] or {}
	local cycleCount = 0
	for index, eventEntry in ipairs(events) do
		if input.now - eventEntry.at > windowSeconds then
			continue
		end
		if eventEntry.kind ~= RepeatedTargetingAbuseState.EventKinds.CaptureStart then
			continue
		end
		for innerIndex = index + 1, #events do
			local endEntry = events[innerIndex]
			if endEntry.kind ~= RepeatedTargetingAbuseState.EventKinds.CustodyEnd then
				continue
			end
			local elapsed = endEntry.at - eventEntry.at
			if elapsed >= 0 and elapsed <= maxCycleSeconds then
				cycleCount += 1
			end
			break
		end
	end
	if cycleCount < threshold then
		return nil
	end

	return {
		sequence = 0,
		at = input.now,
		patternKind = RepeatedTargetingAbuseState.PatternKinds.ShortCustodyCycle,
		targetUserId = input.targetUserId,
		custodianUserId = input.custodianUserId,
		outgoingCustodianUserId = nil,
		incomingCustodianUserId = nil,
		eventCount = cycleCount,
		windowSeconds = windowSeconds,
		detectionKey = string.format("%s:%s", RepeatedTargetingAbuseState.PatternKinds.ShortCustodyCycle, pairKey),
		operationId = input.operationId,
	}
end

local function evaluatePairRewardCap(
	_state: State,
	config: any,
	input: RecordInput,
	pairKey: string
): SuspiciousLoopRecord?
	if input.kind ~= RepeatedTargetingAbuseState.EventKinds.PairRewardCap then
		return nil
	end
	if not isPositiveInteger(input.custodianUserId) then
		return nil
	end

	if not isFiniteNumber(input.pairRewardCount) then
		return nil
	end

	local pairRewardCount = math.floor(input.pairRewardCount :: number)
	if pairRewardCount <= 0 then
		return nil
	end

	return {
		sequence = 0,
		at = input.now,
		patternKind = RepeatedTargetingAbuseState.PatternKinds.PairRewardCapReached,
		targetUserId = input.targetUserId,
		custodianUserId = input.custodianUserId,
		outgoingCustodianUserId = nil,
		incomingCustodianUserId = nil,
		eventCount = pairRewardCount,
		windowSeconds = positiveNumber(
			if config ~= nil then (config :: any).PairRepeatWindowSeconds else nil,
			RepeatedTargetingAbuseConfig.PairRepeatWindowSeconds
		),
		detectionKey = string.format(
			"%s:%s:%d",
			RepeatedTargetingAbuseState.PatternKinds.PairRewardCapReached,
			pairKey,
			pairRewardCount
		),
		operationId = input.operationId,
	}
end

function RepeatedTargetingAbuseState.RecordEvent(state: State, input: RecordInput, config: any?): RecordResult
	local nextState = cloneState(state)
	local detections: { SuspiciousLoopRecord } = {}

	if type(input) ~= "table" then
		nextState.lastReason = "input_invalid"
		return { accepted = false, reason = "input_invalid", state = nextState, detections = detections }
	end
	if not isFiniteNumber(input.now) or input.now < 0 then
		nextState.lastReason = "timestamp_invalid"
		return { accepted = false, reason = "timestamp_invalid", state = nextState, detections = detections }
	end
	if not isPositiveInteger(input.targetUserId) then
		nextState.lastReason = "target_user_id_invalid"
		return { accepted = false, reason = "target_user_id_invalid", state = nextState, detections = detections }
	end
	if not isNonEmptyString(input.kind) then
		nextState.lastReason = "event_kind_invalid"
		return { accepted = false, reason = "event_kind_invalid", state = nextState, detections = detections }
	end

	local eventEntry: EventEntry = {
		at = input.now,
		kind = input.kind,
		custodianUserId = if isPositiveInteger(input.custodianUserId) then input.custodianUserId else nil,
		endReason = if isNonEmptyString(input.endReason) then input.endReason else nil,
		outgoingCustodianUserId = if isPositiveInteger(input.outgoingCustodianUserId)
			then input.outgoingCustodianUserId
			else nil,
		incomingCustodianUserId = if isPositiveInteger(input.incomingCustodianUserId)
			then input.incomingCustodianUserId
			else nil,
		pairRewardCount = if isFiniteNumber(input.pairRewardCount)
			then math.floor(input.pairRewardCount :: number)
			else nil,
	}

	local targetEvents = nextState.targetEventsByUserId[input.targetUserId] or {}
	table.insert(targetEvents, cloneEventEntry(eventEntry))
	nextState.targetEventsByUserId[input.targetUserId] = pruneEvents(
		targetEvents,
		input.now,
		positiveNumber(
			if config ~= nil then (config :: any).TargetCustodyLoopWindowSeconds else nil,
			RepeatedTargetingAbuseConfig.TargetCustodyLoopWindowSeconds
		)
	)

	if input.kind == RepeatedTargetingAbuseState.EventKinds.CustodyTransfer then
		local transferEvents = nextState.transferEventsByTargetUserId[input.targetUserId] or {}
		table.insert(transferEvents, cloneEventEntry(eventEntry))
		nextState.transferEventsByTargetUserId[input.targetUserId] = pruneEvents(
			transferEvents,
			input.now,
			positiveNumber(
				if config ~= nil then (config :: any).TransferLoopWindowSeconds else nil,
				RepeatedTargetingAbuseConfig.TransferLoopWindowSeconds
			)
		)
	end

	local pairKey: string? = nil
	if isPositiveInteger(input.custodianUserId) then
		local custodianUserId = input.custodianUserId :: number
		local resolvedPairKey = makePairKey(custodianUserId, input.targetUserId)
		pairKey = resolvedPairKey
		local pairEvents = nextState.pairEventsByKey[resolvedPairKey] or {}
		table.insert(pairEvents, cloneEventEntry(eventEntry))
		nextState.pairEventsByKey[resolvedPairKey] = pruneEvents(
			pairEvents,
			input.now,
			math.max(
				positiveNumber(
					if config ~= nil then (config :: any).PairRepeatWindowSeconds else nil,
					RepeatedTargetingAbuseConfig.PairRepeatWindowSeconds
				),
				positiveNumber(
					if config ~= nil then (config :: any).ShortCycleWindowSeconds else nil,
					RepeatedTargetingAbuseConfig.ShortCycleWindowSeconds
				)
			)
		)
	end

	local candidates: { SuspiciousLoopRecord } = {}
	local pairRepeatCandidate = if pairKey ~= nil
		then evaluatePairRepeatTargeting(nextState, config, input, pairKey)
		else nil
	if pairRepeatCandidate ~= nil then
		table.insert(candidates, pairRepeatCandidate)
	end
	local targetLoopCandidate = evaluateTargetCustodyLoop(nextState, config, input)
	if targetLoopCandidate ~= nil then
		table.insert(candidates, targetLoopCandidate)
	end
	local transferLoopCandidate = evaluateTransferLoop(nextState, config, input)
	if transferLoopCandidate ~= nil then
		table.insert(candidates, transferLoopCandidate)
	end
	local shortCycleCandidate = if pairKey ~= nil
		then evaluateShortCustodyCycle(nextState, config, input, pairKey)
		else nil
	if shortCycleCandidate ~= nil then
		table.insert(candidates, shortCycleCandidate)
	end
	local pairRewardCapCandidate = if pairKey ~= nil
		then evaluatePairRewardCap(nextState, config, input, pairKey)
		else nil
	if pairRewardCapCandidate ~= nil then
		table.insert(candidates, pairRewardCapCandidate)
	end

	for _, candidate in ipairs(candidates) do
		if candidate ~= nil then
			local updatedState, record = appendDetection(nextState, config, candidate)
			nextState = updatedState
			if record ~= nil then
				table.insert(detections, record)
			end
		end
	end

	nextState.lastReason = "accepted"
	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		detections = detections,
	}
end

function RepeatedTargetingAbuseState.GetTargetSnapshot(
	state: State,
	targetUserId: number,
	now: number,
	config: any?
): any
	if not isPositiveInteger(targetUserId) or not isFiniteNumber(now) then
		return {
			targetUserId = targetUserId,
			eventCount = 0,
			transferCount = 0,
			suspiciousLoopCount = 0,
			lastReason = "snapshot_invalid",
		}
	end

	local windowSeconds = positiveNumber(
		if config ~= nil then (config :: any).TargetCustodyLoopWindowSeconds else nil,
		RepeatedTargetingAbuseConfig.TargetCustodyLoopWindowSeconds
	)
	local events = state.targetEventsByUserId[targetUserId] or {}
	local transferEvents = state.transferEventsByTargetUserId[targetUserId] or {}
	local suspiciousLoopCount = 0
	for _, record in ipairs(state.suspiciousLoops) do
		if record.targetUserId == targetUserId then
			suspiciousLoopCount += 1
		end
	end

	return {
		targetUserId = targetUserId,
		eventCount = countEventsInWindow(events, now, windowSeconds, nil),
		transferCount = countEventsInWindow(transferEvents, now, windowSeconds, nil),
		suspiciousLoopCount = suspiciousLoopCount,
		lastReason = state.lastReason,
	}
end

function RepeatedTargetingAbuseState.GetPairSnapshot(
	state: State,
	custodianUserId: number,
	targetUserId: number,
	now: number,
	config: any?
): any
	if not isPositiveInteger(custodianUserId) or not isPositiveInteger(targetUserId) or not isFiniteNumber(now) then
		return {
			custodianUserId = custodianUserId,
			targetUserId = targetUserId,
			captureCount = 0,
			cycleCount = 0,
			suspiciousLoopCount = 0,
			lastReason = "snapshot_invalid",
		}
	end

	local pairKey = makePairKey(custodianUserId, targetUserId)
	local windowSeconds = positiveNumber(
		if config ~= nil then (config :: any).PairRepeatWindowSeconds else nil,
		RepeatedTargetingAbuseConfig.PairRepeatWindowSeconds
	)
	local events = state.pairEventsByKey[pairKey] or {}
	local suspiciousLoopCount = 0
	for _, record in ipairs(state.suspiciousLoops) do
		if record.custodianUserId == custodianUserId and record.targetUserId == targetUserId then
			suspiciousLoopCount += 1
		end
	end

	return {
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
		captureCount = countEventsInWindow(
			events,
			now,
			windowSeconds,
			RepeatedTargetingAbuseState.EventKinds.CaptureStart
		),
		cycleCount = countEventsInWindow(events, now, windowSeconds, nil),
		suspiciousLoopCount = suspiciousLoopCount,
		lastReason = state.lastReason,
	}
end

function RepeatedTargetingAbuseState.GetRecentSuspiciousLoops(state: State, limit: number?): { SuspiciousLoopRecord }
	local output: { SuspiciousLoopRecord } = {}
	if type(limit) == "number" and limit <= 0 then
		return output
	end

	local maxCount = if type(limit) == "number" then math.max(0, math.floor(limit)) else #state.suspiciousLoops
	for index = #state.suspiciousLoops, 1, -1 do
		if #output >= maxCount then
			break
		end
		table.insert(output, cloneSuspiciousLoop(state.suspiciousLoops[index]))
	end
	return output
end

function RepeatedTargetingAbuseState.PruneExpiredCustodyBlocks(state: State, now: number): State
	if not isFiniteNumber(now) then
		return cloneState(state)
	end

	local nextState = cloneState(state)
	for key, block in pairs(nextState.activeCustodyBlocks) do
		if block.expiresAt <= now then
			nextState.activeCustodyBlocks[key] = nil
		end
	end
	return nextState
end

function RepeatedTargetingAbuseState.ResolveCustodyInteractionBlock(
	state: State,
	input: CustodyBlockInput,
	_config: any?
): any
	if
		not isPositiveInteger(input.custodianUserId)
		or not isPositiveInteger(input.targetUserId)
		or not isFiniteNumber(input.now)
	then
		return { blocked = false, reason = "input_invalid" }
	end

	local prunedState = RepeatedTargetingAbuseState.PruneExpiredCustodyBlocks(state, input.now)
	local interactionKind = if type(input.interactionKind) == "string" then input.interactionKind else "capture"
	local pairKey = string.format("pair:%d:%d", input.custodianUserId, input.targetUserId)
	local pairBlock = prunedState.activeCustodyBlocks[pairKey]
	if pairBlock ~= nil then
		return {
			blocked = true,
			reason = "repeated_targeting_custody_blocked",
			patternKind = pairBlock.patternKind,
			expiresAt = pairBlock.expiresAt,
			state = prunedState,
		}
	end

	if interactionKind == "capture" then
		local targetKey = string.format("target:%d", input.targetUserId)
		local targetBlock = prunedState.activeCustodyBlocks[targetKey]
		if targetBlock ~= nil then
			return {
				blocked = true,
				reason = "repeated_targeting_custody_blocked",
				patternKind = targetBlock.patternKind,
				expiresAt = targetBlock.expiresAt,
				state = prunedState,
			}
		end
	end

	if interactionKind == "transfer" then
		local outgoingCustodianUserId = if isPositiveInteger(input.outgoingCustodianUserId)
			then input.outgoingCustodianUserId
			else input.custodianUserId
		local incomingCustodianUserId = input.incomingCustodianUserId
		if isPositiveInteger(outgoingCustodianUserId) and isPositiveInteger(incomingCustodianUserId) then
			local outgoingId = outgoingCustodianUserId :: number
			local incomingId = incomingCustodianUserId :: number
			local transferKey = string.format("transfer:%d:%d:%d", input.targetUserId, outgoingId, incomingId)
			local transferBlock = prunedState.activeCustodyBlocks[transferKey]
			if transferBlock ~= nil then
				return {
					blocked = true,
					reason = "repeated_targeting_custody_blocked",
					patternKind = transferBlock.patternKind,
					expiresAt = transferBlock.expiresAt,
					state = prunedState,
				}
			end
		end
	end

	return {
		blocked = false,
		reason = "accepted",
		state = prunedState,
	}
end

function RepeatedTargetingAbuseState.ResolveRewardDampeningMultiplier(
	state: State,
	custodianUserId: number,
	targetUserId: number,
	now: number,
	config: any?
): any
	if not isPositiveInteger(custodianUserId) or not isPositiveInteger(targetUserId) or not isFiniteNumber(now) then
		return { multiplier = 1, reason = "input_invalid" }
	end

	local windowSeconds = positiveNumber(
		if config ~= nil then (config :: any).RewardDampeningWindowSeconds else nil,
		RepeatedTargetingAbuseConfig.RewardDampeningWindowSeconds
	)
	local multipliers = if config ~= nil and type((config :: any).RewardDampeningMultipliers) == "table"
		then (config :: any).RewardDampeningMultipliers
		else RepeatedTargetingAbuseConfig.RewardDampeningMultipliers
	local kinds = RepeatedTargetingAbuseState.PatternKinds

	local bestMultiplier = 1
	local bestPattern: string? = nil
	for _, record in ipairs(state.suspiciousLoops) do
		if now - record.at > windowSeconds then
			continue
		end

		local matchesPair = record.custodianUserId == custodianUserId and record.targetUserId == targetUserId
		local matchesTarget = record.targetUserId == targetUserId and record.patternKind == kinds.TargetCustodyLoop
		local matchesTransfer = record.patternKind == kinds.CustodyTransferLoop
			and record.targetUserId == targetUserId
			and (record.outgoingCustodianUserId == custodianUserId or record.incomingCustodianUserId == custodianUserId)
		if not matchesPair and not matchesTarget and not matchesTransfer then
			continue
		end

		local patternMultiplier = if type(multipliers) == "table" then multipliers[record.patternKind] else nil
		if type(patternMultiplier) == "number" and patternMultiplier < bestMultiplier then
			bestMultiplier = patternMultiplier
			bestPattern = record.patternKind
		end
	end

	if bestPattern ~= nil then
		return {
			multiplier = bestMultiplier,
			patternKind = bestPattern,
			reason = "abuse_reward_dampening",
		}
	end

	return {
		multiplier = 1,
		reason = "accepted",
	}
end

function RepeatedTargetingAbuseState.ClearUserHistory(state: State, userId: number): State
	if not isPositiveInteger(userId) then
		return cloneState(state)
	end

	local nextState = cloneState(state)
	for key, _ in pairs(nextState.pairEventsByKey) do
		local separatorIndex = string.find(key, "|", 1, true)
		if separatorIndex ~= nil then
			local custodianPart = string.sub(key, 1, separatorIndex - 1)
			local targetPart = string.sub(key, separatorIndex + 1)
			local custodianId = tonumber(custodianPart)
			local targetId = tonumber(targetPart)
			if custodianId == userId or targetId == userId then
				nextState.pairEventsByKey[key] = nil
			end
		end
	end
	nextState.targetEventsByUserId[userId] = nil
	nextState.transferEventsByTargetUserId[userId] = nil
	for key, block in pairs(nextState.activeCustodyBlocks) do
		if
			block.custodianUserId == userId
			or block.targetUserId == userId
			or block.outgoingCustodianUserId == userId
			or block.incomingCustodianUserId == userId
		then
			nextState.activeCustodyBlocks[key] = nil
		end
	end
	return nextState
end

do
	local function countKeys(map: { [any]: any }): number
		local count = 0
		for _, _ in pairs(map) do
			count += 1
		end
		return count
	end

	function RepeatedTargetingAbuseState.GetStateSnapshot(state: State): any
		return {
			pairKeyCount = countKeys(state.pairEventsByKey),
			targetCount = countKeys(state.targetEventsByUserId),
			suspiciousLoopCount = #state.suspiciousLoops,
			activeCustodyBlockCount = countKeys(state.activeCustodyBlocks),
			sequence = state.sequence,
			lastReason = state.lastReason,
		}
	end
end

return RepeatedTargetingAbuseState
