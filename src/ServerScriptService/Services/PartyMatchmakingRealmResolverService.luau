--!strict

local LiveRealmHubRouting = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("LiveRealmHubRouting")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")

local PartyMatchmakingRealmResolverService: any = {}
local globalEnv: any = getfenv()
local resolveFallbackTargetRealmIdOverride: ((any) -> any)? = nil
local liveRegistryHubApiOverride: any = nil
local listLiveRealmAvailabilityOverride: ((number?, number?) -> { any })? = nil

local DEFAULT_AVAILABILITY_LIMIT = 25

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function getLiveRegistryHubApi(): any?
	if liveRegistryHubApiOverride ~= nil then
		return liveRegistryHubApiOverride
	end

	local fromEnv = rawget(globalEnv, "_LiveRealmRegistryHubSurface_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end

	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_LiveRealmRegistryHubSurface_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end

	return nil
end

local function readLiveRealmAvailability(limit: number?, at: number?): { any }?
	if type(listLiveRealmAvailabilityOverride) == "function" then
		local ok, availability = pcall(listLiveRealmAvailabilityOverride, limit, at)
		if ok and type(availability) == "table" then
			return availability
		end
		return nil
	end

	local hubApi = getLiveRegistryHubApi()
	if type(hubApi) ~= "table" or type((hubApi :: any).ListLiveRealmAvailability) ~= "function" then
		return nil
	end

	local resolvedLimit = if type(limit) == "number" and limit > 0 then limit else DEFAULT_AVAILABILITY_LIMIT
	local ok, availability = pcall(function()
		return (hubApi :: any).ListLiveRealmAvailability(resolvedLimit, at)
	end)
	if not ok or type(availability) ~= "table" then
		return nil
	end

	return availability
end

local function resolveViaLiveRegistryHub(input: any): any?
	local availability = readLiveRealmAvailability(DEFAULT_AVAILABILITY_LIMIT, nil)
	if availability == nil then
		return nil
	end

	local hubResult = LiveRealmHubRouting.ResolveAdmissionTarget({
		targetRealmId = if type(input) == "table" then input.targetRealmId else nil,
	}, availability)
	if hubResult.accepted ~= true then
		return {
			accepted = false,
			reason = hubResult.reason,
			targetRealmId = nil,
			privateServerId = nil,
			resolverPath = hubResult.resolverPath,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		targetRealmId = hubResult.targetRealmId,
		privateServerId = hubResult.privateServerId,
		resolverPath = hubResult.resolverPath,
	}
end

function PartyMatchmakingRealmResolverService.ResolveTargetRealmId(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "request_invalid",
			targetRealmId = nil,
			privateServerId = nil,
			resolverPath = "invalid_request",
		}
	end

	if not isNonEmptyString(input.partyId) then
		return {
			accepted = false,
			reason = "party_id_invalid",
			targetRealmId = nil,
			privateServerId = nil,
			resolverPath = "party_id_invalid",
		}
	end

	local hubResolved = resolveViaLiveRegistryHub(input)
	if hubResolved ~= nil then
		return hubResolved
	end

	if not isNonEmptyString(input.targetRealmId) then
		if type(resolveFallbackTargetRealmIdOverride) == "function" then
			local ok, resolved = pcall(resolveFallbackTargetRealmIdOverride, input)
			if ok and isNonEmptyString(resolved) then
				return {
					accepted = true,
					reason = "accepted",
					targetRealmId = resolved,
					privateServerId = nil,
					resolverPath = "fallback_override",
				}
			end
		end

		return {
			accepted = false,
			reason = "target_realm_missing",
			targetRealmId = nil,
			privateServerId = nil,
			resolverPath = "target_realm_missing",
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		targetRealmId = input.targetRealmId,
		privateServerId = nil,
		resolverPath = "direct_input",
	}
end

function PartyMatchmakingRealmResolverService.ConfigureForTests(config: any?)
	local configAny: any = config
	resolveFallbackTargetRealmIdOverride = if type(configAny) == "table"
			and type(configAny.resolveFallbackTargetRealmId) == "function"
		then configAny.resolveFallbackTargetRealmId
		else nil
	liveRegistryHubApiOverride = if type(configAny) == "table" then configAny.liveRegistryHubApi else nil
	listLiveRealmAvailabilityOverride = if type(configAny) == "table"
			and type(configAny.listLiveRealmAvailability) == "function"
		then configAny.listLiveRealmAvailability
		else nil
end

function PartyMatchmakingRealmResolverService.ResetForTests()
	resolveFallbackTargetRealmIdOverride = nil
	liveRegistryHubApiOverride = nil
	listLiveRealmAvailabilityOverride = nil
end

globalEnv._PartyMatchmakingRealmResolver_QueryAPI = {
	ResolveTargetRealmId = function(input: any): any
		return PartyMatchmakingRealmResolverService.ResolveTargetRealmId(input)
	end,
	ConfigureForTests = function(config: any?)
		PartyMatchmakingRealmResolverService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		PartyMatchmakingRealmResolverService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_PartyMatchmakingRealmResolver_QueryAPI", globalEnv._PartyMatchmakingRealmResolver_QueryAPI)
end

return PartyMatchmakingRealmResolverService
