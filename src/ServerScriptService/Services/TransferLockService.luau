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

local activeLocksByOperationId: { [string]: LockEntry? } = {}
local nowFn: (() -> number)? = nil

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
	for operationId, entry in pairs(activeLocksByOperationId) do
		if entry ~= nil and (entry :: LockEntry).expiresAt <= at then
			activeLocksByOperationId[operationId] = nil
		end
	end
end

function TransferLockService.ConfigureForTests(config: any?)
	local configAny: any = config
	nowFn = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
end

function TransferLockService.ResetForTests()
	activeLocksByOperationId = {}
	nowFn = nil
end

function TransferLockService.TryAcquire(operationId: any, at: any?): boolean
	if not isNonEmptyString(operationId) then
		return false
	end

	local resolvedNow = readNow(at)
	pruneExpired(resolvedNow)

	if activeLocksByOperationId[operationId] ~= nil then
		return false
	end

	local ttlSeconds = resolveTtlSeconds(nil)
	activeLocksByOperationId[operationId] = {
		expiresAt = resolvedNow + ttlSeconds,
	}
	return true
end

function TransferLockService.Release(operationId: any)
	if not isNonEmptyString(operationId) then
		return
	end
	activeLocksByOperationId[operationId] = nil
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
}

if type(_G) == "table" then
	rawset(_G, "_TransferLock_QueryAPI", globalEnv._TransferLock_QueryAPI)
end

return TransferLockService
