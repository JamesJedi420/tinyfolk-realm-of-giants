--!strict

local PartyMatchmakingQueueConfig = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Config")
			:WaitForChild("PartyMatchmakingQueueConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/PartyMatchmakingQueueConfig")

local PartyMatchmakingQueueState = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PartyMatchmakingQueueState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PartyMatchmakingQueueState")

local LiveRealmHubRouting = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("LiveRealmHubRouting")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")

local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local MemoryStoreAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreAdapter"))
	else (require :: any)("./MemoryStoreAdapter")

local PartyMatchmakingQueueStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PartyMatchmakingQueueStore"))
	else (require :: any)("./PartyMatchmakingQueueStore")

local PartyMatchmakingQueueProcessor = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PartyMatchmakingQueueProcessor"))
	else (require :: any)("./PartyMatchmakingQueueProcessor")

local QueueProcessingIdempotencyStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("QueueProcessingIdempotencyStore"))
	else (require :: any)("./QueueProcessingIdempotencyStore")

local QueueNotificationFanout: any = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("QueueNotificationFanout"))
	else (require :: any)("./QueueNotificationFanout")

local PartyMatchmakingQueueService: any = {}
local globalEnv: any = getfenv()

type ProcessScheduler = {
	schedule: (number, () -> ()) -> any,
	cancel: ((any) -> ())?,
}

export type EnqueueResult = {
	accepted: boolean,
	reason: string,
	snapshot: any?,
}

export type ReadBatchResult = {
	accepted: boolean,
	reason: string,
	items: { any },
}

export type ProcessResult = {
	accepted: boolean,
	reason: string,
	outcome: any?,
}

type ProcessingDiagnostics = {
	totalBatches: number,
	totalProcessed: number,
	totalMatched: number,
	totalExpired: number,
	totalFailed: number,
	totalRetryDeferred: number,
	totalDuplicatesSkipped: number,
	loopScheduleAttempts: number,
	loopScheduleSucceeded: number,
	loopScheduleFailed: number,
	loopTickAttempts: number,
	loopTickSucceeded: number,
	loopTickFailed: number,
	loopLastScheduledAt: number?,
	loopLastTickAt: number?,
	loopLastErrorReason: string,
	lastOutcome: any?,
	lastReason: string,
	lastProcessedAt: number?,
}

local started = false
local runtimeQueueStore: any = nil
local runtimeProcessor: any = nil
local runtimeProcessScheduler: ProcessScheduler? = nil
local runtimeProcessToken: any = nil
local runtimeProcessBatchSize = PartyMatchmakingQueueConfig.ProcessBatchSize
local runtimeProcessIntervalSeconds = PartyMatchmakingQueueConfig.ProcessIntervalSeconds
local runtimeQueueNotificationFanout: any = nil
local runtimeOutcomesByOperationId: { [string]: any } = {}
local runtimeActiveOperationIdByPartyId: { [string]: string } = {}
local runtimeProcessingDiagnostics: ProcessingDiagnostics = {
	totalBatches = 0,
	totalProcessed = 0,
	totalMatched = 0,
	totalExpired = 0,
	totalFailed = 0,
	totalRetryDeferred = 0,
	totalDuplicatesSkipped = 0,
	loopScheduleAttempts = 0,
	loopScheduleSucceeded = 0,
	loopScheduleFailed = 0,
	loopTickAttempts = 0,
	loopTickSucceeded = 0,
	loopTickFailed = 0,
	loopLastScheduledAt = nil,
	loopLastTickAt = nil,
	loopLastErrorReason = "not_started",
	lastOutcome = nil,
	lastReason = "not_started",
	lastProcessedAt = nil,
}

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" or value % 1 ~= 0 or value <= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
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

local function defaultProcessSchedule(delaySeconds: number, callback: () -> ()): any
	return task.delay(delaySeconds, callback)
end

local function defaultProcessCancel(token: any)
	if token == nil then
		return
	end
	if type(task.cancel) == "function" then
		task.cancel(token)
	end
end

local function nowSeconds(): number
	return os.clock()
end

local function cloneTable(source: any): any
	if type(source) ~= "table" then
		return nil
	end
	local cloned = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			cloned[key] = cloneTable(value)
		else
			cloned[key] = value
		end
	end
	return cloned
end

local function resetProcessingDiagnostics(reason: string)
	runtimeProcessingDiagnostics = {
		totalBatches = 0,
		totalProcessed = 0,
		totalMatched = 0,
		totalExpired = 0,
		totalFailed = 0,
		totalRetryDeferred = 0,
		totalDuplicatesSkipped = 0,
		loopScheduleAttempts = 0,
		loopScheduleSucceeded = 0,
		loopScheduleFailed = 0,
		loopTickAttempts = 0,
		loopTickSucceeded = 0,
		loopTickFailed = 0,
		loopLastScheduledAt = nil,
		loopLastTickAt = nil,
		loopLastErrorReason = reason,
		lastOutcome = nil,
		lastReason = reason,
		lastProcessedAt = nil,
	}
end

local function updateProcessingDiagnostics(outcome: any, nowAt: number, reason: string)
	if type(outcome) == "table" then
		local outcomeAny: any = outcome
		runtimeProcessingDiagnostics.totalBatches += 1
		runtimeProcessingDiagnostics.totalProcessed += if type(outcomeAny.processed) == "number"
			then outcomeAny.processed
			else 0
		runtimeProcessingDiagnostics.totalMatched += if type(outcomeAny.matched) == "number"
			then outcomeAny.matched
			else 0
		runtimeProcessingDiagnostics.totalExpired += if type(outcomeAny.expired) == "number"
			then outcomeAny.expired
			else 0
		runtimeProcessingDiagnostics.totalFailed += if type(outcomeAny.failed) == "number" then outcomeAny.failed else 0
		runtimeProcessingDiagnostics.totalRetryDeferred += if type(outcomeAny.retryDeferred) == "number"
			then outcomeAny.retryDeferred
			else 0
		runtimeProcessingDiagnostics.totalDuplicatesSkipped += if type(outcomeAny.duplicatesSkipped) == "number"
			then outcomeAny.duplicatesSkipped
			else 0
		runtimeProcessingDiagnostics.lastOutcome = cloneTable(outcome)
	else
		runtimeProcessingDiagnostics.lastOutcome = nil
	end
	runtimeProcessingDiagnostics.lastReason = reason
	runtimeProcessingDiagnostics.lastProcessedAt = nowAt
end

local function recordOutcome(entry: any)
	if type(entry) ~= "table" or not isNonEmptyString(entry.operationId) then
		return
	end
	local snapshot = PartyMatchmakingQueueState.BuildClientSnapshot(entry)
	if snapshot == nil then
		return
	end
	runtimeOutcomesByOperationId[entry.operationId] = snapshot
	if isNonEmptyString(entry.partyId) and entry.status ~= "pending" then
		runtimeActiveOperationIdByPartyId[entry.partyId] = nil
	end
end

local function stopProcessingLoop()
	local scheduler = runtimeProcessScheduler
	local schedulerAny: any = scheduler
	if schedulerAny ~= nil and type(schedulerAny.cancel) == "function" and runtimeProcessToken ~= nil then
		pcall(schedulerAny.cancel, runtimeProcessToken)
	end
	runtimeProcessToken = nil
	runtimeProcessScheduler = nil
end

local scheduleNextTick: any = nil

local function resolveCodec(config: any): any?
	local configAny: any = config
	local requestedCodec = if type(configAny) == "table" then rawget(configAny, "codec") else nil
	if requestedCodec ~= nil then
		return requestedCodec
	end

	if game == nil or type(game.GetService) ~= "function" then
		return nil
	end

	local ok, httpService = pcall(function()
		return game:GetService("HttpService")
	end)
	if not ok or type(httpService) ~= "table" then
		return nil
	end
	if type(httpService.JSONEncode) ~= "function" or type(httpService.JSONDecode) ~= "function" then
		return nil
	end

	return {
		Encode = function(value: any): string
			return httpService:JSONEncode(value)
		end,
		Decode = function(encoded: string): any
			return httpService:JSONDecode(encoded)
		end,
	}
end

local function resolveListLiveRealmAvailability(config: any): any?
	local configAny: any = config
	if type(configAny) == "table" and type(configAny.listLiveRealmAvailability) == "function" then
		return configAny.listLiveRealmAvailability
	end

	local hubApi = getGlobalTable("_LiveRealmRegistryHubSurface_QueryAPI")
	if type(hubApi) == "table" and type(hubApi.ListLiveRealmAvailability) == "function" then
		return function(limit: number?, at: number?)
			return hubApi.ListLiveRealmAvailability(limit, at)
		end
	end

	return nil
end

local function buildRuntime(config: any)
	stopProcessingLoop()
	resetProcessingDiagnostics("started")

	local configAny: any = config
	local adapter = if type(config) == "table" then config.adapter else nil
	if adapter == nil then
		adapter = getGlobalTable("_MemoryStoreAdapter_QueryAPI")
	end
	if adapter == nil then
		adapter = MemoryStoreAdapter.CreateDefault(nil)
	end

	local queueState = if type(config) == "table" and config.queueState ~= nil
		then config.queueState
		else PartyMatchmakingQueueState
	local structurePolicy = if type(config) == "table" and config.structurePolicy ~= nil
		then config.structurePolicy
		else MemoryStoreStructurePolicy
	local codec = resolveCodec(config)
	local nowFn = if type(config) == "table" and type(config.now) == "function" then config.now else nil
	local idempotencyStore = if type(config) == "table" then config.idempotencyStore else nil

	runtimeQueueStore = PartyMatchmakingQueueStore.Create({
		adapter = adapter,
		codec = codec,
		queueState = queueState,
		structurePolicy = structurePolicy,
	})

	if idempotencyStore == nil then
		idempotencyStore = QueueProcessingIdempotencyStore.Create({
			adapter = adapter,
			structurePolicy = structurePolicy,
			now = nowFn,
		})
	end

	local admissionApi = if type(config) == "table" then config.admissionApi else nil
	if admissionApi == nil then
		admissionApi = getGlobalTable("_PartyMatchmakingAdmissionService_QueryAPI")
	end

	local tinyfolkPartyApi = if type(config) == "table" then config.tinyfolkPartyApi else nil
	if tinyfolkPartyApi == nil then
		tinyfolkPartyApi = getGlobalTable("_TinyfolkPartyService_QueryAPI")
	end

	local queueNotificationFanout = if type(config) == "table" then config.queueNotificationFanout else nil
	if queueNotificationFanout == nil then
		queueNotificationFanout = getGlobalTable("_QueueNotificationFanout_QueryAPI")
	end
	if queueNotificationFanout == nil and type(QueueNotificationFanout) == "table" then
		queueNotificationFanout = (QueueNotificationFanout :: any).CreateDefault()
	end

	runtimeProcessor = PartyMatchmakingQueueProcessor.Create({
		queueStore = runtimeQueueStore,
		queueState = queueState,
		idempotencyStore = idempotencyStore,
		listLiveRealmAvailability = resolveListLiveRealmAvailability(config),
		selectMatchmakingTarget = function(availability: { any }, desiredActivity: any, skillBand: any, toolTier: any)
			return LiveRealmHubRouting.SelectMatchmakingTarget(availability, desiredActivity, skillBand, toolTier)
		end,
		admissionApi = admissionApi,
		tinyfolkPartyApi = tinyfolkPartyApi,
		onOutcome = function(entry: any, _receiptId: string?)
			recordOutcome(entry)
		end,
		now = nowFn,
	})

	runtimeProcessBatchSize = if type(configAny) == "table" and isPositiveInteger(configAny.processBatchSize)
		then configAny.processBatchSize
		else PartyMatchmakingQueueConfig.ProcessBatchSize
	runtimeProcessIntervalSeconds = if type(configAny) == "table"
			and type(configAny.processIntervalSeconds) == "number"
			and configAny.processIntervalSeconds > 0
		then configAny.processIntervalSeconds
		else PartyMatchmakingQueueConfig.ProcessIntervalSeconds
	runtimeQueueNotificationFanout = queueNotificationFanout
	started = true

	if type(configAny) == "table" and configAny.enableProcessingLoop == true then
		local requestedScheduler = configAny.processScheduler
		local scheduler: ProcessScheduler = if type(requestedScheduler) == "table"
				and type(requestedScheduler.schedule) == "function"
			then requestedScheduler
			else {
				schedule = defaultProcessSchedule,
				cancel = defaultProcessCancel,
			}
		runtimeProcessScheduler = scheduler

		scheduleNextTick = function()
			local activeScheduler = runtimeProcessScheduler
			local schedulerAny: any = activeScheduler
			if not started or activeScheduler == nil then
				return
			end

			local scheduledAt = nowSeconds()
			local scheduleOk, scheduleToken = pcall(function()
				return schedulerAny.schedule(runtimeProcessIntervalSeconds, function()
					runtimeProcessToken = nil
					if not started then
						return
					end

					local tickAt = nowSeconds()
					local processOk, processResult = pcall(function()
						return PartyMatchmakingQueueService.ProcessBatch(runtimeProcessBatchSize)
					end)
					if not processOk then
						runtimeProcessingDiagnostics.loopTickFailed += 1
						runtimeProcessingDiagnostics.loopLastErrorReason = "loop_tick_process_batch_throw"
					elseif type(processResult) ~= "table" or processResult.accepted ~= true then
						runtimeProcessingDiagnostics.loopTickFailed += 1
						runtimeProcessingDiagnostics.loopLastErrorReason = "loop_tick_process_batch_rejected"
					else
						runtimeProcessingDiagnostics.loopTickSucceeded += 1
						runtimeProcessingDiagnostics.loopLastErrorReason = "accepted"
					end
					runtimeProcessingDiagnostics.loopTickAttempts += 1
					runtimeProcessingDiagnostics.loopLastTickAt = tickAt

					scheduleNextTick()
				end)
			end)

			runtimeProcessingDiagnostics.loopScheduleAttempts += 1
			runtimeProcessingDiagnostics.loopLastScheduledAt = scheduledAt
			if not scheduleOk or scheduleToken == nil then
				runtimeProcessingDiagnostics.loopScheduleFailed += 1
				runtimeProcessToken = nil
				return
			end

			runtimeProcessingDiagnostics.loopScheduleSucceeded += 1
			runtimeProcessToken = scheduleToken
		end

		scheduleNextTick()
	end
end

local function ensureStarted(): boolean
	if started then
		return true
	end

	local ok = pcall(function()
		buildRuntime(nil)
	end)
	if not ok then
		stopProcessingLoop()
		started = false
		runtimeQueueStore = nil
		runtimeProcessor = nil
		resetProcessingDiagnostics("service_start_failed")
	end
	return started
end

function PartyMatchmakingQueueService.Start(config: any?): { ok: boolean, reason: string? }
	local ok, err = pcall(function()
		buildRuntime(config)
	end)
	if not ok then
		stopProcessingLoop()
		started = false
		runtimeQueueStore = nil
		runtimeProcessor = nil
		resetProcessingDiagnostics("service_start_failed")
		return {
			ok = false,
			reason = tostring(err),
		}
	end
	return {
		ok = true,
		reason = nil,
	}
end

function PartyMatchmakingQueueService.ConfigureForTests(config: any): { ok: boolean, reason: string? }
	return PartyMatchmakingQueueService.Start(config)
end

function PartyMatchmakingQueueService.ResetForTests()
	stopProcessingLoop()
	scheduleNextTick = nil
	started = false
	runtimeQueueStore = nil
	runtimeProcessor = nil
	runtimeQueueNotificationFanout = nil
	runtimeOutcomesByOperationId = {}
	runtimeActiveOperationIdByPartyId = {}
	resetProcessingDiagnostics("reset")
end

function PartyMatchmakingQueueService.GetProcessingDiagnostics(): any
	return {
		started = started,
		processBatchSize = runtimeProcessBatchSize,
		processIntervalSeconds = runtimeProcessIntervalSeconds,
		processingLoopEnabled = runtimeProcessScheduler ~= nil,
		totalBatches = runtimeProcessingDiagnostics.totalBatches,
		totalProcessed = runtimeProcessingDiagnostics.totalProcessed,
		totalMatched = runtimeProcessingDiagnostics.totalMatched,
		totalExpired = runtimeProcessingDiagnostics.totalExpired,
		totalFailed = runtimeProcessingDiagnostics.totalFailed,
		totalRetryDeferred = runtimeProcessingDiagnostics.totalRetryDeferred,
		totalDuplicatesSkipped = runtimeProcessingDiagnostics.totalDuplicatesSkipped,
		loopScheduleAttempts = runtimeProcessingDiagnostics.loopScheduleAttempts,
		loopScheduleSucceeded = runtimeProcessingDiagnostics.loopScheduleSucceeded,
		loopScheduleFailed = runtimeProcessingDiagnostics.loopScheduleFailed,
		loopTickAttempts = runtimeProcessingDiagnostics.loopTickAttempts,
		loopTickSucceeded = runtimeProcessingDiagnostics.loopTickSucceeded,
		loopTickFailed = runtimeProcessingDiagnostics.loopTickFailed,
		loopLastScheduledAt = runtimeProcessingDiagnostics.loopLastScheduledAt,
		loopLastTickAt = runtimeProcessingDiagnostics.loopLastTickAt,
		loopLastErrorReason = runtimeProcessingDiagnostics.loopLastErrorReason,
		lastOutcome = cloneTable(runtimeProcessingDiagnostics.lastOutcome),
		lastReason = runtimeProcessingDiagnostics.lastReason,
		lastProcessedAt = runtimeProcessingDiagnostics.lastProcessedAt,
	}
end

function PartyMatchmakingQueueService.EnqueueMatchmaking(input: any): EnqueueResult
	if not ensureStarted() then
		return {
			accepted = false,
			reason = "service_start_failed",
			snapshot = nil,
		}
	end
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "request_invalid",
			snapshot = nil,
		}
	end
	if not isNonEmptyString(input.partyId) then
		return {
			accepted = false,
			reason = "party_id_invalid",
			snapshot = nil,
		}
	end

	if not isPositiveInteger(input.leaderUserId) then
		return {
			accepted = false,
			reason = "leader_user_id_invalid",
			snapshot = nil,
		}
	end

	local activeOperationId = runtimeActiveOperationIdByPartyId[input.partyId]
	if isNonEmptyString(activeOperationId) then
		local existingOutcome = runtimeOutcomesByOperationId[activeOperationId]
		if type(existingOutcome) == "table" and existingOutcome.status == "pending" then
			return {
				accepted = false,
				reason = "party_already_queued",
				snapshot = existingOutcome,
			}
		end
	end

	local createdAt = if type(input.createdAt) == "number" then input.createdAt else nowSeconds()
	local timeoutSeconds = if type(input.timeoutSeconds) == "number" and input.timeoutSeconds > 0
		then math.min(input.timeoutSeconds, PartyMatchmakingQueueConfig.MaxTimeoutSeconds)
		else PartyMatchmakingQueueConfig.DefaultTimeoutSeconds
	local operationId = input.operationId
	if not isNonEmptyString(operationId) then
		local sanitizedPartyId = string.gsub(input.partyId, ":", "_")
		operationId = string.format(
			"%s%s_%d",
			PartyMatchmakingQueueConfig.OperationIdPrefix,
			sanitizedPartyId,
			math.floor(createdAt * 1000)
		)
	end

	local enqueueInput = {
		operationId = operationId,
		partyId = input.partyId,
		leaderUserId = input.leaderUserId,
		partySize = input.partySize,
		partyMemberUserIds = input.partyMemberUserIds,
		desiredActivity = input.desiredActivity,
		skillBand = if type(input.skillBand) == "number" then input.skillBand else 0,
		toolTier = if type(input.toolTier) == "number" then input.toolTier else 0,
		createdAt = createdAt,
		expiration = createdAt + timeoutSeconds,
		status = "pending",
	}

	if type(runtimeQueueStore) ~= "table" or type(runtimeQueueStore.Enqueue) ~= "function" then
		return {
			accepted = false,
			reason = "queue_store_unavailable",
			snapshot = nil,
		}
	end

	local result = runtimeQueueStore.Enqueue(enqueueInput)
	if type(result) ~= "table" or result.accepted ~= true then
		return {
			accepted = false,
			reason = if type(result) == "table" and type(result.reason) == "string"
				then result.reason
				else "queue_enqueue_failed",
			snapshot = result and result.snapshot or nil,
		}
	end

	local snapshot = PartyMatchmakingQueueState.BuildClientSnapshot(result.snapshot)
	runtimeOutcomesByOperationId[operationId] = snapshot
	runtimeActiveOperationIdByPartyId[input.partyId] = operationId

	local fanoutAny: any = runtimeQueueNotificationFanout
	if type(fanoutAny) == "table" and type(fanoutAny.PublishAdmission) == "function" then
		pcall(fanoutAny.PublishAdmission, "party_matchmaking_enqueue", {
			accepted = true,
			reason = "accepted",
			operationId = operationId,
			partyId = input.partyId,
			desiredActivity = input.desiredActivity,
			partySize = input.partySize,
		})
	end

	return {
		accepted = true,
		reason = "accepted",
		snapshot = snapshot,
	}
end

function PartyMatchmakingQueueService.ReadBatch(maxItems: any): ReadBatchResult
	if not ensureStarted() then
		return {
			accepted = false,
			reason = "service_start_failed",
			items = {},
		}
	end
	if type(runtimeQueueStore) ~= "table" or type(runtimeQueueStore.ReadBatch) ~= "function" then
		return {
			accepted = false,
			reason = "queue_store_unavailable",
			items = {},
		}
	end

	local result = runtimeQueueStore.ReadBatch(maxItems)
	if type(result) ~= "table" then
		return {
			accepted = false,
			reason = "queue_store_result_invalid",
			items = {},
		}
	end

	local items = if type(result.items) == "table" then result.items else {}
	local redactedItems = {}
	for _, item in ipairs(items) do
		if type(item) == "table" and type(item.entry) == "table" then
			table.insert(redactedItems, {
				receiptId = item.receiptId,
				entry = PartyMatchmakingQueueState.BuildClientSnapshot(item.entry),
				reason = item.reason,
			})
		else
			table.insert(redactedItems, item)
		end
	end

	return {
		accepted = result.accepted == true,
		reason = if type(result.reason) == "string" then result.reason else "queue_store_result_invalid",
		items = redactedItems,
	}
end

function PartyMatchmakingQueueService.GetQueueSnapshot(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "request_invalid",
		}
	end

	local operationId = input.operationId
	if isNonEmptyString(operationId) then
		local snapshot = runtimeOutcomesByOperationId[operationId]
		if snapshot ~= nil then
			return {
				accepted = true,
				reason = "accepted",
				snapshot = cloneTable(snapshot),
			}
		end
	end

	local partyId = input.partyId
	if isNonEmptyString(partyId) then
		local activeId = runtimeActiveOperationIdByPartyId[partyId]
		if isNonEmptyString(activeId) then
			local snapshot = runtimeOutcomesByOperationId[activeId]
			if snapshot ~= nil then
				return {
					accepted = true,
					reason = "accepted",
					snapshot = cloneTable(snapshot),
				}
			end
		end
	end

	return {
		accepted = false,
		reason = "queue_snapshot_not_found",
	}
end

function PartyMatchmakingQueueService.ProcessBatch(maxItems: any): ProcessResult
	if not isPositiveInteger(maxItems) then
		return {
			accepted = false,
			reason = "max_items_invalid",
			outcome = nil,
		}
	end
	if not ensureStarted() then
		return {
			accepted = false,
			reason = "service_start_failed",
			outcome = nil,
		}
	end
	if type(runtimeProcessor) ~= "table" or type(runtimeProcessor.ProcessBatch) ~= "function" then
		return {
			accepted = false,
			reason = "queue_processor_unavailable",
			outcome = nil,
		}
	end

	local outcome = runtimeProcessor.ProcessBatch(maxItems)
	updateProcessingDiagnostics(outcome, nowSeconds(), "accepted")

	local fanoutAny: any = runtimeQueueNotificationFanout
	if type(fanoutAny) == "table" and type(fanoutAny.PublishAdmission) == "function" then
		pcall(fanoutAny.PublishAdmission, "party_matchmaking_batch_processed", {
			requestedMaxItems = maxItems,
			processed = outcome.processed,
			matched = outcome.matched,
			expired = outcome.expired,
			failed = outcome.failed,
			retryDeferred = outcome.retryDeferred,
			duplicatesSkipped = outcome.duplicatesSkipped,
		})
	end

	return {
		accepted = true,
		reason = "accepted",
		outcome = outcome,
	}
end

globalEnv._PartyMatchmakingQueue_QueryAPI = {
	EnqueueMatchmaking = function(input: any): EnqueueResult
		return PartyMatchmakingQueueService.EnqueueMatchmaking(input)
	end,
	ReadBatch = function(maxItems: any): ReadBatchResult
		return PartyMatchmakingQueueService.ReadBatch(maxItems)
	end,
	GetQueueSnapshot = function(input: any): any
		return PartyMatchmakingQueueService.GetQueueSnapshot(input)
	end,
	ProcessBatch = function(maxItems: any): ProcessResult
		return PartyMatchmakingQueueService.ProcessBatch(maxItems)
	end,
	GetProcessingDiagnostics = function(): any
		return PartyMatchmakingQueueService.GetProcessingDiagnostics()
	end,
	ConfigureForTests = function(config: any)
		return PartyMatchmakingQueueService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		PartyMatchmakingQueueService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_PartyMatchmakingQueue_QueryAPI", globalEnv._PartyMatchmakingQueue_QueryAPI)
end

return PartyMatchmakingQueueService
