--!strict

local NotificationRateGuard: any = {}
local globalEnv: any = getfenv()

export type GuardDecision = {
	accepted: boolean,
	reason: string,
	action: string,
	summary: any?,
}

type Diagnostics = {
	attempts: number,
	accepted: number,
	coalesced: number,
	dropped: number,
	flushAttempts: number,
	lastTopic: string?,
	lastMessageType: string?,
	lastOperationId: string?,
	lastRealmId: string?,
	lastAnnouncementId: string?,
	lastReason: string,
	frequencyByKey: { [string]: number },
	realmStatusByRealm: { [string]: number },
}

type GuardState = {
	windowStart: number,
	count: number,
	coalesced: number,
	dropped: number,
}

local DEFAULT_WINDOW_SECONDS = 1
local DEFAULT_MAX_PUBLISHES_PER_WINDOW = 5
local DEFAULT_REALM_STATUS_MIN_INTERVAL_SECONDS = 10
local DEFAULT_MAX_TRACKED_KEYS = 64

local runtimeGuard: any = nil

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function cloneStringNumberMap(source: { [string]: number }): { [string]: number }
	return table.clone(source)
end

local function resolvePositiveNumber(value: any, fallback: number): number
	if isFiniteNumber(value) and value > 0 then
		return value
	end
	return fallback
end

local function resolveNow(nowFn: any): number
	if type(nowFn) == "function" then
		local ok, nowOrError = pcall(nowFn)
		if ok and isFiniteNumber(nowOrError) then
			return nowOrError
		end
	end
	return os.clock()
end

local function resolveMetadata(input: any): (string?, string?, string?, string?, string?)
	if type(input) ~= "table" then
		return nil, nil, nil, nil, nil
	end

	local topic = if isNonEmptyString(input.topic) then input.topic else nil
	local messageType = if isNonEmptyString(input.messageType) then input.messageType else nil
	local operationId = if isNonEmptyString(input.operationId) then input.operationId else nil
	local realmId = if isNonEmptyString(input.realmId) then input.realmId else nil
	local announcementId = if isNonEmptyString(input.announcementId) then input.announcementId else nil

	local message = input.message
	if type(message) == "table" then
		if messageType == nil and isNonEmptyString(message.messageType) then
			messageType = message.messageType
		end
		if operationId == nil and isNonEmptyString(message.operationId) then
			operationId = message.operationId
		end
		local payload = message.payload
		if type(payload) == "table" then
			if realmId == nil and isNonEmptyString(payload.realmId) then
				realmId = payload.realmId
			end
			if announcementId == nil and isNonEmptyString(payload.announcementId) then
				announcementId = payload.announcementId
			end
		end
	end

	return topic, messageType, operationId, realmId, announcementId
end

local function isRealmStatusMessage(messageType: string): boolean
	return messageType == "RealmStatusChanged" or messageType == "realm_status_changed"
end

local function isAnnouncementMessage(messageType: string): boolean
	return string.sub(string.lower(messageType), 1, 13) == "announcement_"
end

local function isCoalescibleMessage(messageType: string): boolean
	if isRealmStatusMessage(messageType) then
		return true
	end
	if isAnnouncementMessage(messageType) then
		return true
	end
	return string.find(string.lower(messageType), "status", 1, true) ~= nil
end

function NotificationRateGuard.Create(config: any?): any
	local configAny: any = config
	local nowFn = if type(configAny) == "table" then configAny.now else nil
	local windowSeconds = resolvePositiveNumber(
		if type(configAny) == "table" then configAny.windowSeconds else nil,
		DEFAULT_WINDOW_SECONDS
	)
	local maxPublishesPerWindow = math.floor(
		resolvePositiveNumber(
			if type(configAny) == "table" then configAny.maxPublishesPerWindow else nil,
			DEFAULT_MAX_PUBLISHES_PER_WINDOW
		)
	)
	local realmStatusMinIntervalSeconds = resolvePositiveNumber(
		if type(configAny) == "table" then configAny.realmStatusMinIntervalSeconds else nil,
		DEFAULT_REALM_STATUS_MIN_INTERVAL_SECONDS
	)
	local maxTrackedKeys = math.floor(
		resolvePositiveNumber(
			if type(configAny) == "table" then configAny.maxTrackedKeys else nil,
			DEFAULT_MAX_TRACKED_KEYS
		)
	)

	local statesByKey: { [string]: GuardState } = {}
	local trackedKeys: { string } = {}
	local lastRealmStatusAt: { [string]: number } = {}
	local diagnostics: Diagnostics = {
		attempts = 0,
		accepted = 0,
		coalesced = 0,
		dropped = 0,
		flushAttempts = 0,
		lastTopic = nil,
		lastMessageType = nil,
		lastOperationId = nil,
		lastRealmId = nil,
		lastAnnouncementId = nil,
		lastReason = "not_started",
		frequencyByKey = {},
		realmStatusByRealm = {},
	}

	local function ensureState(key: string, now: number): GuardState
		local state = statesByKey[key]
		if state == nil then
			if #trackedKeys >= maxTrackedKeys then
				local oldest = table.remove(trackedKeys, 1)
				if oldest ~= nil then
					statesByKey[oldest] = nil
					diagnostics.frequencyByKey[oldest] = nil
				end
			end
			state = {
				windowStart = now,
				count = 0,
				coalesced = 0,
				dropped = 0,
			}
			statesByKey[key] = state
			table.insert(trackedKeys, key)
		elseif now - state.windowStart >= windowSeconds then
			state.windowStart = now
			state.count = 0
			state.coalesced = 0
			state.dropped = 0
		end
		return state
	end

	local function record(
		accepted: boolean,
		action: string,
		reason: string,
		topic: string?,
		messageType: string?,
		operationId: string?,
		realmId: string?,
		announcementId: string?
	)
		diagnostics.attempts += 1
		diagnostics.lastTopic = topic
		diagnostics.lastMessageType = messageType
		diagnostics.lastOperationId = operationId
		diagnostics.lastRealmId = realmId
		diagnostics.lastAnnouncementId = announcementId
		diagnostics.lastReason = reason

		if accepted and action == "publish" then
			diagnostics.accepted += 1
		elseif accepted and action == "coalesce" then
			diagnostics.coalesced += 1
		else
			diagnostics.dropped += 1
		end
	end

	local guard: any = {}

	function guard.EvaluatePublish(input: any): GuardDecision
		local topic, messageType, operationId, realmId, announcementId = resolveMetadata(input)
		if not isNonEmptyString(topic) then
			record(false, "drop", "topic_invalid", nil, messageType, operationId, realmId, announcementId)
			return {
				accepted = false,
				reason = "topic_invalid",
				action = "drop",
				summary = nil,
			}
		end
		if not isNonEmptyString(messageType) then
			record(false, "drop", "message_type_invalid", topic, nil, operationId, realmId, announcementId)
			return {
				accepted = false,
				reason = "message_type_invalid",
				action = "drop",
				summary = nil,
			}
		end
		local resolvedTopic: string = topic :: any
		local resolvedMessageType: string = messageType :: any

		local now = resolveNow(nowFn)
		local key = resolvedTopic .. "|" .. resolvedMessageType
		local state = ensureState(key, now)
		state.count += 1
		diagnostics.frequencyByKey[key] = state.count

		if isRealmStatusMessage(resolvedMessageType) and realmId ~= nil then
			local resolvedRealmId: string = realmId :: any
			local lastAt = lastRealmStatusAt[resolvedRealmId]
			diagnostics.realmStatusByRealm[resolvedRealmId] = now
			if lastAt ~= nil and now - lastAt < realmStatusMinIntervalSeconds then
				state.coalesced += 1
				record(
					true,
					"coalesce",
					"coalesced",
					resolvedTopic,
					resolvedMessageType,
					operationId,
					resolvedRealmId,
					announcementId
				)
				return {
					accepted = true,
					reason = "coalesced",
					action = "coalesce",
					summary = {
						topic = resolvedTopic,
						messageType = "RealmStatusSummary",
						realmId = resolvedRealmId,
						coalescedCount = state.coalesced,
					},
				}
			end
			lastRealmStatusAt[resolvedRealmId] = now
		end

		if state.count > maxPublishesPerWindow then
			if isCoalescibleMessage(resolvedMessageType) then
				state.coalesced += 1
				record(
					true,
					"coalesce",
					"coalesced",
					resolvedTopic,
					resolvedMessageType,
					operationId,
					realmId,
					announcementId
				)
				local summaryMessageType = if isAnnouncementMessage(resolvedMessageType)
					then "announcement_summary"
					else resolvedMessageType .. "Summary"
				return {
					accepted = true,
					reason = "coalesced",
					action = "coalesce",
					summary = {
						topic = resolvedTopic,
						messageType = summaryMessageType,
						realmId = realmId,
						announcementId = announcementId,
						coalescedCount = state.coalesced,
					},
				}
			end

			state.dropped += 1
			record(
				false,
				"drop",
				"rate_limited",
				resolvedTopic,
				resolvedMessageType,
				operationId,
				realmId,
				announcementId
			)
			return {
				accepted = false,
				reason = "rate_limited",
				action = "drop",
				summary = nil,
			}
		end

		record(true, "publish", "accepted", resolvedTopic, resolvedMessageType, operationId, realmId, announcementId)
		return {
			accepted = true,
			reason = "accepted",
			action = "publish",
			summary = nil,
		}
	end

	function guard.Flush(_input: any?): GuardDecision
		diagnostics.flushAttempts += 1
		diagnostics.lastReason = "accepted"
		return {
			accepted = true,
			reason = "accepted",
			action = "flush",
			summary = nil,
		}
	end

	function guard.GetDiagnostics(): Diagnostics
		return {
			attempts = diagnostics.attempts,
			accepted = diagnostics.accepted,
			coalesced = diagnostics.coalesced,
			dropped = diagnostics.dropped,
			flushAttempts = diagnostics.flushAttempts,
			lastTopic = diagnostics.lastTopic,
			lastMessageType = diagnostics.lastMessageType,
			lastOperationId = diagnostics.lastOperationId,
			lastRealmId = diagnostics.lastRealmId,
			lastAnnouncementId = diagnostics.lastAnnouncementId,
			lastReason = diagnostics.lastReason,
			frequencyByKey = cloneStringNumberMap(diagnostics.frequencyByKey),
			realmStatusByRealm = cloneStringNumberMap(diagnostics.realmStatusByRealm),
		}
	end

	return guard
end

function NotificationRateGuard.CreateDefault(): any
	return NotificationRateGuard.Create()
end

function NotificationRateGuard.ConfigureForTests(config: any?)
	runtimeGuard = NotificationRateGuard.Create(config)
	globalEnv._NotificationRateGuard_QueryAPI = runtimeGuard
	if type(_G) == "table" then
		rawset(_G, "_NotificationRateGuard_QueryAPI", runtimeGuard)
	end
	return runtimeGuard
end

function NotificationRateGuard.ResetForTests()
	runtimeGuard = nil
	globalEnv._NotificationRateGuard_QueryAPI = nil
	if type(_G) == "table" then
		rawset(_G, "_NotificationRateGuard_QueryAPI", nil)
	end
end

function NotificationRateGuard.Start(config: any?): any
	runtimeGuard = NotificationRateGuard.Create(config)
	globalEnv._NotificationRateGuard_QueryAPI = runtimeGuard
	if type(_G) == "table" then
		rawset(_G, "_NotificationRateGuard_QueryAPI", runtimeGuard)
	end
	return runtimeGuard
end

return NotificationRateGuard
