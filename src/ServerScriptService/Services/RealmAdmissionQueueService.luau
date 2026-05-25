--!strict

local RealmAdmissionQueueState = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmAdmissionQueueState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmAdmissionQueueState")

local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local RealmAdmissionQueueStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAdmissionQueueStore"))
	else (require :: any)("./RealmAdmissionQueueStore")

local RealmAdmissionQueueProcessor = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAdmissionQueueProcessor"))
	else (require :: any)("./RealmAdmissionQueueProcessor")

local RealmAdmissionQueueService: any = {}
local globalEnv: any = getfenv()

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

local started = false
local runtimeQueueStore: any = nil
local runtimeProcessor: any = nil

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

local function resolveCodec(config: any): any?
	local configAny: any = config
	if type(configAny) == "table" and configAny.codec ~= nil then
		return configAny.codec
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

local function buildRuntime(config: any)
	local adapter = if type(config) == "table" then config.adapter else nil
	if adapter == nil then
		adapter = getGlobalTable("_MemoryStoreAdapter_QueryAPI")
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

	local queueState = if type(config) == "table" and config.queueState ~= nil
		then config.queueState
		else RealmAdmissionQueueState
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

	runtimeProcessor = RealmAdmissionQueueProcessor.Create({
		queueStore = runtimeQueueStore,
		queueState = queueState,
		capacityApi = capacityApi,
		teleportDispatcher = teleportDispatcher,
		operationLock = operationLock,
		now = nowFn,
	})

	started = true
end

local function ensureStarted(): boolean
	if started then
		return true
	end

	local ok = pcall(function()
		buildRuntime(nil)
	end)

	if not ok then
		started = false
		runtimeQueueStore = nil
		runtimeProcessor = nil
	end

	return started
end

function RealmAdmissionQueueService.Start(config: any?): { ok: boolean, reason: string? }
	local ok, err = pcall(function()
		buildRuntime(config)
	end)
	if not ok then
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
	started = false
	runtimeQueueStore = nil
	runtimeProcessor = nil
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

	local result = runtimeQueueStore.Enqueue(input)
	if type(result) ~= "table" then
		return {
			accepted = false,
			reason = "queue_store_result_invalid",
			snapshot = nil,
		}
	end

	return {
		accepted = result.accepted == true,
		reason = if type(result.reason) == "string" then result.reason else "queue_store_result_invalid",
		snapshot = result.snapshot,
	}
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
	if type(outcome) ~= "table" then
		return {
			accepted = false,
			reason = "queue_processor_result_invalid",
			outcome = nil,
		}
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
