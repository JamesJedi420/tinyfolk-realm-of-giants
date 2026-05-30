--!nocheck

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local ProfileTeleportHandoffService = require("../src/ServerScriptService/Services/ProfileTeleportHandoffService")
local globalEnv: any = getfenv()

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

local function makePlayer(userId: number): any
	return {
		UserId = userId,
		Name = "Player" .. tostring(userId),
	}
end

local ownershipReadyByUserId: { [number]: boolean } = {}
globalEnv._ProfilePersistenceLifecycle_QueryAPI = {
	IsPlayerOwnershipReady = function(userId: number): boolean
		return ownershipReadyByUserId[userId] == true
	end,
}

ProfilePersistenceGateway.ResetForTests()
ProfileTeleportHandoffService.ResetForTests()

ProfilePersistenceGateway.ReleasePlayerProfile = function(_player: any): any
	return {
		ok = true,
		operation = "ReleasePlayerProfile",
		profileKey = "PlayerProfile:test",
	}
end

local ingressPayloads = {}
globalEnv._PartyMatchmakingAdmissionService_QueryAPI = {
	RequestPartyMatchAdmission = function(payload: any): any
		table.insert(ingressPayloads, payload)
		return {
			accepted = true,
			reason = "accepted",
			payload = payload,
		}
	end,
}

local accepted = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(6101), {
	flow = "hub_to_realm",
	targetRealmId = "realm-77",
})
assertEqual(accepted.ok, true, "handoff accepted")
assertTrue(type(accepted.handoffToken) == "string", "handoff token assigned")
assertEqual(#ingressPayloads, 1, "ingress payload emitted")
assertEqual(ingressPayloads[1].operationId, accepted.handoffToken, "operation id maps to handoff token")
assertEqual(
	ingressPayloads[1].partyId,
	string.format("handoff_party:%d:%s", 6101, accepted.handoffToken),
	"deterministic handoff party id"
)
assertEqual(ingressPayloads[1].targetRealmId, "realm-77", "handoff target realm propagated")
assertEqual(type(ingressPayloads[1].partyMemberUserIds), "table", "member user ids table")
assertEqual(#ingressPayloads[1].partyMemberUserIds, 1, "single member handoff")
assertEqual(ingressPayloads[1].partyMemberUserIds[1], 6101, "handoff member user id")

globalEnv._PartyMatchmakingAdmissionService_QueryAPI = nil
local unavailable = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(6102), {
	flow = "hub_to_realm",
	targetRealmId = "realm-77",
})
assertEqual(unavailable.ok, false, "missing ingress api rejected")
assertEqual(unavailable.reason, "admission_queue_unavailable", "missing ingress api reason")
assertEqual(unavailable.retryable, true, "missing ingress api retryable")

globalEnv._PartyMatchmakingAdmissionService_QueryAPI = {
	RequestPartyMatchAdmission = function(_payload: any): any
		error("boom")
	end,
}
local failed = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(6103), {
	flow = "hub_to_realm",
	targetRealmId = "realm-77",
})
assertEqual(failed.ok, false, "ingress exception rejected")
assertEqual(failed.reason, "admission_enqueue_failed", "ingress exception reason")
assertEqual(failed.retryable, true, "ingress exception retryable")

print("profile_teleport_handoff_admission_ingress_runtime_entrypoint: all checks passed")
