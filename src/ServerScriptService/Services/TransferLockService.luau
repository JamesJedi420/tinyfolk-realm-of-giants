--!strict

local MemoryStoreStructurePolicy: any = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local TransferLockService: any = {}
local globalEnv: any = getfenv()

local DEFAULT_TTL_SECONDS = 90

type LockEntry = {
	expiresAt: number,
}

type Diagnostics = {
	acquireAttempts: number,
	acquireSucceeded: number,
	acquireFailed: number,
	releaseAttempts: number,
	releaseSucceeded: number,
	failedAcquireCount: number,
	activeLockCount: number,
	lastReason: string,
	lastOperationId: string?,
}

local activeLocksByOperationId: { [string]: LockEntry? } = {}
local nowFn: (() -> number)? = nil
local diagnostics: Diagnostics = {
	acquireAttempts = 0,
	acquireSucceeded = 0,
	acquireFailed = 0,
	releaseAttempts = 0,
	releaseSucceeded = 0,
	failedAcquireCount = 0,
	activeLockCount = 0,
	lastReason = "not_started",
	lastOperationId = nil,
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

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function readNow(at: any?): number
	if isFiniteNumber(at) then
		return at :: number
	end
	if type(nowFn) == "function" then
		local value = nowFn()
		if isFiniteNumber(value) then
			return value
		end
	end
	return os.clock()
end

local function resolveTtlSeconds(config: any?): number
	local configuredTtl = if type(config) == "table" then (config :: any).ttlSeconds else nil
	if isFiniteNumber(configuredTtl) and configuredTtl > 0 then
		return configuredTtl
	end

	local structurePolicyAny: any = MemoryStoreStructurePolicy
	if type(structurePolicyAny) == "table" and type((structurePolicyAny :: any).ResolveExpiration) == "function" then
		local ttlResultAny: any = (structurePolicyAny :: any).ResolveExpiration("transferLocks")
		if type(ttlResultAny) == "table" and ttlResultAny.ok == true then
			local ttlTable: any = ttlResultAny
			local resolvedTtlSeconds: any = ttlTable.ttlSeconds
			if isFiniteNumber(resolvedTtlSeconds) and resolvedTtlSeconds > 0 then
				return resolvedTtlSeconds :: number
			end
		end
	end

	return DEFAULT_TTL_SECONDS
end

local function pruneExpired(at: number)
	local removedCount = 0
	for operationId, entry in pairs(activeLocksByOperationId) do
		if entry ~= nil and (entry :: LockEntry).expiresAt <= at then
			activeLocksByOperationId[operationId] = nil
			removedCount += 1
		end
	end
	if removedCount > 0 then
		diagnostics.activeLockCount = math.max(0, diagnostics.activeLockCount - removedCount)
	end
end

local function cloneDiagnostics(): Diagnostics
	return {
		acquireAttempts = diagnostics.acquireAttempts,
		acquireSucceeded = diagnostics.acquireSucceeded,
		acquireFailed = diagnostics.acquireFailed,
		releaseAttempts = diagnostics.releaseAttempts,
		releaseSucceeded = diagnostics.releaseSucceeded,
		failedAcquireCount = diagnostics.failedAcquireCount,
		activeLockCount = diagnostics.activeLockCount,
		lastReason = diagnostics.lastReason,
		lastOperationId = diagnostics.lastOperationId,
	}
end

function TransferLockService.ConfigureForTests(config: any?)
	local configAny: any = config
	nowFn = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
end

function TransferLockService.ResetForTests()
	activeLocksByOperationId = {}
	nowFn = nil
	diagnostics = {
		acquireAttempts = 0,
		acquireSucceeded = 0,
		acquireFailed = 0,
		releaseAttempts = 0,
		releaseSucceeded = 0,
		failedAcquireCount = 0,
		activeLockCount = 0,
		lastReason = "reset",
		lastOperationId = nil,
	}
end

function TransferLockService.TryAcquire(operationId: any, at: any?): boolean
	diagnostics.acquireAttempts += 1
	diagnostics.lastOperationId = if isNonEmptyString(operationId) then operationId else nil
	if not isNonEmptyString(operationId) then
		diagnostics.acquireFailed += 1
		diagnostics.failedAcquireCount += 1
		diagnostics.lastReason = "operation_id_invalid"
		return false
	end

	local resolvedNow = readNow(at)
	pruneExpired(resolvedNow)

	if activeLocksByOperationId[operationId] ~= nil then
		diagnostics.acquireFailed += 1
		diagnostics.failedAcquireCount += 1
		diagnostics.lastReason = "transfer_lock_active"
		return false
	end

	local ttlSeconds = resolveTtlSeconds(nil)
	activeLocksByOperationId[operationId] = {
		expiresAt = resolvedNow + ttlSeconds,
	}
	diagnostics.acquireSucceeded += 1
	diagnostics.activeLockCount += 1
	diagnostics.lastReason = "accepted"
	return true
end

function TransferLockService.Release(operationId: any)
	diagnostics.releaseAttempts += 1
	diagnostics.lastOperationId = if isNonEmptyString(operationId) then operationId else nil
	if not isNonEmptyString(operationId) then
		diagnostics.lastReason = "operation_id_invalid"
		return
	end
	if activeLocksByOperationId[operationId] ~= nil then
		diagnostics.releaseSucceeded += 1
		diagnostics.activeLockCount = math.max(0, diagnostics.activeLockCount - 1)
		diagnostics.lastReason = "accepted"
	else
		diagnostics.lastReason = "lock_not_found"
	end
	activeLocksByOperationId[operationId] = nil
end

function TransferLockService.GetDiagnostics(): Diagnostics
	return cloneDiagnostics()
end

globalEnv._TransferLock_QueryAPI = {
	TryAcquire = function(operationId: any): boolean
		return TransferLockService.TryAcquire(operationId)
	end,
	Release = function(operationId: any)
		TransferLockService.Release(operationId)
	end,
	ConfigureForTests = function(config: any?)
		TransferLockService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		TransferLockService.ResetForTests()
	end,
	GetDiagnostics = function(): Diagnostics
		return TransferLockService.GetDiagnostics()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_TransferLock_QueryAPI", globalEnv._TransferLock_QueryAPI)
end

return TransferLockService
