--!strict

local MemoryStoreCallObservability: any = {}

local LOG_COALESCE_SECONDS = 30

type Diagnostics = {
	throttledCount: number,
	partitionLimitCount: number,
	otherFailureCount: number,
	totalFailures: number,
	lastReason: string,
	lastOperation: string?,
	lastDetail: string?,
}

local diagnostics: Diagnostics = {
	throttledCount = 0,
	partitionLimitCount = 0,
	otherFailureCount = 0,
	totalFailures = 0,
	lastReason = "not_started",
	lastOperation = nil,
	lastDetail = nil,
}

local lastLoggedAtByKey: { [string]: number } = {}
local warnFn: ((string) -> ())? = nil
local nowFn: (() -> number)? = nil

local function readNow(): number
	if type(nowFn) == "function" then
		local value = nowFn()
		if type(value) == "number" and value == value then
			return value
		end
	end
	return os.clock()
end

local function emitWarn(message: string)
	if type(warnFn) == "function" then
		warnFn(message)
		return
	end
	warn(message)
end

local function cloneDiagnostics(): Diagnostics
	return {
		throttledCount = diagnostics.throttledCount,
		partitionLimitCount = diagnostics.partitionLimitCount,
		otherFailureCount = diagnostics.otherFailureCount,
		totalFailures = diagnostics.totalFailures,
		lastReason = diagnostics.lastReason,
		lastOperation = diagnostics.lastOperation,
		lastDetail = diagnostics.lastDetail,
	}
end

function MemoryStoreCallObservability.ClassifyError(err: any): string
	local message = string.lower(tostring(err))
	if string.find(message, "throttl", 1, true) ~= nil then
		return "memory_store_throttled"
	end
	if
		string.find(message, "partition", 1, true) ~= nil
		and (
			string.find(message, "limit", 1, true) ~= nil
			or string.find(message, "full", 1, true) ~= nil
			or string.find(message, "capacity", 1, true) ~= nil
		)
	then
		return "memory_store_partition_limit"
	end
	return "memory_store_other"
end

function MemoryStoreCallObservability.ConfigureForTests(config: any?)
	local configAny: any = config
	warnFn = if type(configAny) == "table" and type(configAny.warn) == "function" then configAny.warn else nil
	nowFn = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
end

function MemoryStoreCallObservability.ResetForTests()
	diagnostics = {
		throttledCount = 0,
		partitionLimitCount = 0,
		otherFailureCount = 0,
		totalFailures = 0,
		lastReason = "reset",
		lastOperation = nil,
		lastDetail = nil,
	}
	lastLoggedAtByKey = {}
	warnFn = nil
	nowFn = nil
end

function MemoryStoreCallObservability.RecordFailure(operation: any, structureHint: any?, err: any)
	local operationName = if type(operation) == "string" and operation ~= "" then operation else "unknown"
	local reason = MemoryStoreCallObservability.ClassifyError(err)
	local detail = tostring(err)

	diagnostics.totalFailures += 1
	diagnostics.lastReason = reason
	diagnostics.lastOperation = operationName
	diagnostics.lastDetail = detail

	if reason == "memory_store_throttled" then
		diagnostics.throttledCount += 1
	elseif reason == "memory_store_partition_limit" then
		diagnostics.partitionLimitCount += 1
	else
		diagnostics.otherFailureCount += 1
	end

	local logKey = string.format("%s:%s", operationName, reason)
	local now = readNow()
	local lastLoggedAt = lastLoggedAtByKey[logKey]
	if type(lastLoggedAt) == "number" and (now - lastLoggedAt) < LOG_COALESCE_SECONDS then
		return
	end
	lastLoggedAtByKey[logKey] = now

	local structureSuffix = if type(structureHint) == "string" and structureHint ~= ""
		then string.format(" structure=%s", structureHint)
		else ""
	emitWarn(
		string.format(
			"[MemoryStoreCallObservability] operation=%s reason=%s%s detail=%s",
			operationName,
			reason,
			structureSuffix,
			detail
		)
	)
end

function MemoryStoreCallObservability.GetDiagnostics(): Diagnostics
	return cloneDiagnostics()
end

return MemoryStoreCallObservability
