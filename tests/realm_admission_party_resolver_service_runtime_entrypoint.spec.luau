--!nocheck

local ResolverService = require("../src/ServerScriptService/Services/RealmAdmissionPartyResolverService")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

ResolverService.ResetForTests()
ResolverService.ConfigureForTests({
	now = function(): number
		return 100
	end,
	playersService = {
		GetPlayers = function(_self: any)
			return {
				{
					UserId = 501,
					GetAttribute = function(_p: any, name: string)
						if name == "RealmAdmissionPartyId" then
							return "party-attr"
						end
						return nil
					end,
				},
				{
					UserId = 502,
					GetAttribute = function(_p: any, name: string)
						if name == "PartyId" then
							return "party-legacy"
						end
						return nil
					end,
				},
			}
		end,
	},
})

local registerResult = ResolverService.RegisterPartyMembers({
	partyId = "party-reg",
	memberUserIds = { 503, 504, 503 },
	at = 100,
	ttlSeconds = 30,
})
assertTrue(registerResult.accepted, "register accepts valid input")

local registeredMembers = ResolverService.ResolvePartyMemberUserIds("party-reg", 110)
assertEqual(#registeredMembers, 2, "registered members resolved")
assertEqual(registeredMembers[1], 503, "registered member first")
assertEqual(registeredMembers[2], 504, "registered member second")

local expiredMembers = ResolverService.ResolvePartyMemberUserIds("party-reg", 131)
assertEqual(#expiredMembers, 0, "registered members expire by ttl")

local attributeMembers = ResolverService.ResolvePartyMemberUserIds("party-attr", 120)
assertEqual(#attributeMembers, 1, "attribute fallback resolves member")
assertEqual(attributeMembers[1], 501, "attribute fallback member id")

local legacyMembers = ResolverService.ResolvePartyMemberUserIds("party-legacy", 120)
assertEqual(#legacyMembers, 1, "legacy attribute fallback resolves member")
assertEqual(legacyMembers[1], 502, "legacy attribute fallback member id")

local invalidRegister = ResolverService.RegisterPartyMembers({
	partyId = "",
	memberUserIds = { 501 },
})
assertEqual(invalidRegister.accepted, false, "invalid party id rejected")

local unregisterResult = ResolverService.UnregisterParty("party-reg")
assertTrue(unregisterResult.accepted, "unregister accepted")

print("realm_admission_party_resolver_service_runtime_entrypoint: all checks passed")
