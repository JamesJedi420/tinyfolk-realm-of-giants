--!nocheck

local AdmissionQueueProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("AdmissionQueueProducer"))
	else (require :: any)("./AdmissionQueueProducer")

local globalEnv: any = getfenv()

local DEFAULT_EXPIRATION_SECONDS = 600

local queryApiOverride: any = nil
local nowFnOverride: (() -> number)? = nil
local targetRealmResolverOverride: any = nil

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

local function resolveTargetRealmId(input: any): (string?, string?)
	if type(input) ~= "table" then
		return nil, "request_invalid"
	end

	if isNonEmptyString(input.targetRealmId) then
		return input.targetRealmId, nil
	end

	local resolver = targetRealmResolverOverride
	if resolver == nil then
		local envAny: any = globalEnv
		if type(envAny) == "table" then
			resolver = envAny._PartyMatchmakingRealmResolver_QueryAPI
		end
	end
	if type(resolver) ~= "table" or type((resolver :: any).ResolveTargetRealmId) ~= "function" then
		return nil, "target_realm_unavailable"
	end

	local ok, result = pcall(function()
		return (resolver :: any).ResolveTargetRealmId(input)
	end)
	if not ok or type(result) ~= "table" then
		return nil, "target_realm_unavailable"
	end
	if result.accepted ~= true or not isNonEmptyString(result.targetRealmId) then
		if type(result.reason) == "string" then
			return nil, result.reason
		end
		return nil, "target_realm_unavailable"
	end

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

function PartyMatchmakingAdmissionService.RequestPartyAdmission(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "request_invalid" }
	end
	if not isNonEmptyString(input.partyId) then
		return { accepted = false, reason = "party_id_invalid" }
	end

	local targetRealmId, targetReason = resolveTargetRealmId(input)
	if targetRealmId == nil then
		return { accepted = false, reason = targetReason or "target_realm_unavailable" }
	end

	local createdAt = resolveNow()
	local operationId = input.operationId
	if not isNonEmptyString(operationId) then
		operationId = string.format("party_match_%s_%d", input.partyId, math.floor(createdAt * 1000))
	end

	local result = admissionProducer.Enqueue({
		operationId = operationId,
		partyId = input.partyId,
		targetRealmId = targetRealmId,
		entryType = "direct_invite",
		partyMemberUserIds = resolveMemberUserIds(input),
		priority = input.priority,
		createdAt = createdAt,
		expiration = input.expiration,
		expirationSeconds = input.expirationSeconds,
		retryCount = 0,
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
end

globalEnv._PartyMatchmakingAdmissionService_QueryAPI = {
	RequestPartyAdmission = function(input: any): any
		return PartyMatchmakingAdmissionService.RequestPartyAdmission(input)
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
