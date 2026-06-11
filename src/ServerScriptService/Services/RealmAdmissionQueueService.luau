--!strict

local RealmAdmissionQueueState = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmAdmissionQueueState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmAdmissionQueueState")

local PartyHistoryProfileState = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PartyHistoryProfileState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PartyHistoryProfileState")

local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local MemoryStoreAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreAdapter"))
	else (require :: any)("./MemoryStoreAdapter")

local RealmAdmissionQueueStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAdmissionQueueStore"))
	else (require :: any)("./RealmAdmissionQueueStore")

local RealmAdmissionQueueProcessor = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAdmissionQueueProcessor"))
	else (require :: any)("./RealmAdmissionQueueProcessor")

local QueueProcessingIdempotencyStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("QueueProcessingIdempotencyStore"))
	else (require :: any)("./QueueProcessingIdempotencyStore")

local QueueNotificationFanout: any = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("QueueNotificationFanout"))
	else (require :: any)("./QueueNotificationFanout")

local RealmAdmissionQueueService: any = {}
local globalEnv: any = getfenv()

local DEFAULT_PROCESS_BATCH_SIZE = 25
local DEFAULT_PROCESS_INTERVAL_SECONDS = 1

type ProcessScheduler = {
	schedule: (number, () -> ()) -> any,
	cancel: ((any) -> ())?,
}

export type EnqueueResult = {
	accepted: boolean,
	reason: string,
	snapshot: any?,
}

export type ProcessResult = {
	accepted: boolean,
	reason: string,
	outcome: any?,
}

export type BatchReadResult = {
	accepted: boolean,
	reason: string,
	items: { any },
}

type ProcessingDiagnostics = {
	totalBatches: number,
	totalProcessed: number,
	totalSucceeded: number,
	totalExpired: number,
	totalRetryDeferred: number,
	totalFailed: number,
	totalDuplicatesSkipped: number,
	totalCleanupDeferred: number,
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
local runtimeProcessBatchSize = DEFAULT_PROCESS_BATCH_SIZE
local runtimeProcessIntervalSeconds = DEFAULT_PROCESS_INTERVAL_SECONDS
local runtimeQueueNotificationFanout: any = nil
local runtimePartyResolver: any = nil
local runtimeProcessingDiagnostics: ProcessingDiagnostics = {
	totalBatches = 0,
	totalProcessed = 0,
	totalSucceeded = 0,
	totalExpired = 0,
	totalRetryDeferred = 0,
	totalFailed = 0,
	totalDuplicatesSkipped = 0,
	totalCleanupDeferred = 0,
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
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return value > 0
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

local function resolveProcessBatchSize(config: any): number
	local configAny: any = config
	local requestedBatchSize = if type(configAny) == "table" then rawget(configAny, "processBatchSize") else nil
	if isPositiveInteger(requestedBatchSize) then
		return requestedBatchSize
	end
	return DEFAULT_PROCESS_BATCH_SIZE
end

local function resolveProcessIntervalSeconds(config: any): number
	local configAny: any = config
	local requestedIntervalSeconds = if type(configAny) == "table"
		then rawget(configAny, "processIntervalSeconds")
		else nil
	if type(requestedIntervalSeconds) == "number" then
		local value = requestedIntervalSeconds
		if value > 0 and value == value and value ~= math.huge and value ~= -math.huge then
			return value
		end
	end
	return DEFAULT_PROCESS_INTERVAL_SECONDS
end

local function resolveProcessScheduler(config: any): ProcessScheduler
	local configAny: any = config
	local requestedScheduler = if type(configAny) == "table" then rawget(configAny, "processScheduler") else nil
	if type(requestedScheduler) == "table" then
		local scheduler: any = requestedScheduler
		if type(scheduler.schedule) == "function" then
			return scheduler
		end
	end

	return {
		schedule = defaultProcessSchedule,
		cancel = defaultProcessCancel,
	}
end

local function resetProcessingDiagnostics(reason: string)
	runtimeProcessingDiagnostics = {
		totalBatches = 0,
		totalProcessed = 0,
		totalSucceeded = 0,
		totalExpired = 0,
		totalRetryDeferred = 0,
		totalFailed = 0,
		totalDuplicatesSkipped = 0,
		totalCleanupDeferred = 0,
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

local function nowSeconds(): number
	return os.clock()
end

local function recordLoopSchedule(at: number, success: boolean, reason: string)
	runtimeProcessingDiagnostics.loopScheduleAttempts += 1
	runtimeProcessingDiagnostics.loopLastScheduledAt = at
	if success then
		runtimeProcessingDiagnostics.loopScheduleSucceeded += 1
	else
		runtimeProcessingDiagnostics.loopScheduleFailed += 1
	end
	runtimeProcessingDiagnostics.loopLastErrorReason = reason
end

local function recordLoopTick(at: number, success: boolean, reason: string)
	runtimeProcessingDiagnostics.loopTickAttempts += 1
	runtimeProcessingDiagnostics.loopLastTickAt = at
	if success then
		runtimeProcessingDiagnostics.loopTickSucceeded += 1
	else
		runtimeProcessingDiagnostics.loopTickFailed += 1
	end
	runtimeProcessingDiagnostics.loopLastErrorReason = reason
end

local cloneTable: (source: any) -> any
cloneTable = function(source: any): any
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

local function updateProcessingDiagnostics(outcome: any, nowAt: number, reason: string)
	if type(outcome) == "table" then
		local outcomeAny: any = outcome
		runtimeProcessingDiagnostics.totalBatches += 1
		runtimeProcessingDiagnostics.totalProcessed += if type(outcomeAny.processed) == "number"
			then outcomeAny.processed
			else 0
		runtimeProcessingDiagnostics.totalSucceeded += if type(outcomeAny.succeeded) == "number"
			then outcomeAny.succeeded
			else 0
		runtimeProcessingDiagnostics.totalExpired += if type(outcomeAny.expired) == "number"
			then outcomeAny.expired
			else 0
		runtimeProcessingDiagnostics.totalRetryDeferred += if type(outcomeAny.retryDeferred) == "number"
			then outcomeAny.retryDeferred
			else 0
		runtimeProcessingDiagnostics.totalFailed += if type(outcomeAny.failed) == "number" then outcomeAny.failed else 0
		runtimeProcessingDiagnostics.totalDuplicatesSkipped += if type(outcomeAny.duplicatesSkipped) == "number"
			then outcomeAny.duplicatesSkipped
			else 0
		runtimeProcessingDiagnostics.totalCleanupDeferred += if type(outcomeAny.cleanupDeferred) == "number"
			then outcomeAny.cleanupDeferred
			else 0
		runtimeProcessingDiagnostics.lastOutcome = cloneTable(outcome)
	else
		runtimeProcessingDiagnostics.lastOutcome = nil
	end
	runtimeProcessingDiagnostics.lastReason = reason
	runtimeProcessingDiagnostics.lastProcessedAt = nowAt
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

local function resolvePartyResolver(config: any): any?
	local configAny: any = config
	local requestedResolver = if type(configAny) == "table" then rawget(configAny, "partyResolver") else nil
	if requestedResolver ~= nil then
		return requestedResolver
	end

	return getGlobalTable("_RealmAdmissionPartyResolver_QueryAPI")
end

local function unregisterResolverParty(partyId: any)
	if type(partyId) ~= "string" or partyId == "" then
		return
	end

	local resolverAny: any = runtimePartyResolver
	if type(resolverAny) ~= "table" or type((resolverAny :: any).UnregisterParty) ~= "function" then
		return
	end

	pcall((resolverAny :: any).UnregisterParty, partyId)
end

local function resolveProfilePersistenceGateway(): any?
	local gateway = getGlobalTable("_ProfilePersistenceGateway_QueryAPI")
	if type(gateway) == "table" then
		return gateway
	end

	local ok, loaded = pcall(function()
		if script ~= nil and script.Parent ~= nil then
			return require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
		end
		return (require :: any)("./ProfilePersistenceGateway")
	end)
	if ok then
		return loaded
	end

	return nil
end

local function makePlayerStub(userId: number): any
	return {
		UserId = userId,
	}
end

local function persistPartyHistoryForAdmission(input: any)
	if type(input) ~= "table" or type(input.partyMemberUserIds) ~= "table" or #input.partyMemberUserIds <= 0 then
		return
	end

	local gateway = resolveProfilePersistenceGateway()
	if type(gateway) ~= "table" or type(gateway.UpdateLoadedPlayerProfileData) ~= "function" then
		return
	end

	local historyEntry = {
		operationId = input.operationId,
		partyId = input.partyId,
		targetRealmId = input.targetRealmId,
		entryType = input.entryType,
		formedAt = input.createdAt,
		partySize = input.partySize,
		partyMemberUserIds = input.partyMemberUserIds,
	}

	for _, memberUserId in ipairs(input.partyMemberUserIds) do
		if type(memberUserId) ~= "number" then
			continue
		end

		local player = makePlayerStub(memberUserId)
		local updateOk, updateResult = pcall(
			gateway.UpdateLoadedPlayerProfileData,
			player,
			function(currentData: any): any
				if type(currentData) ~= "table" then
					return nil, "profile_data_invalid"
				end
				local historyResult = PartyHistoryProfileState.AppendEntry(
					currentData,
					historyEntry,
					PartyHistoryProfileState.GetDefaultHistoryLimit()
				)
				if historyResult.accepted ~= true then
					return nil, historyResult.reason
				end
				return historyResult.profileData
			end
		)
		if updateOk and type(updateResult) == "table" and updateResult.ok == true then
			if type(gateway.SavePlayerProfile) == "function" then
				pcall(gateway.SavePlayerProfile, player)
			end
		end
	end
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
		local activeCapacityPolicy = MemoryStoreStructurePolicy.GetPolicy("activeRealmCapacity")
		local mapName = if type(activeCapacityPolicy) == "table" then activeCapacityPolicy.name else nil
		adapter = MemoryStoreAdapter.CreateDefault({
			activeRealmCapacityMapName = mapName,
		})
	end

	local capacityApi = if type(config) == "table" then config.capacityApi else nil
	if capacityApi == nil then
		capacityApi = getGlobalTable("_ActiveRealmCapacity_QueryAPI")
	end

	local teleportDispatcher = if type(config) == "table" then config.teleportDispatcher else nil
	if teleportDispatcher == nil then
		teleportDispatcher = getGlobalTable("_RealmTeleportDispatcher_QueryAPI")
	end

	local operationLock = if type(config) == "table" then config.operationLock else nil
	if operationLock == nil then
		operationLock = getGlobalTable("_TransferLock_QueryAPI")
	end

	local queueNotificationFanout = if type(config) == "table" then config.queueNotificationFanout else nil
	if queueNotificationFanout == nil then
		queueNotificationFanout = getGlobalTable("_QueueNotificationFanout_QueryAPI")
	end
	if queueNotificationFanout == nil and type(QueueNotificationFanout) == "table" then
		queueNotificationFanout = (QueueNotificationFanout :: any).CreateDefault()
	end

	local queueState = if type(config) == "table" and config.queueState ~= nil
		then config.queueState
		else RealmAdmissionQueueState
	local idempotencyStore = if type(config) == "table" then config.idempotencyStore else nil
	local partyResolver = resolvePartyResolver(config)
	local structurePolicy = if type(config) == "table" and config.structurePolicy ~= nil
		then config.structurePolicy
		else MemoryStoreStructurePolicy
	local codec = resolveCodec(config)
	local nowFn = if type(config) == "table" and type(config.now) == "function" then config.now else nil

	runtimeQueueStore = RealmAdmissionQueueStore.Create({
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

	runtimeProcessor = RealmAdmissionQueueProcessor.Create({
		queueStore = runtimeQueueStore,
		queueState = queueState,
		capacityApi = capacityApi,
		teleportDispatcher = teleportDispatcher,
		operationLock = operationLock,
		idempotencyStore = idempotencyStore,
		partyResolver = partyResolver,
		now = nowFn,
	})

	runtimeProcessBatchSize = resolveProcessBatchSize(configAny)
	runtimeProcessIntervalSeconds = resolveProcessIntervalSeconds(configAny)
	runtimeQueueNotificationFanout = queueNotificationFanout
	runtimePartyResolver = partyResolver
	started = true

	if type(configAny) == "table" and configAny.enableProcessingLoop == true then
		runtimeProcessScheduler = resolveProcessScheduler(configAny)

		scheduleNextTick = function()
			local scheduler = runtimeProcessScheduler
			local schedulerAny: any = scheduler
			if not started or scheduler == nil then
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
						return RealmAdmissionQueueService.ProcessBatch(runtimeProcessBatchSize)
					end)
					if not processOk then
						recordLoopTick(tickAt, false, "loop_tick_process_batch_throw")
					elseif type(processResult) ~= "table" then
						recordLoopTick(tickAt, false, "loop_tick_process_batch_result_invalid")
					elseif processResult.accepted == true then
						recordLoopTick(tickAt, true, "accepted")
					else
						local tickReason = if type(processResult.reason) == "string"
								and processResult.reason ~= ""
							then processResult.reason
							else "loop_tick_process_batch_rejected"
						recordLoopTick(tickAt, false, tickReason)
					end

					scheduleNextTick()
				end)
			end)

			if not scheduleOk then
				runtimeProcessToken = nil
				recordLoopSchedule(scheduledAt, false, "loop_schedule_failed")
				return
			end

			if scheduleToken == nil then
				runtimeProcessToken = nil
				recordLoopSchedule(scheduledAt, false, "loop_schedule_token_invalid")
				return
			end

			runtimeProcessToken = scheduleToken
			recordLoopSchedule(scheduledAt, true, "accepted")
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
		runtimeQueueNotificationFanout = nil
		runtimePartyResolver = nil
		resetProcessingDiagnostics("service_start_failed")
	end

	return started
end

function RealmAdmissionQueueService.Start(config: any?): { ok: boolean, reason: string? }
	local ok, err = pcall(function()
		buildRuntime(config)
	end)
	if not ok then
		stopProcessingLoop()
		started = false
		runtimeQueueStore = nil
		runtimeProcessor = nil
		runtimeQueueNotificationFanout = nil
		runtimePartyResolver = nil
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

function RealmAdmissionQueueService.ConfigureForTests(config: any): { ok: boolean, reason: string? }
	return RealmAdmissionQueueService.Start(config)
end

function RealmAdmissionQueueService.ResetForTests()
	stopProcessingLoop()
	scheduleNextTick = nil
	started = false
	runtimeQueueStore = nil
	runtimeProcessor = nil
	runtimeQueueNotificationFanout = nil
	runtimePartyResolver = nil
	resetProcessingDiagnostics("reset")
end

function RealmAdmissionQueueService.GetProcessingDiagnostics(): any
	return {
		started = started,
		processBatchSize = runtimeProcessBatchSize,
		processIntervalSeconds = runtimeProcessIntervalSeconds,
		processingLoopEnabled = runtimeProcessScheduler ~= nil,
		totalBatches = runtimeProcessingDiagnostics.totalBatches,
		totalProcessed = runtimeProcessingDiagnostics.totalProcessed,
		totalSucceeded = runtimeProcessingDiagnostics.totalSucceeded,
		totalExpired = runtimeProcessingDiagnostics.totalExpired,
		totalRetryDeferred = runtimeProcessingDiagnostics.totalRetryDeferred,
		totalFailed = runtimeProcessingDiagnostics.totalFailed,
		totalDuplicatesSkipped = runtimeProcessingDiagnostics.totalDuplicatesSkipped,
		totalCleanupDeferred = runtimeProcessingDiagnostics.totalCleanupDeferred,
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

function RealmAdmissionQueueService.EnqueueAdmission(input: any): EnqueueResult
	if not ensureStarted() then
		return {
			accepted = false,
			reason = "service_start_failed",
			snapshot = nil,
		}
	end

	if type(runtimeQueueStore) ~= "table" or type(runtimeQueueStore.Enqueue) ~= "function" then
		return {
			accepted = false,
			reason = "queue_store_unavailable",
			snapshot = nil,
		}
	end

	local resolverAny: any = runtimePartyResolver
	local inputAny: any = input
	local partyMemberUserIds = if type(inputAny) == "table" and type(inputAny.partyMemberUserIds) == "table"
		then inputAny.partyMemberUserIds
		else nil
	local registrationReason: string? = nil
	local registeredPartyId: string? = nil

	if partyMemberUserIds ~= nil then
		if type(resolverAny) ~= "table" or type((resolverAny :: any).RegisterPartyMembers) ~= "function" then
			return {
				accepted = false,
				reason = "party_resolver_unavailable",
				snapshot = nil,
			}
		end

		local registerInput = {
			partyId = if type(inputAny) == "table" then inputAny.partyId else nil,
			memberUserIds = partyMemberUserIds,
			at = if type(inputAny) == "table" then inputAny.createdAt else nil,
		}
		local ok, registrationResult = pcall((resolverAny :: any).RegisterPartyMembers, registerInput)
		if not ok or type(registrationResult) ~= "table" or registrationResult.accepted ~= true then
			registrationReason = if type(registrationResult) == "table"
					and type(registrationResult.reason) == "string"
				then registrationResult.reason
				else "party_member_registration_failed"
			return {
				accepted = false,
				reason = registrationReason or "party_member_registration_failed",
				snapshot = nil,
			}
		end

		registrationReason = if type(registrationResult.reason) == "string"
			then registrationResult.reason
			else "accepted"
		if type(registerInput.partyId) == "string" and registerInput.partyId ~= "" then
			registeredPartyId = registerInput.partyId
		end
	end

	local result = runtimeQueueStore.Enqueue(input)
	if type(result) ~= "table" then
		if registeredPartyId ~= nil then
			unregisterResolverParty(registeredPartyId)
		end
		return {
			accepted = false,
			reason = "queue_store_result_invalid",
			snapshot = nil,
		}
	end

	if result.accepted ~= true and registeredPartyId ~= nil then
		unregisterResolverParty(registeredPartyId)
	end

	local response = {
		accepted = result.accepted == true,
		reason = if type(result.reason) == "string" then result.reason else "queue_store_result_invalid",
		snapshot = result.snapshot,
	}

	if response.accepted == true and type(input) == "table" then
		persistPartyHistoryForAdmission(input)
	end

	local fanoutAny: any = runtimeQueueNotificationFanout
	if type(fanoutAny) == "table" and type(fanoutAny.PublishAdmission) == "function" then
		pcall((fanoutAny :: any).PublishAdmission, "admission_enqueue", {
			accepted = response.accepted,
			reason = response.reason,
			partyMemberRegistrationReason = registrationReason,
			partyMemberCount = if type(partyMemberUserIds) == "table" then #partyMemberUserIds else nil,
			operationId = if type(input) == "table" then input.operationId else nil,
			targetRealmId = if type(input) == "table" then input.targetRealmId else nil,
			partyId = if type(input) == "table" then input.partyId else nil,
			entryType = if type(input) == "table" then input.entryType else nil,
		})
	end

	return response
end

function RealmAdmissionQueueService.ReadBatch(maxItems: any): BatchReadResult
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

	return {
		accepted = result.accepted == true,
		reason = if type(result.reason) == "string" then result.reason else "queue_store_result_invalid",
		items = if type(result.items) == "table" then result.items else {},
	}
end

function RealmAdmissionQueueService.ProcessBatch(maxItems: any): ProcessResult
	if not isPositiveInteger(maxItems) then
		updateProcessingDiagnostics(nil, os.clock(), "max_items_invalid")
		return {
			accepted = false,
			reason = "max_items_invalid",
			outcome = nil,
		}
	end

	if not ensureStarted() then
		updateProcessingDiagnostics(nil, os.clock(), "service_start_failed")
		return {
			accepted = false,
			reason = "service_start_failed",
			outcome = nil,
		}
	end

	if type(runtimeProcessor) ~= "table" or type(runtimeProcessor.ProcessBatch) ~= "function" then
		updateProcessingDiagnostics(nil, os.clock(), "queue_processor_unavailable")
		return {
			accepted = false,
			reason = "queue_processor_unavailable",
			outcome = nil,
		}
	end

	local outcome = runtimeProcessor.ProcessBatch(maxItems)
	if type(outcome) ~= "table" then
		updateProcessingDiagnostics(nil, os.clock(), "queue_processor_result_invalid")
		return {
			accepted = false,
			reason = "queue_processor_result_invalid",
			outcome = nil,
		}
	end

	updateProcessingDiagnostics(outcome, os.clock(), "accepted")

	local fanoutAny: any = runtimeQueueNotificationFanout
	if type(fanoutAny) == "table" and type(fanoutAny.PublishAdmission) == "function" then
		pcall((fanoutAny :: any).PublishAdmission, "admission_batch_processed", {
			requestedMaxItems = maxItems,
			processed = outcome.processed,
			succeeded = outcome.succeeded,
			expired = outcome.expired,
			retryDeferred = outcome.retryDeferred,
			failed = outcome.failed,
			duplicatesSkipped = outcome.duplicatesSkipped,
			cleanupDeferred = outcome.cleanupDeferred,
		})
	end

	return {
		accepted = true,
		reason = "accepted",
		outcome = outcome,
	}
end

globalEnv._RealmAdmissionQueue_QueryAPI = {
	EnqueueAdmission = function(input: any): EnqueueResult
		return RealmAdmissionQueueService.EnqueueAdmission(input)
	end,
	ReadBatch = function(maxItems: any): BatchReadResult
		return RealmAdmissionQueueService.ReadBatch(maxItems)
	end,
	ProcessBatch = function(maxItems: any): ProcessResult
		return RealmAdmissionQueueService.ProcessBatch(maxItems)
	end,
	GetProcessingDiagnostics = function(): any
		return RealmAdmissionQueueService.GetProcessingDiagnostics()
	end,
	ConfigureForTests = function(config: any)
		return RealmAdmissionQueueService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		RealmAdmissionQueueService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RealmAdmissionQueue_QueryAPI", globalEnv._RealmAdmissionQueue_QueryAPI)
end

return RealmAdmissionQueueService
