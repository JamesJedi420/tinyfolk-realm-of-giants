--!strict

local PartyMatchmakingRealmResolverService: any = {}
local globalEnv: any = getfenv()
local resolveFallbackTargetRealmIdOverride: ((any) -> any)? = nil

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

function PartyMatchmakingRealmResolverService.ResolveTargetRealmId(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "request_invalid",
			targetRealmId = nil,
		}
	end

	if not isNonEmptyString(input.partyId) then
		return {
			accepted = false,
			reason = "party_id_invalid",
			targetRealmId = nil,
		}
	end

	if not isNonEmptyString(input.targetRealmId) then
		if type(resolveFallbackTargetRealmIdOverride) == "function" then
			local ok, resolved = pcall(resolveFallbackTargetRealmIdOverride, input)
			if ok and isNonEmptyString(resolved) then
				return {
					accepted = true,
					reason = "accepted",
					targetRealmId = resolved,
				}
			end
		end

		return {
			accepted = false,
			reason = "target_realm_missing",
			targetRealmId = nil,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		targetRealmId = input.targetRealmId,
	}
end

function PartyMatchmakingRealmResolverService.ConfigureForTests(config: any?)
	local configAny: any = config
	resolveFallbackTargetRealmIdOverride = if type(configAny) == "table"
			and type(configAny.resolveFallbackTargetRealmId) == "function"
		then configAny.resolveFallbackTargetRealmId
		else nil
end

function PartyMatchmakingRealmResolverService.ResetForTests()
	resolveFallbackTargetRealmIdOverride = nil
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
