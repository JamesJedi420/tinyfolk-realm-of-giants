--!nocheck

local AdmissionQueueProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("AdmissionQueueProducer"))
	else (require :: any)("./AdmissionQueueProducer")

local globalEnv: any = getfenv()

local DEFAULT_EXPIRATION_SECONDS = 600

local queryApiOverride: any = nil
local nowFnOverride: (() -> number)? = nil

type AdmissionDiagnostics = {
	enqueueAttempts: number,
	enqueueSucceeded: number,
	enqueueFailed: number,
	lastReason: string,
}

local admissionDiagnostics: AdmissionDiagnostics = {
	enqueueAttempts = 0,
	enqueueSucceeded = 0,
	enqueueFailed = 0,
	lastReason = "not_started",
}

local function cloneAdmissionDiagnostics(): AdmissionDiagnostics
	return {
		enqueueAttempts = admissionDiagnostics.enqueueAttempts,
		enqueueSucceeded = admissionDiagnostics.enqueueSucceeded,
		enqueueFailed = admissionDiagnostics.enqueueFailed,
		lastReason = admissionDiagnostics.lastReason,
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

local admissionProducer = AdmissionQueueProducer.Create({
	defaultExpirationSeconds = DEFAULT_EXPIRATION_SECONDS,
	now = function(): number
		return resolveNow()
	end,
	queryApiResolver = function()
		return getRealmAdmissionQueueQueryApi()
	end,
})

local ProfileTeleportAdmissionService: any = {}

function ProfileTeleportAdmissionService.RequestTeleportHandoffAdmission(input: any): any
	if type(input) ~= "table" then
		admissionDiagnostics.lastReason = "request_invalid"
		return { accepted = false, reason = "request_invalid" }
	end

	if not isValidUserId(input.userId) then
		admissionDiagnostics.lastReason = "admission_user_id_invalid"
		return { accepted = false, reason = "admission_user_id_invalid" }
	end
	if not isNonEmptyString(input.handoffToken) then
		admissionDiagnostics.lastReason = "handoff_token_invalid"
		return { accepted = false, reason = "handoff_token_invalid" }
	end
	if not isNonEmptyString(input.targetRealmId) then
		admissionDiagnostics.lastReason = "target_realm_id_invalid"
		return { accepted = false, reason = "target_realm_id_invalid" }
	end

	local userId = input.userId
	local handoffToken = input.handoffToken
	local createdAt = resolveNow()
	local operationId = if isNonEmptyString(input.operationId) then input.operationId else handoffToken
	local partyId = if isNonEmptyString(input.partyId)
		then input.partyId
		else string.format("handoff_party:%d:%s", userId, handoffToken)

	local result = admissionProducer.Enqueue({
		operationId = operationId,
		partyId = partyId,
		targetRealmId = input.targetRealmId,
		entryType = "matchmaking_queue",
		partyMemberUserIds = { userId },
		priority = input.priority,
		createdAt = createdAt,
		expiration = input.expiration,
		expirationSeconds = input.expirationSeconds,
		retryCount = 0,
	})

	admissionDiagnostics.enqueueAttempts += 1

	if result.accepted ~= true then
		admissionDiagnostics.enqueueFailed += 1
		admissionDiagnostics.lastReason = if type(result.reason) == "string"
			then result.reason
			else "admission_enqueue_failed"
		return {
			accepted = false,
			reason = result.reason,
			payload = result.payload,
		}
	end

	admissionDiagnostics.enqueueSucceeded += 1
	admissionDiagnostics.lastReason = if type(result.reason) == "string" then result.reason else "accepted"

	return {
		accepted = true,
		reason = result.reason,
		payload = result.payload,
		snapshot = result.snapshot,
	}
end

function ProfileTeleportAdmissionService.GetAdmissionDiagnostics(): AdmissionDiagnostics
	return cloneAdmissionDiagnostics()
end

function ProfileTeleportAdmissionService.ConfigureForTests(config: any)
	local configAny: any = config
	queryApiOverride = if type(configAny) == "table" then configAny.admissionQueueApi else nil
	nowFnOverride = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
end

function ProfileTeleportAdmissionService.ResetForTests()
	queryApiOverride = nil
	nowFnOverride = nil
	admissionDiagnostics = {
		enqueueAttempts = 0,
		enqueueSucceeded = 0,
		enqueueFailed = 0,
		lastReason = "not_started",
	}
end

globalEnv._ProfileTeleportAdmissionService_QueryAPI = {
	RequestTeleportHandoffAdmission = function(input: any): any
		return ProfileTeleportAdmissionService.RequestTeleportHandoffAdmission(input)
	end,
	GetAdmissionDiagnostics = function(): AdmissionDiagnostics
		return ProfileTeleportAdmissionService.GetAdmissionDiagnostics()
	end,
	ConfigureForTests = function(config: any)
		ProfileTeleportAdmissionService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		ProfileTeleportAdmissionService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_ProfileTeleportAdmissionService_QueryAPI", globalEnv._ProfileTeleportAdmissionService_QueryAPI)
end

return ProfileTeleportAdmissionService
