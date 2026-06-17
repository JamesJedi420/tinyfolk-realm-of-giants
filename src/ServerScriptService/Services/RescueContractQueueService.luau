--!strict

local RescueContractConfig = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Config")
			:WaitForChild("RescueContractConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/RescueContractConfig")

local RescueContractQueueState = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RescueContractQueueState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RescueContractQueueState")

local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local MemoryStoreAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreAdapter"))
	else (require :: any)("./MemoryStoreAdapter")

local RescueContractQueueStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RescueContractQueueStore"))
	else (require :: any)("./RescueContractQueueStore")

local RescueContractQueueService: any = {}
local globalEnv: any = getfenv()

local started = false
local runtimeQueueStore: any = nil

local diagnostics = {
	enqueueAttempts = 0,
	enqueueSucceeded = 0,
	enqueueFailed = 0,
	reconcileAttempts = 0,
	reconcileSucceeded = 0,
	reconcileFailed = 0,
	removeAttempts = 0,
	removeSucceeded = 0,
	removeFailed = 0,
	lastReason = "not_started",
	lastIngestedCount = 0,
	lastRemovedCount = 0,
}

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
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

local function nowSeconds(): number
	return os.clock()
end

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

local function resolveMemoryStoreAdapter(config: any): any?
	local configAny: any = config
	local requestedAdapter = if type(configAny) == "table" then rawget(configAny, "adapter") else nil
	if requestedAdapter ~= nil then
		return requestedAdapter
	end

	local fromEnv = getGlobalTable("_MemoryStoreAdapter_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end

	return MemoryStoreAdapter.CreateDefault()
end

local function buildRuntime(config: any?)
	if started and runtimeQueueStore ~= nil then
		return
	end

	local codec = resolveCodec(config)
	local adapter = resolveMemoryStoreAdapter(config)
	runtimeQueueStore = RescueContractQueueStore.Create({
		adapter = adapter,
		codec = codec,
		queueState = RescueContractQueueState,
		structurePolicy = MemoryStoreStructurePolicy,
	})
	started = runtimeQueueStore ~= nil
end

local function getRescueContractServiceApi(): any?
	return getGlobalTable("_RescueContractService_QueryAPI")
end

function RescueContractQueueService.Start(config: any?): { ok: boolean, reason: string? }
	local ok, err = pcall(function()
		buildRuntime(config)
	end)
	if not ok or runtimeQueueStore == nil then
		started = false
		runtimeQueueStore = nil
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

function RescueContractQueueService.ConfigureForTests(config: any): { ok: boolean, reason: string? }
	return RescueContractQueueService.Start(config)
end

function RescueContractQueueService.ResetForTests()
	started = false
	runtimeQueueStore = nil
	diagnostics = {
		enqueueAttempts = 0,
		enqueueSucceeded = 0,
		enqueueFailed = 0,
		reconcileAttempts = 0,
		reconcileSucceeded = 0,
		reconcileFailed = 0,
		removeAttempts = 0,
		removeSucceeded = 0,
		removeFailed = 0,
		lastReason = "reset",
		lastIngestedCount = 0,
		lastRemovedCount = 0,
	}
end

function RescueContractQueueService.GetDiagnostics(): any
	return {
		started = started,
		enqueueAttempts = diagnostics.enqueueAttempts,
		enqueueSucceeded = diagnostics.enqueueSucceeded,
		enqueueFailed = diagnostics.enqueueFailed,
		reconcileAttempts = diagnostics.reconcileAttempts,
		reconcileSucceeded = diagnostics.reconcileSucceeded,
		reconcileFailed = diagnostics.reconcileFailed,
		removeAttempts = diagnostics.removeAttempts,
		removeSucceeded = diagnostics.removeSucceeded,
		removeFailed = diagnostics.removeFailed,
		lastReason = diagnostics.lastReason,
		lastIngestedCount = diagnostics.lastIngestedCount,
		lastRemovedCount = diagnostics.lastRemovedCount,
	}
end

function RescueContractQueueService.EnqueueQueueEntry(input: any): any
	diagnostics.enqueueAttempts += 1
	if not started or runtimeQueueStore == nil or type(runtimeQueueStore.Enqueue) ~= "function" then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = "service_unavailable"
		return { accepted = false, reason = "service_unavailable" }
	end

	local result = runtimeQueueStore.Enqueue(input)
	if type(result) ~= "table" or result.accepted ~= true then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = if type(result) == "table" and type(result.reason) == "string"
			then result.reason
			else "enqueue_failed"
		return { accepted = false, reason = diagnostics.lastReason }
	end

	diagnostics.enqueueSucceeded += 1
	diagnostics.lastReason = "accepted"
	return {
		accepted = true,
		reason = "accepted",
		snapshot = result.snapshot,
	}
end

function RescueContractQueueService.RemoveStoreReceipt(receiptId: any): any
	diagnostics.removeAttempts += 1
	if not started or runtimeQueueStore == nil or type(runtimeQueueStore.Remove) ~= "function" then
		diagnostics.removeFailed += 1
		diagnostics.lastReason = "service_unavailable"
		return { accepted = false, reason = "service_unavailable" }
	end
	if type(receiptId) ~= "string" or receiptId == "" then
		diagnostics.removeFailed += 1
		diagnostics.lastReason = "receipt_id_invalid"
		return { accepted = false, reason = "receipt_id_invalid" }
	end

	local result = runtimeQueueStore.Remove(receiptId)
	if type(result) ~= "table" or result.accepted ~= true then
		diagnostics.removeFailed += 1
		diagnostics.lastReason = if type(result) == "table" and type(result.reason) == "string"
			then result.reason
			else "remove_failed"
		return { accepted = false, reason = diagnostics.lastReason }
	end

	diagnostics.removeSucceeded += 1
	diagnostics.lastReason = "accepted"
	return { accepted = true, reason = "accepted" }
end

function RescueContractQueueService.ReconcileFromStore(input: any?): any
	diagnostics.reconcileAttempts += 1
	if not started or runtimeQueueStore == nil or type(runtimeQueueStore.ReadBatch) ~= "function" then
		diagnostics.reconcileFailed += 1
		diagnostics.lastReason = "service_unavailable"
		return { accepted = false, reason = "service_unavailable", ingestedCount = 0, removedCount = 0 }
	end

	local inputAny: any = input
	local at = if type(inputAny) == "table" and type(inputAny.at) == "number" then inputAny.at else nowSeconds()
	local limit = if type(inputAny) == "table" and isPositiveInteger(inputAny.limit)
		then inputAny.limit
		else RescueContractConfig.ReconcileBatchSize

	local rescueApi = getRescueContractServiceApi()
	if type(rescueApi) ~= "table" or type(rescueApi.IngestQueueEntry) ~= "function" then
		diagnostics.reconcileFailed += 1
		diagnostics.lastReason = "rescue_contract_api_unavailable"
		return { accepted = false, reason = "rescue_contract_api_unavailable", ingestedCount = 0, removedCount = 0 }
	end

	local readResult = runtimeQueueStore.ReadBatch(limit)
	if type(readResult) ~= "table" or readResult.accepted ~= true then
		diagnostics.reconcileFailed += 1
		diagnostics.lastReason = if type(readResult) == "table" and type(readResult.reason) == "string"
			then readResult.reason
			else "store_read_failed"
		return { accepted = false, reason = diagnostics.lastReason, ingestedCount = 0, removedCount = 0 }
	end

	local ingestedCount = 0
	local removedCount = 0
	for _, item in ipairs(readResult.items) do
		if type(item) ~= "table" then
			continue
		end
		local receiptId = item.receiptId
		local entry = item.entry
		if type(receiptId) ~= "string" or receiptId == "" then
			continue
		end
		if entry == nil then
			removedCount += 1
			continue
		end

		if RescueContractQueueState.IsExpired(entry, at) then
			local removeResult = RescueContractQueueService.RemoveStoreReceipt(receiptId)
			if removeResult.accepted == true then
				removedCount += 1
			end
			continue
		end

		local ingestResult = rescueApi.IngestQueueEntry(entry, receiptId, at)
		if type(ingestResult) == "table" and ingestResult.accepted == true then
			ingestedCount += 1
		end
	end

	diagnostics.reconcileSucceeded += 1
	diagnostics.lastReason = "accepted"
	diagnostics.lastIngestedCount = ingestedCount
	diagnostics.lastRemovedCount = removedCount
	return {
		accepted = true,
		reason = "accepted",
		ingestedCount = ingestedCount,
		removedCount = removedCount,
	}
end

globalEnv._RescueContractQueue_QueryAPI = {
	EnqueueQueueEntry = RescueContractQueueService.EnqueueQueueEntry,
	ReconcileFromStore = RescueContractQueueService.ReconcileFromStore,
	RemoveStoreReceipt = RescueContractQueueService.RemoveStoreReceipt,
	GetDiagnostics = RescueContractQueueService.GetDiagnostics,
	ConfigureForTests = RescueContractQueueService.ConfigureForTests,
	ResetForTests = RescueContractQueueService.ResetForTests,
}

if type(_G) == "table" then
	rawset(_G, "_RescueContractQueue_QueryAPI", globalEnv._RescueContractQueue_QueryAPI)
end

return RescueContractQueueService
