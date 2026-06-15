--!nocheck

local globalEnv: any = _G

globalEnv._PartyMatchmakingRealmResolver_QueryAPI = nil

require("../src/ServerScriptService/Services/PartyMatchmakingRealmResolverService")

local resolverApi = globalEnv._PartyMatchmakingRealmResolver_QueryAPI
assert(type(resolverApi) == "table", "resolver query api published")
assert(type(resolverApi.ResolveTargetRealmId) == "function", "resolver function published")
assert(type(resolverApi.ConfigureForTests) == "function", "resolver configure for tests published")
assert(type(resolverApi.ResetForTests) == "function", "resolver reset for tests published")

local invalidRequest = resolverApi.ResolveTargetRealmId(nil)
assert(invalidRequest.accepted == false, "nil request rejected")
assert(invalidRequest.reason == "request_invalid", "nil request reason")

local invalidParty = resolverApi.ResolveTargetRealmId({
	partyId = "",
	targetRealmId = "realm-1",
})
assert(invalidParty.accepted == false, "invalid party rejected")
assert(invalidParty.reason == "party_id_invalid", "invalid party reason")

local missingTarget = resolverApi.ResolveTargetRealmId({
	partyId = "party-1",
})
assert(missingTarget.accepted == false, "missing target rejected")
assert(missingTarget.reason == "target_realm_missing", "missing target reason")

resolverApi.ConfigureForTests({
	listLiveRealmAvailability = function(_limit: number?, _at: number?): { any }
		return {
			{
				realmId = "giant_realm_7001",
				ownerUserId = 7001,
				privateServerId = "ps-live-7001",
				accessMode = "private",
				playerCount = 2,
				capacity = 8,
				dangerRating = 0.8,
				lifecycle = "active",
				isAvailable = true,
				updatedAt = 100,
			},
		}
	end,
})

local raidBoardAccepted = resolverApi.ResolveTargetRealmId({
	partyId = "party-raid-board",
})
assert(raidBoardAccepted.accepted == true, "hub raid board accepted")
assert(raidBoardAccepted.targetRealmId == "giant_realm_7001", "hub raid board target realm")
assert(raidBoardAccepted.privateServerId == "ps-live-7001", "hub raid board private server id")
assert(raidBoardAccepted.resolverPath == "hub_raid_board", "hub raid board resolver path")

local hubDirectAccepted = resolverApi.ResolveTargetRealmId({
	partyId = "party-direct",
	targetRealmId = "giant_realm_7001",
})
assert(hubDirectAccepted.accepted == true, "hub direct target accepted")
assert(hubDirectAccepted.resolverPath == "hub_direct", "hub direct resolver path")

local hubDirectRejected = resolverApi.ResolveTargetRealmId({
	partyId = "party-direct-missing",
	targetRealmId = "giant_realm_missing",
})
assert(hubDirectRejected.accepted == false, "hub direct missing rejected")
assert(hubDirectRejected.reason == "target_realm_unavailable", "hub direct missing reason")

resolverApi.ResetForTests()
resolverApi.ConfigureForTests({
	resolveFallbackTargetRealmId = function(input: any)
		if input.partyId == "party-fallback" then
			return "realm-fallback"
		end
		return nil
	end,
})

local fallbackAccepted = resolverApi.ResolveTargetRealmId({
	partyId = "party-fallback",
})
assert(fallbackAccepted.accepted == true, "fallback target accepted")
assert(fallbackAccepted.targetRealmId == "realm-fallback", "fallback target value")

resolverApi.ResetForTests()

local accepted = resolverApi.ResolveTargetRealmId({
	partyId = "party-1",
	targetRealmId = "realm-42",
})
assert(accepted.accepted == true, "valid request accepted")
assert(accepted.reason == "accepted", "valid request reason")
assert(accepted.targetRealmId == "realm-42", "valid request target")

globalEnv._PartyMatchmakingRealmResolver_QueryAPI = nil

print("party_matchmaking_realm_resolver_service_runtime_entrypoint: all checks passed")
