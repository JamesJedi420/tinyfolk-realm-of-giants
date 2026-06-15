--!strict

local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local RealmTransferHandoffState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTransferHandoffState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferHandoffState")

local RealmTransferHandoffService: any = {}
local globalEnv: any = getfenv()

export type HandoffDiagnostics = {
	totalBegins: number,
	acceptedBegins: number,
	rejectedBegins: number,
	totalConsumes: number,
	acceptedConsumes: number,
	rejectedConsumes: number,
	lastOperation: string,
	lastReason: string,
}

local sessionRecordsByRealmId: { [string]: RealmTransferHandoffState.SessionRecord? } = {}
local tokenCounter = 0
local nowFn: (() -> number)? = nil
local diagnostics: HandoffDiagnostics = {
	totalBegins = 0,
	acceptedBegins = 0,
	rejectedBegins = 0,
	totalConsumes = 0,
	acceptedConsumes = 0,
	rejectedConsumes = 0,
	lastOperation = "none",
	lastReason = "not_started",
}

local function cloneDiagnostics(): HandoffDiagnostics
	return {
		totalBegins = diagnostics.totalBegins,
		acceptedBegins = diagnostics.acceptedBegins,
		rejectedBegins = diagnostics.rejectedBegins,
		totalConsumes = diagnostics.totalConsumes,
		acceptedConsumes = diagnostics.acceptedConsumes,
		rejectedConsumes = diagnostics.rejectedConsumes,
		lastOperation = diagnostics.lastOperation,
		lastReason = diagnostics.lastReason,
	}
end

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
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
	return os.time()
end

local function resolveTtlSeconds(): number
	local structurePolicyAny: any = MemoryStoreStructurePolicy
	if type(structurePolicyAny) == "table" and type((structurePolicyAny :: any).ResolveExpiration) == "function" then
		local ttlResultAny: any = (structurePolicyAny :: any).ResolveExpiration("realmTransferSessions")
		if type(ttlResultAny) == "table" and ttlResultAny.ok == true then
			local resolvedTtlSeconds: any = ttlResultAny.ttlSeconds
			if isFiniteNumber(resolvedTtlSeconds) and resolvedTtlSeconds > 0 then
				return resolvedTtlSeconds :: number
			end
		end
	end
	return RealmTransferHandoffState.DEFAULT_TOKEN_TTL_SECONDS
end

local function getTransferLockQueryApi(): any?
	local queryApi = globalEnv._TransferLock_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

local function recordDiagnostics(operation: string, accepted: boolean, reason: string)
	diagnostics.lastOperation = operation
	diagnostics.lastReason = reason
	if operation == "begin" then
		diagnostics.totalBegins += 1
		if accepted then
			diagnostics.acceptedBegins += 1
		else
			diagnostics.rejectedBegins += 1
		end
	elseif operation == "consume" then
		diagnostics.totalConsumes += 1
		if accepted then
			diagnostics.acceptedConsumes += 1
		else
			diagnostics.rejectedConsumes += 1
		end
	end
end

local function nextGeneratedToken(userId: number): string
	tokenCounter += 1
	return RealmTransferHandoffState.FormatHandoffToken(userId, tokenCounter)
end

function RealmTransferHandoffService.ConfigureForTests(config: any?)
	local configAny: any = config
	nowFn = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
end

function RealmTransferHandoffService.ResetForTests()
	sessionRecordsByRealmId = {}
	tokenCounter = 0
	nowFn = nil
	diagnostics = {
		totalBegins = 0,
		acceptedBegins = 0,
		rejectedBegins = 0,
		totalConsumes = 0,
		acceptedConsumes = 0,
		rejectedConsumes = 0,
		lastOperation = "none",
		lastReason = "reset",
	}
end

function RealmTransferHandoffService.GetSessionRecord(realmId: any): any
	if not isNonEmptyString(realmId) then
		return {
			accepted = false,
			reason = "realm_id_invalid",
			sessionRecord = nil,
		}
	end

	local record = sessionRecordsByRealmId[realmId]
	if record == nil then
		return {
			accepted = false,
			reason = "session_record_missing",
			sessionRecord = nil,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		sessionRecord = record,
	}
end

function RealmTransferHandoffService.BeginHandoff(input: any): any
	if type(input) ~= "table" then
		recordDiagnostics("begin", false, "handoff_input_invalid")
		return {
			accepted = false,
			reason = "handoff_input_invalid",
			handoffToken = nil,
			handoffEntry = nil,
		}
	end

	local userId = input.userId
	local targetRealmId = input.targetRealmId
	if not isPositiveInteger(userId) then
		recordDiagnostics("begin", false, "handoff_user_id_invalid")
		return {
			accepted = false,
			reason = "handoff_user_id_invalid",
			handoffToken = nil,
			handoffEntry = nil,
		}
	end
	if not isNonEmptyString(targetRealmId) then
		recordDiagnostics("begin", false, "handoff_target_realm_invalid")
		return {
			accepted = false,
			reason = "handoff_target_realm_invalid",
			handoffToken = nil,
			handoffEntry = nil,
		}
	end

	local now = readNow(input.now)
	local operationId = if isNonEmptyString(input.operationId) then input.operationId else nextGeneratedToken(userId)
	local lockApi = getTransferLockQueryApi()
	if lockApi == nil or type(lockApi.TryAcquire) ~= "function" then
		recordDiagnostics("begin", false, "transfer_lock_unavailable")
		return {
			accepted = false,
			reason = "transfer_lock_unavailable",
			handoffToken = nil,
			handoffEntry = nil,
		}
	end

	local lockAcquired = lockApi.TryAcquire(operationId, now)
	if lockAcquired ~= true then
		recordDiagnostics("begin", false, "transfer_lock_active")
		return {
			accepted = false,
			reason = "transfer_lock_active",
			handoffToken = nil,
			handoffEntry = nil,
		}
	end

	local currentRecord = sessionRecordsByRealmId[targetRealmId]
	local beginResult = RealmTransferHandoffState.BeginHandoff(currentRecord, {
		userId = userId,
		targetRealmId = targetRealmId,
		operationId = operationId,
		assignmentReason = input.assignmentReason,
		now = now,
		ttlSeconds = resolveTtlSeconds(),
		realmOwnerUserId = input.realmOwnerUserId,
	})
	if beginResult.accepted ~= true or beginResult.sessionRecord == nil then
		if type(lockApi.Release) == "function" then
			lockApi.Release(operationId)
		end
		recordDiagnostics("begin", false, beginResult.reason)
		return {
			accepted = false,
			reason = beginResult.reason,
			handoffToken = nil,
			handoffEntry = nil,
		}
	end

	sessionRecordsByRealmId[targetRealmId] = beginResult.sessionRecord
	recordDiagnostics("begin", true, "accepted")
	return {
		accepted = true,
		reason = "accepted",
		handoffToken = operationId,
		handoffEntry = beginResult.handoffEntry,
	}
end

function RealmTransferHandoffService.ConsumeHandoffOnArrival(input: any): any
	if type(input) ~= "table" then
		recordDiagnostics("consume", false, "handoff_input_invalid")
		return {
			accepted = false,
			reason = "handoff_input_invalid",
			handoffEntry = nil,
		}
	end

	local userId = input.userId
	local handoffToken = input.handoffToken
	local targetRealmId = input.targetRealmId
	if not isPositiveInteger(userId) then
		recordDiagnostics("consume", false, "handoff_user_id_invalid")
		return {
			accepted = false,
			reason = "handoff_user_id_invalid",
			handoffEntry = nil,
		}
	end
	if not isNonEmptyString(handoffToken) then
		recordDiagnostics("consume", false, "handoff_token_invalid")
		return {
			accepted = false,
			reason = "handoff_token_invalid",
			handoffEntry = nil,
		}
	end
	if not isNonEmptyString(targetRealmId) then
		recordDiagnostics("consume", false, "handoff_target_realm_invalid")
		return {
			accepted = false,
			reason = "handoff_target_realm_invalid",
			handoffEntry = nil,
		}
	end

	local now = readNow(input.now)
	local currentRecord = sessionRecordsByRealmId[targetRealmId]
	local consumeResult = RealmTransferHandoffState.ConsumeHandoff(currentRecord, {
		userId = userId,
		handoffToken = handoffToken,
		now = now,
	})
	if consumeResult.accepted ~= true then
		recordDiagnostics("consume", false, consumeResult.reason)
		return {
			accepted = false,
			reason = consumeResult.reason,
			handoffEntry = consumeResult.handoffEntry,
		}
	end

	if consumeResult.sessionRecord ~= nil then
		sessionRecordsByRealmId[targetRealmId] = consumeResult.sessionRecord
	end

	local lockApi = getTransferLockQueryApi()
	if lockApi ~= nil and type(lockApi.Release) == "function" then
		lockApi.Release(handoffToken)
	end

	recordDiagnostics("consume", true, "accepted")
	return {
		accepted = true,
		reason = "accepted",
		handoffEntry = consumeResult.handoffEntry,
	}
end

function RealmTransferHandoffService.GetDiagnostics(): HandoffDiagnostics
	return cloneDiagnostics()
end

globalEnv._RealmTransferHandoffService_QueryAPI = {
	BeginHandoff = function(input: any): any
		return RealmTransferHandoffService.BeginHandoff(input)
	end,
	ConsumeHandoffOnArrival = function(input: any): any
		return RealmTransferHandoffService.ConsumeHandoffOnArrival(input)
	end,
	GetSessionRecord = function(realmId: any): any
		return RealmTransferHandoffService.GetSessionRecord(realmId)
	end,
	GetDiagnostics = function(): HandoffDiagnostics
		return RealmTransferHandoffService.GetDiagnostics()
	end,
	ConfigureForTests = function(config: any?)
		RealmTransferHandoffService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		RealmTransferHandoffService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RealmTransferHandoffService_QueryAPI", globalEnv._RealmTransferHandoffService_QueryAPI)
end

return RealmTransferHandoffService
