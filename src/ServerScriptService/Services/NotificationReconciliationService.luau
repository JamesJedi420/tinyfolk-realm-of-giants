--!strict

local NotificationMessageSchema = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("NotificationMessageSchema"))
	else (require :: any)("./NotificationMessageSchema")
local RealmMetadataRegistry = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("RealmAssembly")
			:WaitForChild("RealmMetadataRegistry")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/RealmAssembly/RealmMetadataRegistry")

local NotificationReconciliationService: any = {}
local globalEnv: any = getfenv()

local DEFAULT_RECONCILE_INTERVAL_SECONDS = 30
local DEFAULT_RESCUE_QUEUE_LIMIT = 50

type ChannelCounters = {
	attempts: number,
	succeeded: number,
	failed: number,
}

type Diagnostics = {
	totalAttempts: number,
	totalSucceeded: number,
	totalFailed: number,
	admissionQueue: ChannelCounters,
	rescueQueue: ChannelCounters,
	realmStatus: ChannelCounters,
	systemAnnouncement: ChannelCounters,
	returnRecovery: ChannelCounters,
	loopScheduleAttempts: number,
	loopScheduleSucceeded: number,
	loopScheduleFailed: number,
	loopTickAttempts: number,
	loopTickSucceeded: number,
	loopTickFailed: number,
	loopLastScheduledAt: number?,
	loopLastTickAt: number?,
	lastChannel: string,
	lastMessageType: string?,
	lastOperationId: string?,
	lastReason: string,
	lastReconciledAt: number?,
}

local runtimeConfig: any = nil
local runtimeScheduler: any = nil
local runtimeLoopToken: any = nil
local scheduleNextTick: (() -> ())? = nil

local diagnostics: Diagnostics

local function newChannelCounters(): ChannelCounters
	return {
		attempts = 0,
		succeeded = 0,
		failed = 0,
	}
end

local function resetDiagnostics(reason: string)
	diagnostics = {
		totalAttempts = 0,
		totalSucceeded = 0,
		totalFailed = 0,
		admissionQueue = newChannelCounters(),
		rescueQueue = newChannelCounters(),
		realmStatus = newChannelCounters(),
		systemAnnouncement = newChannelCounters(),
		returnRecovery = newChannelCounters(),
		loopScheduleAttempts = 0,
		loopScheduleSucceeded = 0,
		loopScheduleFailed = 0,
		loopTickAttempts = 0,
		loopTickSucceeded = 0,
		loopTickFailed = 0,
		loopLastScheduledAt = nil,
		loopLastTickAt = nil,
		lastChannel = "none",
		lastMessageType = nil,
		lastOperationId = nil,
		lastReason = reason,
		lastReconciledAt = nil,
	}
end

resetDiagnostics("not_started")

local function nowSeconds(): number
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.now) == "function" then
		local nowValue = configAny.now()
		if type(nowValue) == "number" and nowValue == nowValue and nowValue ~= math.huge and nowValue ~= -math.huge then
			return nowValue
		end
	end
	return os.clock()
end

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local clone: any = {}
	for key, child in pairs(value) do
		clone[key] = cloneTable(child)
	end
	return clone
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

local function resolveDependency(configKey: string, globalName: string): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and configAny[configKey] ~= nil then
		return configAny[configKey]
	end
	return getGlobalTable(globalName)
end

local function channelCounters(channel: string): ChannelCounters
	local diagnosticsAny: any = diagnostics
	return diagnosticsAny[channel] :: ChannelCounters
end

local function recordChannel(
	channel: string,
	accepted: boolean,
	reason: string,
	messageType: string?,
	operationId: string?,
	reconciledAt: number
)
	local counters = channelCounters(channel)
	counters.attempts += 1
	diagnostics.totalAttempts += 1
	if accepted then
		counters.succeeded += 1
		diagnostics.totalSucceeded += 1
	else
		counters.failed += 1
		diagnostics.totalFailed += 1
	end
	diagnostics.lastChannel = channel
	diagnostics.lastMessageType = messageType
	diagnostics.lastOperationId = operationId
	diagnostics.lastReason = reason
	diagnostics.lastReconciledAt = reconciledAt
end

local function makeResult(accepted: boolean, reason: string, channel: string, snapshot: any?): any
	local result: any = {
		accepted = accepted,
		reason = reason,
		channel = channel,
	}
	if accepted then
		result.snapshot = snapshot
	end
	return result
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0 and value == value
end

local function resolveAt(input: any): number
	if type(input) == "table" and type(input.at) == "number" and input.at == input.at then
		return input.at
	end
	return nowSeconds()
end

local function fanOutRaidBoardNotify(at: number)
	local raidBoardApi = resolveDependency("raidBoardHubApi", "_RaidBoardHubService_QueryAPI")
	if type(raidBoardApi) ~= "table" or type((raidBoardApi :: any).BroadcastNotify) ~= "function" then
		return
	end

	pcall(function()
		(raidBoardApi :: any).BroadcastNotify({
			reason = "realm_status_reconciled",
			at = at,
		})
	end)
end

local function resolveScheduler(config: any): any?
	if type(config) == "table" and type(config.reconciliationScheduler) == "table" then
		return config.reconciliationScheduler
	end
	if task ~= nil and type(task.delay) == "function" then
		return {
			schedule = function(delaySeconds: number, callback: () -> ())
				return task.delay(delaySeconds, callback)
			end,
			cancel = function(_token: any) end,
		}
	end
	return nil
end

local function stopLoop()
	local scheduler = runtimeScheduler
	local token = runtimeLoopToken
	runtimeLoopToken = nil
	if scheduler ~= nil and token ~= nil and type((scheduler :: any).cancel) == "function" then
		pcall(function()
			(scheduler :: any).cancel(token)
		end)
	end
end

local function recordLoopSchedule(at: number, accepted: boolean, reason: string)
	diagnostics.loopScheduleAttempts += 1
	diagnostics.loopLastScheduledAt = at
	if accepted then
		diagnostics.loopScheduleSucceeded += 1
	else
		diagnostics.loopScheduleFailed += 1
		diagnostics.lastReason = reason
	end
end

local function recordLoopTick(at: number, accepted: boolean, reason: string)
	diagnostics.loopTickAttempts += 1
	diagnostics.loopLastTickAt = at
	diagnostics.lastReason = reason
	if accepted then
		diagnostics.loopTickSucceeded += 1
	else
		diagnostics.loopTickFailed += 1
	end
end

local function resolveIntervalSeconds(config: any): number
	if type(config) == "table" and type(config.reconciliationIntervalSeconds) == "number" then
		local interval = config.reconciliationIntervalSeconds
		if interval > 0 and interval == interval and interval ~= math.huge and interval ~= -math.huge then
			return interval
		end
	end
	return DEFAULT_RECONCILE_INTERVAL_SECONDS
end

local function messageChannel(messageType: string): string?
	if string.sub(messageType, 1, 10) == "admission_" then
		return "admissionQueue"
	end
	if string.sub(messageType, 1, 7) == "rescue_" then
		return "rescueQueue"
	end
	if messageType == "RealmStatusChanged" or messageType == "realm_status_changed" then
		return "realmStatus"
	end
	if string.sub(messageType, 1, 6) == "realm_" then
		return "realmStatus"
	end
	if string.sub(messageType, 1, 13) == "announcement_" then
		return "systemAnnouncement"
	end
	if string.sub(messageType, 1, 7) == "return_" then
		return "returnRecovery"
	end
	return nil
end

function NotificationReconciliationService.ReconcileAdmissionQueue(input: any?): any
	local at = resolveAt(input)
	local api = resolveDependency("admissionQueueApi", "_RealmAdmissionQueue_QueryAPI")
	if type(api) ~= "table" or type((api :: any).GetProcessingDiagnostics) ~= "function" then
		recordChannel("admissionQueue", false, "admission_queue_api_unavailable", nil, nil, at)
		return makeResult(false, "admission_queue_api_unavailable", "admissionQueue", nil)
	end

	local ok, snapshot = pcall(function()
		return (api :: any).GetProcessingDiagnostics()
	end)
	if not ok or type(snapshot) ~= "table" then
		recordChannel("admissionQueue", false, "admission_queue_reconcile_failed", nil, nil, at)
		return makeResult(false, "admission_queue_reconcile_failed", "admissionQueue", nil)
	end

	recordChannel("admissionQueue", true, "accepted", nil, nil, at)
	return makeResult(true, "accepted", "admissionQueue", cloneTable(snapshot))
end

function NotificationReconciliationService.ReconcileRescueQueue(input: any?): any
	local at = resolveAt(input)
	local inputAny: any = input
	local limit = if type(inputAny) == "table" and isPositiveInteger(inputAny.limit)
		then inputAny.limit
		else DEFAULT_RESCUE_QUEUE_LIMIT
	local api = resolveDependency("rescueHubApi", "_RescueContractHubSurface_QueryAPI")
	if type(api) ~= "table" or type((api :: any).GetPendingRescueQueueEntries) ~= "function" then
		recordChannel("rescueQueue", false, "rescue_queue_api_unavailable", nil, nil, at)
		return makeResult(false, "rescue_queue_api_unavailable", "rescueQueue", nil)
	end

	local ok, entries = pcall(function()
		return (api :: any).GetPendingRescueQueueEntries(limit, at)
	end)
	if not ok or type(entries) ~= "table" then
		recordChannel("rescueQueue", false, "rescue_queue_reconcile_failed", nil, nil, at)
		return makeResult(false, "rescue_queue_reconcile_failed", "rescueQueue", nil)
	end

	recordChannel("rescueQueue", true, "accepted", nil, nil, at)
	return makeResult(true, "accepted", "rescueQueue", {
		limit = limit,
		entries = cloneTable(entries),
	})
end

function NotificationReconciliationService.ReconcileRealmStatus(input: any?): any
	local at = resolveAt(input)
	local inputAny: any = input
	local limit = if type(inputAny) == "table" and isPositiveInteger(inputAny.limit)
		then inputAny.limit
		else DEFAULT_RESCUE_QUEUE_LIMIT

	local liveRegistryApi = resolveDependency("liveRealmRegistryHubApi", "_LiveRealmRegistryHubSurface_QueryAPI")
	if type(liveRegistryApi) == "table" and type((liveRegistryApi :: any).ListLiveRealmAvailability) == "function" then
		local ok, entries = pcall(function()
			return (liveRegistryApi :: any).ListLiveRealmAvailability(limit, at)
		end)
		if ok and type(entries) == "table" then
			recordChannel("realmStatus", true, "accepted", nil, nil, at)
			fanOutRaidBoardNotify(at)
			return makeResult(true, "accepted", "realmStatus", {
				limit = limit,
				realms = cloneTable(entries),
			})
		end
	end

	local configAny: any = runtimeConfig
	local registry = if type(configAny) == "table" then configAny.realmMetadataRegistry else nil
	local ok, snapshot = pcall(function()
		return RealmMetadataRegistry.BuildRealmMetadataSnapshot(registry)
	end)
	if not ok or type(snapshot) ~= "table" then
		recordChannel("realmStatus", false, "realm_status_reconcile_failed", nil, nil, at)
		return makeResult(false, "realm_status_reconcile_failed", "realmStatus", nil)
	end

	recordChannel("realmStatus", true, "accepted", nil, nil, at)
	fanOutRaidBoardNotify(at)
	return makeResult(true, "accepted", "realmStatus", {
		realms = cloneTable(snapshot),
	})
end

function NotificationReconciliationService.ReconcileSystemAnnouncement(input: any?): any
	local at = resolveAt(input)
	local api = resolveDependency("systemAnnouncementApi", "_SystemAnnouncementService_QueryAPI")
	if type(api) ~= "table" or type((api :: any).GetActiveAnnouncement) ~= "function" then
		recordChannel("systemAnnouncement", false, "announcement_api_unavailable", nil, nil, at)
		return makeResult(false, "announcement_api_unavailable", "systemAnnouncement", nil)
	end

	local ok, snapshot = pcall(function()
		return (api :: any).GetActiveAnnouncement({ at = at })
	end)
	if not ok or type(snapshot) ~= "table" then
		recordChannel("systemAnnouncement", false, "announcement_reconcile_failed", nil, nil, at)
		return makeResult(false, "announcement_reconcile_failed", "systemAnnouncement", nil)
	end

	recordChannel("systemAnnouncement", true, "accepted", nil, nil, at)
	return makeResult(true, "accepted", "systemAnnouncement", cloneTable(snapshot))
end

function NotificationReconciliationService.ReconcileReturnRecovery(input: any): any
	local at = resolveAt(input)
	if type(input) ~= "table" or not isPositiveInteger(input.userId) then
		recordChannel("returnRecovery", false, "user_id_invalid", nil, nil, at)
		return makeResult(false, "user_id_invalid", "returnRecovery", nil)
	end

	local api = resolveDependency("handoffApi", "_ProfileTeleportHandoffService_QueryAPI")
	if type(api) ~= "table" or type((api :: any).CanSpawnGameplayForUserId) ~= "function" then
		recordChannel("returnRecovery", false, "return_recovery_api_unavailable", nil, nil, at)
		return makeResult(false, "return_recovery_api_unavailable", "returnRecovery", nil)
	end

	local ok, canSpawn = pcall(function()
		return (api :: any).CanSpawnGameplayForUserId(input.userId)
	end)
	if not ok or type(canSpawn) ~= "boolean" then
		recordChannel("returnRecovery", false, "return_recovery_reconcile_failed", nil, nil, at)
		return makeResult(false, "return_recovery_reconcile_failed", "returnRecovery", nil)
	end

	recordChannel("returnRecovery", true, "accepted", nil, nil, at)
	return makeResult(true, "accepted", "returnRecovery", {
		userId = input.userId,
		canSpawnGameplay = canSpawn,
	})
end

function NotificationReconciliationService.ReconcileAll(input: any?): any
	local inputAny: any = input
	local at = resolveAt(input)
	local results = {
		NotificationReconciliationService.ReconcileAdmissionQueue({ at = at }),
		NotificationReconciliationService.ReconcileRescueQueue({
			at = at,
			limit = if type(inputAny) == "table" then inputAny.rescueQueueLimit else nil,
		}),
		NotificationReconciliationService.ReconcileRealmStatus({ at = at }),
		NotificationReconciliationService.ReconcileSystemAnnouncement({ at = at }),
	}

	local returnRecoveryInput = if type(inputAny) == "table" then inputAny.returnRecovery else nil
	if type(returnRecoveryInput) == "table" then
		local mergedReturnInput = cloneTable(returnRecoveryInput)
		mergedReturnInput.at = at
		table.insert(results, NotificationReconciliationService.ReconcileReturnRecovery(mergedReturnInput))
	end

	local accepted = true
	for _, result in ipairs(results) do
		if type(result) ~= "table" or result.accepted ~= true then
			accepted = false
			break
		end
	end

	return {
		accepted = accepted,
		reason = if accepted then "accepted" else "reconcile_partial_failure",
		channel = "all",
		snapshot = {
			results = results,
		},
	}
end

function NotificationReconciliationService.HandleNotification(envelope: any): any
	local validation = NotificationMessageSchema.ValidateEnvelope(envelope)
	if validation.accepted ~= true then
		local at = nowSeconds()
		diagnostics.lastChannel = "notification"
		diagnostics.lastMessageType = if type(envelope) == "table" then envelope.messageType else nil
		diagnostics.lastOperationId = if type(envelope) == "table" then envelope.operationId else nil
		diagnostics.lastReason = if type(validation.reason) == "string" then validation.reason else "envelope_invalid"
		diagnostics.lastReconciledAt = at
		return {
			accepted = false,
			reason = diagnostics.lastReason,
			channel = "notification",
		}
	end

	local messageType = envelope.messageType
	local operationId = envelope.operationId
	local channel = messageChannel(messageType)
	if channel == nil then
		local at = nowSeconds()
		diagnostics.lastChannel = "notification"
		diagnostics.lastMessageType = messageType
		diagnostics.lastOperationId = operationId
		diagnostics.lastReason = "message_type_unhandled"
		diagnostics.lastReconciledAt = at
		return {
			accepted = false,
			reason = "message_type_unhandled",
			channel = "notification",
		}
	end

	local result
	if channel == "admissionQueue" then
		result = NotificationReconciliationService.ReconcileAdmissionQueue({ at = envelope.sentAt })
	elseif channel == "rescueQueue" then
		result = NotificationReconciliationService.ReconcileRescueQueue({ at = envelope.sentAt })
	elseif channel == "realmStatus" then
		result = NotificationReconciliationService.ReconcileRealmStatus({ at = envelope.sentAt })
	elseif channel == "systemAnnouncement" then
		result = NotificationReconciliationService.ReconcileSystemAnnouncement({ at = envelope.sentAt })
	else
		local userId = if type(envelope.payload) == "table" then envelope.payload.userId else nil
		result = NotificationReconciliationService.ReconcileReturnRecovery({
			at = envelope.sentAt,
			userId = userId,
		})
	end

	diagnostics.lastMessageType = messageType
	diagnostics.lastOperationId = operationId
	return result
end

function NotificationReconciliationService.GetDiagnostics(): any
	return cloneTable(diagnostics)
end

function NotificationReconciliationService.Start(config: any?): any
	stopLoop()
	runtimeConfig = if type(config) == "table" then config else {}
	resetDiagnostics("started")

	local configAny: any = runtimeConfig
	if configAny.enableReconciliationLoop == true then
		runtimeScheduler = resolveScheduler(runtimeConfig)
		local intervalSeconds = resolveIntervalSeconds(runtimeConfig)

		scheduleNextTick = function()
			local scheduler = runtimeScheduler
			if scheduler == nil or type((scheduler :: any).schedule) ~= "function" then
				recordLoopSchedule(nowSeconds(), false, "reconciliation_scheduler_unavailable")
				return
			end

			local scheduledAt = nowSeconds()
			local scheduleOk, token = pcall(function()
				return (scheduler :: any).schedule(intervalSeconds, function()
					runtimeLoopToken = nil
					local tickAt = nowSeconds()
					local reconcileOk, reconcileResult = pcall(function()
						return NotificationReconciliationService.ReconcileAll()
					end)
					if not reconcileOk then
						recordLoopTick(tickAt, false, "reconciliation_tick_failed")
					elseif type(reconcileResult) ~= "table" then
						recordLoopTick(tickAt, false, "reconciliation_tick_result_invalid")
					elseif reconcileResult.accepted == true then
						recordLoopTick(tickAt, true, "accepted")
					else
						local reason = if type(reconcileResult.reason) == "string"
								and reconcileResult.reason ~= ""
							then reconcileResult.reason
							else "reconciliation_tick_rejected"
						recordLoopTick(tickAt, false, reason)
					end

					if scheduleNextTick ~= nil then
						scheduleNextTick()
					end
				end)
			end)

			if not scheduleOk then
				recordLoopSchedule(scheduledAt, false, "reconciliation_schedule_failed")
				return
			end
			if token == nil then
				recordLoopSchedule(scheduledAt, false, "reconciliation_schedule_token_invalid")
				return
			end
			runtimeLoopToken = token
			recordLoopSchedule(scheduledAt, true, "accepted")
		end

		local schedulerStart = scheduleNextTick
		if schedulerStart ~= nil then
			schedulerStart()
		end
	end

	return {
		ok = true,
		reason = nil,
	}
end

function NotificationReconciliationService.ConfigureForTests(config: any): any
	return NotificationReconciliationService.Start(config)
end

function NotificationReconciliationService.ResetForTests()
	stopLoop()
	runtimeConfig = nil
	runtimeScheduler = nil
	scheduleNextTick = nil
	resetDiagnostics("reset")
end

NotificationReconciliationService.Start({})

globalEnv._NotificationReconciliation_QueryAPI = {
	ReconcileAll = function(input: any?): any
		return NotificationReconciliationService.ReconcileAll(input)
	end,
	ReconcileAdmissionQueue = function(input: any?): any
		return NotificationReconciliationService.ReconcileAdmissionQueue(input)
	end,
	ReconcileRescueQueue = function(input: any?): any
		return NotificationReconciliationService.ReconcileRescueQueue(input)
	end,
	ReconcileRealmStatus = function(input: any?): any
		return NotificationReconciliationService.ReconcileRealmStatus(input)
	end,
	ReconcileSystemAnnouncement = function(input: any?): any
		return NotificationReconciliationService.ReconcileSystemAnnouncement(input)
	end,
	ReconcileReturnRecovery = function(input: any): any
		return NotificationReconciliationService.ReconcileReturnRecovery(input)
	end,
	HandleNotification = function(envelope: any): any
		return NotificationReconciliationService.HandleNotification(envelope)
	end,
	GetDiagnostics = function(): any
		return NotificationReconciliationService.GetDiagnostics()
	end,
	ConfigureForTests = function(config: any): any
		return NotificationReconciliationService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		NotificationReconciliationService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_NotificationReconciliation_QueryAPI", globalEnv._NotificationReconciliation_QueryAPI)
end

return NotificationReconciliationService
