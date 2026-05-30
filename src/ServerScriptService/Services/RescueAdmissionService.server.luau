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

local RescueAdmissionService: any = {}

function RescueAdmissionService.RequestRescueContractAdmission(input: any): any
	if type(input) ~= "table" then
		admissionDiagnostics.lastReason = "request_invalid"
		return { accepted = false, reason = "request_invalid" }
	end
	if not isNonEmptyString(input.partyId) then
		admissionDiagnostics.lastReason = "party_id_invalid"
		return { accepted = false, reason = "party_id_invalid" }
	end
	if not isNonEmptyString(input.targetRealmId) then
		admissionDiagnostics.lastReason = "target_realm_id_invalid"
		return { accepted = false, reason = "target_realm_id_invalid" }
	end

	local createdAt = resolveNow()
	local operationId = input.operationId
	if not isNonEmptyString(operationId) then
		operationId = string.format("rescue_admission_%s_%d", input.partyId, math.floor(createdAt * 1000))
	end

	local result = admissionProducer.Enqueue({
		operationId = operationId,
		partyId = input.partyId,
		targetRealmId = input.targetRealmId,
		entryType = "rescue_contract",
		partyMemberUserIds = resolveMemberUserIds(input),
		priority = input.priority,
		createdAt = createdAt,
		expiration = input.expiration,
		expirationSeconds = input.expirationSeconds,
		retryCount = input.retryCount,
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

function RescueAdmissionService.GetAdmissionDiagnostics(): AdmissionDiagnostics
	return cloneAdmissionDiagnostics()
end

function RescueAdmissionService.ConfigureForTests(config: any)
	local configAny: any = config
	queryApiOverride = if type(configAny) == "table" then configAny.admissionQueueApi else nil
	nowFnOverride = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
end

function RescueAdmissionService.ResetForTests()
	queryApiOverride = nil
	nowFnOverride = nil
	admissionDiagnostics = {
		enqueueAttempts = 0,
		enqueueSucceeded = 0,
		enqueueFailed = 0,
		lastReason = "not_started",
	}
end

globalEnv._RescueAdmissionService_QueryAPI = {
	RequestRescueContractAdmission = function(input: any): any
		return RescueAdmissionService.RequestRescueContractAdmission(input)
	end,
	GetAdmissionDiagnostics = function(): AdmissionDiagnostics
		return RescueAdmissionService.GetAdmissionDiagnostics()
	end,
	ConfigureForTests = function(config: any)
		RescueAdmissionService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		RescueAdmissionService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RescueAdmissionService_QueryAPI", globalEnv._RescueAdmissionService_QueryAPI)
end

return RescueAdmissionService
