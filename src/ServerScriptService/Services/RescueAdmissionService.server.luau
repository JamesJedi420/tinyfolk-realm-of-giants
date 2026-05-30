--!nocheck

local AdmissionQueueProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("AdmissionQueueProducer"))
	else (require :: any)("./AdmissionQueueProducer")

local globalEnv: any = getfenv()

local DEFAULT_EXPIRATION_SECONDS = 600

local queryApiOverride: any = nil
local nowFnOverride: (() -> number)? = nil

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
		return { accepted = false, reason = "request_invalid" }
	end
	if not isNonEmptyString(input.partyId) then
		return { accepted = false, reason = "party_id_invalid" }
	end
	if not isNonEmptyString(input.targetRealmId) then
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

	if result.accepted ~= true then
		return {
			accepted = false,
			reason = result.reason,
			payload = result.payload,
		}
	end

	return {
		accepted = true,
		reason = result.reason,
		payload = result.payload,
		snapshot = result.snapshot,
	}
end

function RescueAdmissionService.ConfigureForTests(config: any)
	local configAny: any = config
	queryApiOverride = if type(configAny) == "table" then configAny.admissionQueueApi else nil
	nowFnOverride = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
end

function RescueAdmissionService.ResetForTests()
	queryApiOverride = nil
	nowFnOverride = nil
end

globalEnv._RescueAdmissionService_QueryAPI = {
	RequestRescueContractAdmission = function(input: any): any
		return RescueAdmissionService.RequestRescueContractAdmission(input)
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
