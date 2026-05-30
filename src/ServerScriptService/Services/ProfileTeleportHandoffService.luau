--!strict

local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else (require :: any)("./ProfilePersistenceGateway")

local ProfileTeleportHandoffService: any = {}
local globalEnv: any = getfenv()

export type HandoffResult = {
	ok: boolean,
	operation: string,
	reason: string?,
	retryable: boolean?,
	handoffToken: string?,
	fallbackRoute: string?,
}

export type AdmissionIngressDiagnostics = {
	totalAttempts: number,
	primaryAttempts: number,
	primarySucceeded: number,
	primaryFailed: number,
	fallbackAttempts: number,
	fallbackSucceeded: number,
	fallbackFailed: number,
	lastPath: string,
	lastReason: string,
	lastPrimaryReason: string,
	lastFallbackReason: string,
}

local pendingHandoffByUserId: { [number]: { handoffToken: string }? } = {}
local releaseReadyCallbacksByUserId: { [number]: { (HandoffResult) -> () }? } = {}
local handoffCounter = 0
local admissionIngressDiagnostics: AdmissionIngressDiagnostics = {
	totalAttempts = 0,
	primaryAttempts = 0,
	primarySucceeded = 0,
	primaryFailed = 0,
	fallbackAttempts = 0,
	fallbackSucceeded = 0,
	fallbackFailed = 0,
	lastPath = "none",
	lastReason = "none",
	lastPrimaryReason = "none",
	lastFallbackReason = "none",
}

local function cloneAdmissionIngressDiagnostics(): AdmissionIngressDiagnostics
	return {
		totalAttempts = admissionIngressDiagnostics.totalAttempts,
		primaryAttempts = admissionIngressDiagnostics.primaryAttempts,
		primarySucceeded = admissionIngressDiagnostics.primarySucceeded,
		primaryFailed = admissionIngressDiagnostics.primaryFailed,
		fallbackAttempts = admissionIngressDiagnostics.fallbackAttempts,
		fallbackSucceeded = admissionIngressDiagnostics.fallbackSucceeded,
		fallbackFailed = admissionIngressDiagnostics.fallbackFailed,
		lastPath = admissionIngressDiagnostics.lastPath,
		lastReason = admissionIngressDiagnostics.lastReason,
		lastPrimaryReason = admissionIngressDiagnostics.lastPrimaryReason,
		lastFallbackReason = admissionIngressDiagnostics.lastFallbackReason,
	}
end

local function isValidUserId(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function getPlayerUserId(player: any): number?
	if type(player) ~= "table" and typeof(player) ~= "Instance" then
		return nil
	end

	local userId = player.UserId
	if not isValidUserId(userId) then
		return nil
	end

	return userId
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function makeResult(
	ok: boolean,
	operation: string,
	reason: string?,
	retryable: boolean?,
	handoffToken: string?,
	fallbackRoute: string?
): HandoffResult
	return {
		ok = ok,
		operation = operation,
		reason = reason,
		retryable = retryable,
		handoffToken = handoffToken,
		fallbackRoute = fallbackRoute,
	}
end

local function nextHandoffToken(userId: number): string
	handoffCounter += 1
	return string.format("handoff:%d:%d", userId, handoffCounter)
end

local function getPartyMatchmakingAdmissionQueryApi(): any?
	local queryApi = globalEnv._PartyMatchmakingAdmissionService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	if type((queryApi :: any).RequestPartyMatchAdmission) ~= "function" then
		return nil
	end

	return queryApi
end

local function getProfileTeleportAdmissionQueryApi(): any?
	local queryApi = globalEnv._ProfileTeleportAdmissionService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	if type((queryApi :: any).RequestTeleportHandoffAdmission) ~= "function" then
		return nil
	end

	return queryApi
end

local function isRetryableEnqueueReason(reason: string?): boolean
	return reason == "admission_queue_unavailable" or reason == "admission_enqueue_failed"
end

local function finalizeAdmissionResult(result: any): any
	if type(result) ~= "table" then
		return {
			accepted = false,
			reason = "admission_enqueue_failed",
		}
	end

	if result.accepted ~= true then
		return {
			accepted = false,
			reason = if type(result.reason) == "string" then result.reason else "admission_enqueue_failed",
		}
	end

	return {
		accepted = true,
		reason = if type(result.reason) == "string" then result.reason else "accepted",
	}
end

local function requestAdmissionViaProfileTeleportService(
	userId: number,
	handoffToken: string,
	targetRealmId: string
): any
	local admissionApi = getProfileTeleportAdmissionQueryApi()
	if type(admissionApi) ~= "table" then
		return {
			accepted = false,
			reason = "admission_queue_unavailable",
		}
	end

	local ok, result = pcall(function()
		return (admissionApi :: any).RequestTeleportHandoffAdmission({
			userId = userId,
			handoffToken = handoffToken,
			targetRealmId = targetRealmId,
		})
	end)

	if not ok then
		return {
			accepted = false,
			reason = "admission_enqueue_failed",
		}
	end

	return finalizeAdmissionResult(result)
end

local function requestAdmissionViaPartyMatchmakingService(
	userId: number,
	handoffToken: string,
	targetRealmId: string
): any
	local admissionApi = getPartyMatchmakingAdmissionQueryApi()
	if type(admissionApi) ~= "table" then
		return {
			accepted = false,
			reason = "admission_queue_unavailable",
		}
	end

	local ok, result = pcall(function()
		return (admissionApi :: any).RequestPartyMatchAdmission({
			operationId = handoffToken,
			partyId = string.format("handoff_party:%d:%s", userId, handoffToken),
			targetRealmId = targetRealmId,
			partyMemberUserIds = { userId },
		})
	end)

	if not ok then
		return {
			accepted = false,
			reason = "admission_enqueue_failed",
		}
	end

	return finalizeAdmissionResult(result)
end

local function requestAdmissionHandoff(userId: number, handoffToken: string, targetRealmId: string): any
	admissionIngressDiagnostics.totalAttempts += 1
	admissionIngressDiagnostics.primaryAttempts += 1
	admissionIngressDiagnostics.lastPath = "primary_profile_teleport"

	local primaryResult = requestAdmissionViaProfileTeleportService(userId, handoffToken, targetRealmId)
	if primaryResult.accepted == true then
		admissionIngressDiagnostics.primarySucceeded += 1
		admissionIngressDiagnostics.lastReason = "accepted"
		admissionIngressDiagnostics.lastPrimaryReason = "accepted"
		return primaryResult
	end

	admissionIngressDiagnostics.primaryFailed += 1
	local primaryReason = if type(primaryResult.reason) == "string" and primaryResult.reason ~= ""
		then primaryResult.reason
		else "admission_enqueue_failed"
	admissionIngressDiagnostics.lastReason = primaryReason
	admissionIngressDiagnostics.lastPrimaryReason = primaryReason

	if primaryReason ~= "admission_queue_unavailable" then
		return primaryResult
	end

	admissionIngressDiagnostics.fallbackAttempts += 1
	admissionIngressDiagnostics.lastPath = "fallback_party_matchmaking"

	local fallbackResult = requestAdmissionViaPartyMatchmakingService(userId, handoffToken, targetRealmId)
	if fallbackResult.accepted == true then
		admissionIngressDiagnostics.fallbackSucceeded += 1
		admissionIngressDiagnostics.lastReason = "accepted"
		admissionIngressDiagnostics.lastFallbackReason = "accepted"
		return fallbackResult
	end

	admissionIngressDiagnostics.fallbackFailed += 1
	local fallbackReason = if type(fallbackResult.reason) == "string" and fallbackResult.reason ~= ""
		then fallbackResult.reason
		else "admission_enqueue_failed"
	admissionIngressDiagnostics.lastReason = fallbackReason
	admissionIngressDiagnostics.lastFallbackReason = fallbackReason
	return fallbackResult
end

local function getLifecycleQueryApi(): any?
	local queryApi = globalEnv._ProfilePersistenceLifecycle_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function isOwnershipReady(userId: number): boolean
	local queryApi = getLifecycleQueryApi()
	if queryApi == nil or type(queryApi.IsPlayerOwnershipReady) ~= "function" then
		return false
	end

	local ok, ready = pcall(function()
		return queryApi.IsPlayerOwnershipReady(userId)
	end)
	if not ok then
		return false
	end

	return ready == true
end

local function notifyReleaseReadyCallbacks(userId: number, result: HandoffResult)
	local callbacks = releaseReadyCallbacksByUserId[userId]
	if callbacks == nil or #callbacks == 0 then
		return
	end

	for _, callback in ipairs(callbacks) do
		pcall(callback, result)
	end
end

function ProfileTeleportHandoffService.ResetForTests()
	pendingHandoffByUserId = {}
	releaseReadyCallbacksByUserId = {}
	handoffCounter = 0
	admissionIngressDiagnostics = {
		totalAttempts = 0,
		primaryAttempts = 0,
		primarySucceeded = 0,
		primaryFailed = 0,
		fallbackAttempts = 0,
		fallbackSucceeded = 0,
		fallbackFailed = 0,
		lastPath = "none",
		lastReason = "none",
		lastPrimaryReason = "none",
		lastFallbackReason = "none",
	}
end

function ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics(): AdmissionIngressDiagnostics
	return cloneAdmissionIngressDiagnostics()
end

function ProfileTeleportHandoffService.RegisterReleaseReadyCallback(userId: any, callback: any): boolean
	if not isValidUserId(userId) then
		return false
	end
	if type(callback) ~= "function" then
		return false
	end

	local callbacks = releaseReadyCallbacksByUserId[userId]
	if callbacks == nil then
		callbacks = {}
		releaseReadyCallbacksByUserId[userId] = callbacks
	end
	table.insert(callbacks, callback)

	local pending = pendingHandoffByUserId[userId]
	if pending ~= nil then
		pcall(callback, makeResult(true, "BeginCrossServerHandoff", nil, nil, pending.handoffToken, nil))
	end
	return true
end

function ProfileTeleportHandoffService.BeginCrossServerHandoff(player: any, context: any?): HandoffResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeResult(false, "BeginCrossServerHandoff", "invalid_player_user_id", false, nil, "safe_fallback")
	end

	local contextAny: any = context
	local targetRealmId = if type(contextAny) == "table" then contextAny.targetRealmId else nil
	if not isNonEmptyString(targetRealmId) then
		return makeResult(false, "BeginCrossServerHandoff", "target_realm_id_invalid", false, nil, "safe_fallback")
	end

	local releaseResult = ProfilePersistenceGateway.ReleasePlayerProfile(player)
	if not releaseResult.ok then
		return makeResult(
			false,
			"BeginCrossServerHandoff",
			"release_before_transfer_failed",
			releaseResult.retryable == true,
			nil,
			"safe_fallback"
		)
	end

	local handoffToken = nextHandoffToken(userId)
	local enqueueResult = requestAdmissionHandoff(userId, handoffToken, targetRealmId)
	if enqueueResult.accepted ~= true then
		return makeResult(
			false,
			"BeginCrossServerHandoff",
			enqueueResult.reason,
			isRetryableEnqueueReason(enqueueResult.reason),
			nil,
			"safe_fallback"
		)
	end

	pendingHandoffByUserId[userId] = {
		handoffToken = handoffToken,
	}

	local result = makeResult(true, "BeginCrossServerHandoff", nil, nil, handoffToken, nil)
	notifyReleaseReadyCallbacks(userId, result)
	return result
end

function ProfileTeleportHandoffService.ConfirmDestinationOwnership(userId: any, handoffToken: any?): HandoffResult
	if not isValidUserId(userId) then
		return makeResult(false, "ConfirmDestinationOwnership", "invalid_user_id", false, nil, "safe_fallback")
	end

	local pending = pendingHandoffByUserId[userId]
	local pendingToken: string? = nil
	if pending ~= nil then
		pendingToken = pending.handoffToken
	end

	if pendingToken ~= nil and handoffToken ~= nil and pendingToken ~= handoffToken then
		return makeResult(false, "ConfirmDestinationOwnership", "handoff_token_mismatch", false, nil, "safe_fallback")
	end

	if pendingToken == nil and type(handoffToken) ~= "string" then
		return makeResult(false, "ConfirmDestinationOwnership", "handoff_not_pending", false, nil, "safe_fallback")
	end

	if not isOwnershipReady(userId) then
		return makeResult(
			false,
			"ConfirmDestinationOwnership",
			"ownership_not_ready",
			true,
			if pendingToken ~= nil then pendingToken else handoffToken,
			nil
		)
	end

	pendingHandoffByUserId[userId] = nil
	releaseReadyCallbacksByUserId[userId] = nil
	return makeResult(
		true,
		"ConfirmDestinationOwnership",
		nil,
		nil,
		if pendingToken ~= nil then pendingToken else handoffToken,
		nil
	)
end

function ProfileTeleportHandoffService.CanSpawnGameplayForUserId(userId: any): boolean
	if not isValidUserId(userId) then
		return false
	end

	local pending = pendingHandoffByUserId[userId]
	if pending == nil then
		return true
	end

	if isOwnershipReady(userId) then
		pendingHandoffByUserId[userId] = nil
		releaseReadyCallbacksByUserId[userId] = nil
		return true
	end

	return false
end

globalEnv._ProfileTeleportHandoffService_QueryAPI = {
	BeginCrossServerHandoff = function(player: any, context: any?): HandoffResult
		return ProfileTeleportHandoffService.BeginCrossServerHandoff(player, context)
	end,
	ConfirmDestinationOwnership = function(userId: any, handoffToken: any?): HandoffResult
		return ProfileTeleportHandoffService.ConfirmDestinationOwnership(userId, handoffToken)
	end,
	CanSpawnGameplayForUserId = function(userId: any): boolean
		return ProfileTeleportHandoffService.CanSpawnGameplayForUserId(userId)
	end,
	RegisterReleaseReadyCallback = function(userId: any, callback: any): boolean
		return ProfileTeleportHandoffService.RegisterReleaseReadyCallback(userId, callback)
	end,
	GetAdmissionIngressDiagnostics = function(): AdmissionIngressDiagnostics
		return ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
	end,
	ResetForTests = function()
		ProfileTeleportHandoffService.ResetForTests()
	end,
}

return ProfileTeleportHandoffService
