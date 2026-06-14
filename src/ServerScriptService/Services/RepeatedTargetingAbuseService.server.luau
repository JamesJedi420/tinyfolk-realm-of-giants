--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RepeatedTargetingAbuseConfig = require(Config:WaitForChild("RepeatedTargetingAbuseConfig"))
local RepeatedTargetingAbuseState = require(GiantRealm:WaitForChild("RepeatedTargetingAbuseState"))

local globalEnv: any = getfenv()
local state = RepeatedTargetingAbuseState.NewState()

local function now(): number
	return os.clock()
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function getRuntimeEventLogQueryApi(): any?
	local queryApi = globalEnv._RuntimeEventLogService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	queryApi = globalEnv._EventLogService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._RuntimeEventLogService_QueryAPI) == "table" then
		return (_G :: any)._RuntimeEventLogService_QueryAPI
	end
	if type(_G) == "table" and type((_G :: any)._EventLogService_QueryAPI) == "table" then
		return (_G :: any)._EventLogService_QueryAPI
	end
	return nil
end

local function logSuspiciousLoop(record: any)
	local eventLogApi = getRuntimeEventLogQueryApi()
	if eventLogApi == nil then
		return
	end

	local payload = {
		category = RepeatedTargetingAbuseConfig.EventLogCategory,
		message = string.format("Suspicious custody loop detected: %s", tostring(record.patternKind)),
		severity = "warn",
		timestamp = record.at,
		metadata = {
			patternKind = record.patternKind,
			targetUserId = record.targetUserId,
			custodianUserId = record.custodianUserId,
			outgoingCustodianUserId = record.outgoingCustodianUserId,
			incomingCustodianUserId = record.incomingCustodianUserId,
			eventCount = record.eventCount,
			windowSeconds = record.windowSeconds,
			detectionKey = record.detectionKey,
			operationId = record.operationId,
			sequence = record.sequence,
		},
	}

	if type(eventLogApi.RecordEventFromPayload) == "function" then
		pcall(eventLogApi.RecordEventFromPayload, payload)
		return
	end
	if type(eventLogApi.RecordEvent) == "function" then
		pcall(
			eventLogApi.RecordEvent,
			payload.category,
			payload.message,
			payload.severity,
			payload.timestamp,
			payload.metadata
		)
	end
end

local function projectDetectionAttributes(record: any)
	local attrs = RepeatedTargetingAbuseConfig.StateAttributes
	local players = {
		getPlayerByUserId(record.targetUserId),
		if type(record.custodianUserId) == "number" then getPlayerByUserId(record.custodianUserId) else nil,
		if type(record.outgoingCustodianUserId) == "number"
			then getPlayerByUserId(record.outgoingCustodianUserId)
			else nil,
		if type(record.incomingCustodianUserId) == "number"
			then getPlayerByUserId(record.incomingCustodianUserId)
			else nil,
	}

	for _, player in ipairs(players) do
		if player ~= nil then
			player:SetAttribute(attrs.AbuseFlag, true)
			player:SetAttribute(attrs.AbusePattern, record.patternKind)
			player:SetAttribute(attrs.AbuseEventCount, record.eventCount)
			player:SetAttribute(attrs.AbuseLastAt, record.at)
		end
	end
end

local function recordEvent(input: any): any
	local resolvedNow = if type(input) == "table" and type(input.now) == "number" then input.now else now()
	local transition = RepeatedTargetingAbuseState.RecordEvent(
		state,
		if type(input) == "table"
			then input
			else {
				now = resolvedNow,
				kind = "",
				targetUserId = 0,
			},
		RepeatedTargetingAbuseConfig
	)
	state = transition.state

	for _, detection in ipairs(transition.detections) do
		logSuspiciousLoop(detection)
		projectDetectionAttributes(detection)
	end

	return {
		accepted = transition.accepted,
		reason = transition.reason,
		detections = transition.detections,
	}
end

globalEnv._RepeatedTargetingAbuseService_QueryAPI = {
	RecordCaptureStart = function(
		custodianUserId: number,
		targetUserId: number,
		at: number?,
		operationId: string?
	): any
		return recordEvent({
			now = if type(at) == "number" then at else now(),
			kind = RepeatedTargetingAbuseState.EventKinds.CaptureStart,
			custodianUserId = custodianUserId,
			targetUserId = targetUserId,
			operationId = operationId,
		})
	end,
	RecordCustodyEnd = function(
		custodianUserId: number,
		targetUserId: number,
		endReason: string,
		at: number?,
		operationId: string?
	): any
		return recordEvent({
			now = if type(at) == "number" then at else now(),
			kind = RepeatedTargetingAbuseState.EventKinds.CustodyEnd,
			custodianUserId = custodianUserId,
			targetUserId = targetUserId,
			endReason = endReason,
			operationId = operationId,
		})
	end,
	RecordCustodyTransfer = function(
		outgoingCustodianUserId: number,
		incomingCustodianUserId: number,
		targetUserId: number,
		at: number?,
		operationId: string?
	): any
		return recordEvent({
			now = if type(at) == "number" then at else now(),
			kind = RepeatedTargetingAbuseState.EventKinds.CustodyTransfer,
			targetUserId = targetUserId,
			outgoingCustodianUserId = outgoingCustodianUserId,
			incomingCustodianUserId = incomingCustodianUserId,
			operationId = operationId,
		})
	end,
	RecordPairRewardCapReached = function(
		custodianUserId: number,
		targetUserId: number,
		pairRewardCount: number,
		at: number?,
		operationId: string?
	): any
		return recordEvent({
			now = if type(at) == "number" then at else now(),
			kind = RepeatedTargetingAbuseState.EventKinds.PairRewardCap,
			custodianUserId = custodianUserId,
			targetUserId = targetUserId,
			pairRewardCount = pairRewardCount,
			operationId = operationId,
		})
	end,
	GetTargetSnapshot = function(targetUserId: number, at: number?): any
		return RepeatedTargetingAbuseState.GetTargetSnapshot(
			state,
			targetUserId,
			if type(at) == "number" then at else now(),
			RepeatedTargetingAbuseConfig
		)
	end,
	GetPairSnapshot = function(custodianUserId: number, targetUserId: number, at: number?): any
		return RepeatedTargetingAbuseState.GetPairSnapshot(
			state,
			custodianUserId,
			targetUserId,
			if type(at) == "number" then at else now(),
			RepeatedTargetingAbuseConfig
		)
	end,
	GetRecentSuspiciousLoops = function(limit: number?): any
		return RepeatedTargetingAbuseState.GetRecentSuspiciousLoops(state, limit)
	end,
	GetStateSnapshot = function(): any
		return RepeatedTargetingAbuseState.GetStateSnapshot(state)
	end,
	ResetForTests = function()
		state = RepeatedTargetingAbuseState.NewState()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RepeatedTargetingAbuseService_QueryAPI", globalEnv._RepeatedTargetingAbuseService_QueryAPI)
end

Players.PlayerRemoving:Connect(function(player: Player)
	state = RepeatedTargetingAbuseState.ClearUserHistory(state, player.UserId)
end)

return globalEnv._RepeatedTargetingAbuseService_QueryAPI
