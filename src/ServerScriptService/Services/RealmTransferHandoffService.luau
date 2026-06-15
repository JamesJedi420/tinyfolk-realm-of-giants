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

local RealmTransferSessionStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferSessionStore"))
	else (require :: any)("./RealmTransferSessionStore")

local RealmTransferHandoffService: any = {}
local globalEnv: any = getfenv()

export type HandoffDiagnostics = {
	totalBegins: number,
	acceptedBegins: number,
	rejectedBegins: number,
	totalConsumes: number,
	acceptedConsumes: number,
	rejectedConsumes: number,
	totalInvalidations: number,
	acceptedInvalidations: number,
	rejectedInvalidations: number,
	lastOperation: string,
	lastReason: string,
}

local tokenCounter = 0
local nowFn: (() -> number)? = nil
local sessionStore: any? = nil
local diagnostics: HandoffDiagnostics = {
	totalBegins = 0,
	acceptedBegins = 0,
	rejectedBegins = 0,
	totalConsumes = 0,
	acceptedConsumes = 0,
	rejectedConsumes = 0,
	totalInvalidations = 0,
	acceptedInvalidations = 0,
	rejectedInvalidations = 0,
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
		totalInvalidations = diagnostics.totalInvalidations,
		acceptedInvalidations = diagnostics.acceptedInvalidations,
		rejectedInvalidations = diagnostics.rejectedInvalidations,
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

local function getMemoryStoreAdapter(): any?
	local queryApi = globalEnv._MemoryStoreAdapter_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	return nil
end

local function resolveSessionStore(): any
	if sessionStore ~= nil then
		return sessionStore
	end
	sessionStore = RealmTransferSessionStore.Create({
		adapter = getMemoryStoreAdapter(),
		handoffState = RealmTransferHandoffState,
		structurePolicy = MemoryStoreStructurePolicy,
	})
	return sessionStore
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
	elseif operation == "invalidate" then
		diagnostics.totalInvalidations += 1
		if accepted then
			diagnostics.acceptedInvalidations += 1
		else
			diagnostics.rejectedInvalidations += 1
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
	if type(configAny) == "table" and type(configAny.store) == "table" then
		sessionStore = configAny.store
	end
end

function RealmTransferHandoffService.ResetForTests()
	tokenCounter = 0
	nowFn = nil
	sessionStore = nil
	diagnostics = {
		totalBegins = 0,
		acceptedBegins = 0,
		rejectedBegins = 0,
		totalConsumes = 0,
		acceptedConsumes = 0,
		rejectedConsumes = 0,
		totalInvalidations = 0,
		acceptedInvalidations = 0,
		rejectedInvalidations = 0,
		lastOperation = "none",
		lastReason = "reset",
	}
	local store = resolveSessionStore()
	if type(store) == "table" and type(store.ResetForTests) == "function" then
		store.ResetForTests()
	end
end

function RealmTransferHandoffService.GetSessionRecord(realmId: any): any
	if not isNonEmptyString(realmId) then
		return {
			accepted = false,
			reason = "realm_id_invalid",
			sessionRecord = nil,
		}
	end

	local storeResult = resolveSessionStore().GetSessionRecord(realmId)
	if storeResult.accepted ~= true then
		return {
			accepted = false,
			reason = storeResult.reason,
			sessionRecord = storeResult.sessionRecord,
		}
	end

	local record = storeResult.sessionRecord
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

	local beginResult: any = nil
	local storeResult = resolveSessionStore().UpdateSessionRecord(targetRealmId, function(currentRecord: any?)
		beginResult = RealmTransferHandoffState.BeginHandoff(currentRecord, {
			userId = userId,
			targetRealmId = targetRealmId,
			operationId = operationId,
			assignmentReason = input.assignmentReason,
			now = now,
			ttlSeconds = resolveTtlSeconds(),
			realmOwnerUserId = input.realmOwnerUserId,
		})
		return beginResult
	end)

	if storeResult.accepted ~= true or beginResult == nil or beginResult.accepted ~= true then
		if type(lockApi.Release) == "function" then
			lockApi.Release(operationId)
		end
		local reason = if type(beginResult) == "table" and type(beginResult.reason) == "string"
			then beginResult.reason
			else storeResult.reason
		recordDiagnostics("begin", false, reason)
		return {
			accepted = false,
			reason = reason,
			handoffToken = nil,
			handoffEntry = nil,
		}
	end

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
	local consumeResult: any = nil
	local storeResult = resolveSessionStore().UpdateSessionRecord(targetRealmId, function(currentRecord: any?)
		consumeResult = RealmTransferHandoffState.ConsumeHandoff(currentRecord, {
			userId = userId,
			handoffToken = handoffToken,
			now = now,
		})
		return consumeResult
	end)

	if storeResult.accepted ~= true then
		local reason = if type(consumeResult) == "table" and type(consumeResult.reason) == "string"
			then consumeResult.reason
			else storeResult.reason
		if reason == "session_record_missing" then
			recordDiagnostics("consume", false, reason)
			return {
				accepted = false,
				reason = reason,
				handoffEntry = nil,
			}
		end
		recordDiagnostics("consume", false, reason)
		return {
			accepted = false,
			reason = reason,
			handoffEntry = if type(consumeResult) == "table" then consumeResult.handoffEntry else nil,
		}
	end

	if consumeResult == nil or consumeResult.accepted ~= true then
		local reason = if type(consumeResult) == "table" and type(consumeResult.reason) == "string"
			then consumeResult.reason
			else "handoff_consume_failed"
		recordDiagnostics("consume", false, reason)
		return {
			accepted = false,
			reason = reason,
			handoffEntry = if type(consumeResult) == "table" then consumeResult.handoffEntry else nil,
		}
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

function RealmTransferHandoffService.InvalidateHandoffOnAbort(input: any): any
	if type(input) ~= "table" then
		recordDiagnostics("invalidate", false, "handoff_input_invalid")
		return {
			accepted = false,
			reason = "handoff_input_invalid",
			handoffEntry = nil,
		}
	end

	local handoffToken = input.handoffToken
	local targetRealmId = input.targetRealmId
	if not isNonEmptyString(handoffToken) then
		recordDiagnostics("invalidate", false, "handoff_token_invalid")
		return {
			accepted = false,
			reason = "handoff_token_invalid",
			handoffEntry = nil,
		}
	end
	if not isNonEmptyString(targetRealmId) then
		recordDiagnostics("invalidate", false, "handoff_target_realm_invalid")
		return {
			accepted = false,
			reason = "handoff_target_realm_invalid",
			handoffEntry = nil,
		}
	end

	local now = readNow(input.now)
	local invalidateResult: any = nil
	local storeResult = resolveSessionStore().UpdateSessionRecord(targetRealmId, function(currentRecord: any?)
		invalidateResult = RealmTransferHandoffState.InvalidateHandoff(currentRecord, {
			handoffToken = handoffToken,
			now = now,
		})
		return invalidateResult
	end)

	if storeResult.accepted ~= true then
		local reason = if type(invalidateResult) == "table" and type(invalidateResult.reason) == "string"
			then invalidateResult.reason
			else storeResult.reason
		if reason == "session_record_missing" or reason == "handoff_token_not_found" then
			recordDiagnostics("invalidate", true, "accepted")
			local lockApi = getTransferLockQueryApi()
			if lockApi ~= nil and type(lockApi.Release) == "function" then
				lockApi.Release(handoffToken)
			end
			return {
				accepted = true,
				reason = "accepted",
				handoffEntry = nil,
			}
		end
		recordDiagnostics("invalidate", false, reason)
		return {
			accepted = false,
			reason = reason,
			handoffEntry = nil,
		}
	end

	if invalidateResult == nil or invalidateResult.accepted ~= true then
		local reason = if type(invalidateResult) == "table" and type(invalidateResult.reason) == "string"
			then invalidateResult.reason
			else "handoff_invalidate_failed"
		if reason == "session_record_missing" or reason == "handoff_token_not_found" then
			recordDiagnostics("invalidate", true, "accepted")
			local lockApi = getTransferLockQueryApi()
			if lockApi ~= nil and type(lockApi.Release) == "function" then
				lockApi.Release(handoffToken)
			end
			return {
				accepted = true,
				reason = "accepted",
				handoffEntry = nil,
			}
		end
		recordDiagnostics("invalidate", false, reason)
		return {
			accepted = false,
			reason = reason,
			handoffEntry = if type(invalidateResult) == "table" then invalidateResult.handoffEntry else nil,
		}
	end

	local lockApi = getTransferLockQueryApi()
	if lockApi ~= nil and type(lockApi.Release) == "function" then
		lockApi.Release(handoffToken)
	end

	recordDiagnostics("invalidate", true, "accepted")
	return {
		accepted = true,
		reason = "accepted",
		handoffEntry = invalidateResult.handoffEntry,
	}
end

function RealmTransferHandoffService.ResolveExpiredSession(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "handoff_input_invalid",
			resolution = "invalid_input",
			handoffEntry = nil,
		}
	end

	local handoffToken = input.handoffToken
	local targetRealmId = input.targetRealmId
	if not isNonEmptyString(handoffToken) then
		return {
			accepted = false,
			reason = "handoff_token_invalid",
			resolution = "invalid_token",
			handoffEntry = nil,
		}
	end
	if not isNonEmptyString(targetRealmId) then
		return {
			accepted = false,
			reason = "handoff_target_realm_invalid",
			resolution = "invalid_target",
			handoffEntry = nil,
		}
	end

	local now = readNow(input.now)
	local sessionResult = resolveSessionStore().GetSessionRecord(targetRealmId)
	if sessionResult.accepted ~= true or sessionResult.sessionRecord == nil then
		return {
			accepted = true,
			reason = "session_record_missing",
			resolution = "pending_recovery_authority",
			handoffEntry = nil,
		}
	end

	local record = sessionResult.sessionRecord
	local entryBeforePrune = RealmTransferHandoffState.GetHandoffEntry(record, handoffToken)
	local prunedRecord = RealmTransferHandoffState.PruneExpired(record, now)
	local entryAfterPrune = RealmTransferHandoffState.GetHandoffEntry(prunedRecord, handoffToken)

	if entryBeforePrune ~= nil and entryAfterPrune == nil and entryBeforePrune.expiresAt <= now then
		resolveSessionStore().UpdateSessionRecord(targetRealmId, function(_currentRecord: any?)
			return {
				accepted = true,
				reason = "accepted",
				sessionRecord = prunedRecord,
			}
		end)
		return {
			accepted = true,
			reason = "handoff_token_expired",
			resolution = "pending_recovery_authority",
			handoffEntry = entryBeforePrune,
		}
	end

	if entryAfterPrune == nil then
		return {
			accepted = false,
			reason = "handoff_token_not_found",
			resolution = "safe_fallback",
			handoffEntry = nil,
		}
	end

	if entryAfterPrune.expiresAt <= now then
		return {
			accepted = true,
			reason = "handoff_token_expired",
			resolution = "pending_recovery_authority",
			handoffEntry = entryAfterPrune,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		resolution = "session_record_authority",
		handoffEntry = entryAfterPrune,
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
	InvalidateHandoffOnAbort = function(input: any): any
		return RealmTransferHandoffService.InvalidateHandoffOnAbort(input)
	end,
	ResolveExpiredSession = function(input: any): any
		return RealmTransferHandoffService.ResolveExpiredSession(input)
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
