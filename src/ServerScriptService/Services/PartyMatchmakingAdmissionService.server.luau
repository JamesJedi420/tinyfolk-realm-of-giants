--!nocheck

local AdmissionQueueProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("AdmissionQueueProducer"))
	else (require :: any)("./AdmissionQueueProducer")

local globalEnv: any = getfenv()

local DEFAULT_EXPIRATION_SECONDS = 600

local queryApiOverride: any = nil
local nowFnOverride: (() -> number)? = nil
local targetRealmResolverOverride: any = nil

type AdmissionDiagnostics = {
	totalRequests: number,
	resolverAttempts: number,
	resolverSucceeded: number,
	resolverFailed: number,
	resolverFallbackDirectTargetUsed: number,
	enqueueAttempts: number,
	enqueueSucceeded: number,
	enqueueFailed: number,
	lastEntryType: string,
	lastReason: string,
	lastResolverReason: string,
	lastEnqueueReason: string,
	lastResolverPath: string,
}

local admissionDiagnostics: AdmissionDiagnostics = {
	totalRequests = 0,
	resolverAttempts = 0,
	resolverSucceeded = 0,
	resolverFailed = 0,
	resolverFallbackDirectTargetUsed = 0,
	enqueueAttempts = 0,
	enqueueSucceeded = 0,
	enqueueFailed = 0,
	lastEntryType = "none",
	lastReason = "none",
	lastResolverReason = "none",
	lastEnqueueReason = "none",
	lastResolverPath = "none",
}

local function cloneAdmissionDiagnostics(): AdmissionDiagnostics
	return {
		totalRequests = admissionDiagnostics.totalRequests,
		resolverAttempts = admissionDiagnostics.resolverAttempts,
		resolverSucceeded = admissionDiagnostics.resolverSucceeded,
		resolverFailed = admissionDiagnostics.resolverFailed,
		resolverFallbackDirectTargetUsed = admissionDiagnostics.resolverFallbackDirectTargetUsed,
		enqueueAttempts = admissionDiagnostics.enqueueAttempts,
		enqueueSucceeded = admissionDiagnostics.enqueueSucceeded,
		enqueueFailed = admissionDiagnostics.enqueueFailed,
		lastEntryType = admissionDiagnostics.lastEntryType,
		lastReason = admissionDiagnostics.lastReason,
		lastResolverReason = admissionDiagnostics.lastResolverReason,
		lastEnqueueReason = admissionDiagnostics.lastEnqueueReason,
		lastResolverPath = admissionDiagnostics.lastResolverPath,
	}
end

local function resolveNow(): number
	if type(nowFnOverride) == "function" then
		local at = nowFnOverride()
		if type(at) == "number" and at == at and at ~= math.huge and at ~= -math.huge then
			return at
		end
	end
	return os.clock()
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function getRealmAdmissionQueueQueryApi(): any?
	if queryApiOverride ~= nil then
		return queryApiOverride
	end

	local envAny: any = globalEnv
	if type(envAny) ~= "table" then
		return nil
	end

	local queryApi = envAny._RealmAdmissionQueue_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getPartyMatchmakingRealmResolverQueryApi(): any?
	if targetRealmResolverOverride ~= nil then
		return targetRealmResolverOverride
	end

	local envAny: any = globalEnv
	if type(envAny) ~= "table" then
		return nil
	end

	local queryApi = envAny._PartyMatchmakingRealmResolver_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getRealmPermissionQueryApi(): any?
	local envAny: any = globalEnv
	if type(envAny) ~= "table" then
		return nil
	end

	local queryApi = envAny._RealmPermissionService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end

	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_RealmPermissionService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end

	return nil
end

local function validateRealmAdmissionPermission(
	targetRealmId: string,
	entryType: string?,
	requesterUserIds: { number }?
): (boolean, string?)
	local permissionApi = getRealmPermissionQueryApi()
	if type(permissionApi) ~= "table" or type(permissionApi.EvaluateAdmissionForRealm) ~= "function" then
		return true, nil
	end

	local ok, result = pcall(function()
		return permissionApi.EvaluateAdmissionForRealm(targetRealmId, {
			entryType = entryType,
			requesterUserIds = requesterUserIds,
		})
	end)
	if not ok or type(result) ~= "table" then
		return true, nil
	end
	if result.accepted == true then
		return true, nil
	end

	return false, if type(result.reason) == "string" then result.reason else "realm_access_denied"
end

local function resolveTargetRealmId(input: any): (string?, string?)
	if type(input) ~= "table" then
		admissionDiagnostics.lastResolverPath = "invalid_request"
		admissionDiagnostics.lastResolverReason = "request_invalid"
		return nil, "request_invalid"
	end

	admissionDiagnostics.resolverAttempts += 1

	local resolver = getPartyMatchmakingRealmResolverQueryApi()
	if type(resolver) ~= "table" or type((resolver :: any).ResolveTargetRealmId) ~= "function" then
		if isNonEmptyString(input.targetRealmId) then
			admissionDiagnostics.resolverSucceeded += 1
			admissionDiagnostics.resolverFallbackDirectTargetUsed += 1
			admissionDiagnostics.lastResolverPath = "direct_target"
			admissionDiagnostics.lastResolverReason = "accepted"
			return input.targetRealmId, nil
		end
		admissionDiagnostics.resolverFailed += 1
		admissionDiagnostics.lastResolverPath = "resolver_unavailable"
		admissionDiagnostics.lastResolverReason = "target_realm_unavailable"
		return nil, "target_realm_unavailable"
	end

	local ok, result = pcall(function()
		return (resolver :: any).ResolveTargetRealmId(input)
	end)
	if not ok or type(result) ~= "table" then
		admissionDiagnostics.resolverFailed += 1
		admissionDiagnostics.lastResolverPath = "resolver_threw"
		admissionDiagnostics.lastResolverReason = "target_realm_unavailable"
		return nil, "target_realm_unavailable"
	end
	if result.accepted ~= true then
		admissionDiagnostics.resolverFailed += 1
		admissionDiagnostics.lastResolverPath = "resolver_rejected"
		if type(result.reason) == "string" then
			admissionDiagnostics.lastResolverReason = result.reason
			return nil, result.reason
		end
		admissionDiagnostics.lastResolverReason = "target_realm_unavailable"
		return nil, "target_realm_unavailable"
	end

	if not isNonEmptyString(result.targetRealmId) then
		admissionDiagnostics.resolverFailed += 1
		admissionDiagnostics.lastResolverPath = "resolver_invalid"
		admissionDiagnostics.lastResolverReason = "target_realm_invalid"
		return nil, "target_realm_invalid"
	end

	admissionDiagnostics.resolverSucceeded += 1
	admissionDiagnostics.lastResolverPath = "resolver_query"
	admissionDiagnostics.lastResolverReason = "accepted"
	return result.targetRealmId, nil
end

local function resolveMemberUserIds(input: any): any
	if type(input) ~= "table" then
		return nil
	end
	if type(input.partyMemberUserIds) == "table" then
		return input.partyMemberUserIds
	end
	if type(input.memberUserIds) == "table" then
		return input.memberUserIds
	end
	return nil
end

local admissionProducer = AdmissionQueueProducer.Create({
	defaultExpirationSeconds = DEFAULT_EXPIRATION_SECONDS,
	now = function(): number
		return resolveNow()
	end,
	queryApiResolver = function()
		return getRealmAdmissionQueueQueryApi()
	end,
})

local PartyMatchmakingAdmissionService: any = {}

local function requestAdmissionWithEntryType(input: any, entryType: string, operationPrefix: string): any
	admissionDiagnostics.totalRequests += 1
	admissionDiagnostics.lastEntryType = entryType
	admissionDiagnostics.lastReason = "none"
	admissionDiagnostics.lastEnqueueReason = "none"

	if type(input) ~= "table" then
		admissionDiagnostics.lastReason = "request_invalid"
		return { accepted = false, reason = "request_invalid" }
	end
	if not isNonEmptyString(input.partyId) then
		admissionDiagnostics.lastReason = "party_id_invalid"
		return { accepted = false, reason = "party_id_invalid" }
	end

	local targetRealmId, targetReason = resolveTargetRealmId(input)
	if targetRealmId == nil then
		local resolvedReason = targetReason or "target_realm_unavailable"
		admissionDiagnostics.lastReason = resolvedReason
		return { accepted = false, reason = targetReason or "target_realm_unavailable" }
	end

	local permissionAllowed, permissionReason =
		validateRealmAdmissionPermission(targetRealmId, entryType, resolveMemberUserIds(input))
	if not permissionAllowed then
		local rejectedReason = permissionReason or "realm_access_denied"
		admissionDiagnostics.lastReason = rejectedReason
		return { accepted = false, reason = rejectedReason }
	end

	local createdAt = resolveNow()
	local operationId = input.operationId
	if not isNonEmptyString(operationId) then
		operationId = string.format("%s_%s_%d", operationPrefix, input.partyId, math.floor(createdAt * 1000))
	end

	local result = admissionProducer.Enqueue({
		operationId = operationId,
		partyId = input.partyId,
		targetRealmId = targetRealmId,
		entryType = entryType,
		partyMemberUserIds = resolveMemberUserIds(input),
		priority = input.priority,
		createdAt = createdAt,
		expiration = input.expiration,
		expirationSeconds = input.expirationSeconds,
		retryCount = 0,
	})

	admissionDiagnostics.enqueueAttempts += 1

	if result.accepted ~= true then
		admissionDiagnostics.enqueueFailed += 1
		local rejectedReason = if type(result.reason) == "string" then result.reason else "admission_enqueue_failed"
		admissionDiagnostics.lastReason = rejectedReason
		admissionDiagnostics.lastEnqueueReason = rejectedReason
		return {
			accepted = false,
			reason = result.reason,
			payload = result.payload,
		}
	end

	admissionDiagnostics.enqueueSucceeded += 1
	local acceptedReason = if type(result.reason) == "string" then result.reason else "accepted"
	admissionDiagnostics.lastReason = acceptedReason
	admissionDiagnostics.lastEnqueueReason = acceptedReason

	return {
		accepted = true,
		reason = result.reason,
		payload = result.payload,
		snapshot = result.snapshot,
	}
end

function PartyMatchmakingAdmissionService.GetAdmissionDiagnostics(): AdmissionDiagnostics
	return cloneAdmissionDiagnostics()
end

function PartyMatchmakingAdmissionService.RequestPartyAdmission(input: any): any
	return requestAdmissionWithEntryType(input, "direct_invite", "party_match")
end

function PartyMatchmakingAdmissionService.RequestPartyMatchAdmission(input: any): any
	return requestAdmissionWithEntryType(input, "direct_invite", "party_queue_match")
end

function PartyMatchmakingAdmissionService.ConfigureForTests(config: any)
	local configAny: any = config
	queryApiOverride = if type(configAny) == "table" then configAny.admissionQueueApi else nil
	nowFnOverride = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
	targetRealmResolverOverride = if type(configAny) == "table" then configAny.targetRealmResolver else nil
end

function PartyMatchmakingAdmissionService.ResetForTests()
	queryApiOverride = nil
	nowFnOverride = nil
	targetRealmResolverOverride = nil
	admissionDiagnostics = {
		totalRequests = 0,
		resolverAttempts = 0,
		resolverSucceeded = 0,
		resolverFailed = 0,
		resolverFallbackDirectTargetUsed = 0,
		enqueueAttempts = 0,
		enqueueSucceeded = 0,
		enqueueFailed = 0,
		lastEntryType = "none",
		lastReason = "none",
		lastResolverReason = "none",
		lastEnqueueReason = "none",
		lastResolverPath = "none",
	}
end

globalEnv._PartyMatchmakingAdmissionService_QueryAPI = {
	RequestPartyAdmission = function(input: any): any
		return PartyMatchmakingAdmissionService.RequestPartyAdmission(input)
	end,
	RequestPartyMatchAdmission = function(input: any): any
		return PartyMatchmakingAdmissionService.RequestPartyMatchAdmission(input)
	end,
	GetAdmissionDiagnostics = function(): AdmissionDiagnostics
		return PartyMatchmakingAdmissionService.GetAdmissionDiagnostics()
	end,
	ConfigureForTests = function(config: any)
		PartyMatchmakingAdmissionService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		PartyMatchmakingAdmissionService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_PartyMatchmakingAdmissionService_QueryAPI", globalEnv._PartyMatchmakingAdmissionService_QueryAPI)
end

return PartyMatchmakingAdmissionService
