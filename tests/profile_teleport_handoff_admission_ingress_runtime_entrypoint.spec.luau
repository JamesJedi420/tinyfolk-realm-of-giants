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
globalEnv._ProfileTeleportAdmissionService_QueryAPI = {
	RequestTeleportHandoffAdmission = function(payload: any): any
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
assertEqual(ingressPayloads[1].handoffToken, accepted.handoffToken, "handoff token maps to ingress payload")
assertEqual(ingressPayloads[1].userId, 6101, "ingress payload user id")
assertEqual(ingressPayloads[1].targetRealmId, "realm-77", "handoff target realm propagated")
local afterPrimaryDiagnostics = ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
assertEqual(afterPrimaryDiagnostics.totalAttempts, 1, "primary diagnostics total attempts")
assertEqual(afterPrimaryDiagnostics.primaryAttempts, 1, "primary diagnostics primary attempts")
assertEqual(afterPrimaryDiagnostics.primarySucceeded, 1, "primary diagnostics primary success")
assertEqual(afterPrimaryDiagnostics.primaryFailed, 0, "primary diagnostics primary failures")
assertEqual(afterPrimaryDiagnostics.fallbackAttempts, 0, "primary diagnostics fallback attempts")
assertEqual(afterPrimaryDiagnostics.lastPath, "primary_profile_teleport", "primary diagnostics last path")
assertEqual(afterPrimaryDiagnostics.lastReason, "accepted", "primary diagnostics last reason")

globalEnv._ProfileTeleportAdmissionService_QueryAPI = nil
local fallbackIngressPayloads = {}
globalEnv._PartyMatchmakingAdmissionService_QueryAPI = {
	RequestPartyMatchAdmission = function(payload: any): any
		table.insert(fallbackIngressPayloads, payload)
		return {
			accepted = true,
			reason = "accepted",
			payload = payload,
		}
	end,
}

local fallbackAccepted = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(6102), {
	flow = "hub_to_realm",
	targetRealmId = "realm-77",
})
assertEqual(fallbackAccepted.ok, true, "fallback handoff accepted")
assertTrue(type(fallbackAccepted.handoffToken) == "string", "fallback token assigned")
assertEqual(#fallbackIngressPayloads, 1, "fallback ingress payload emitted")
assertEqual(fallbackIngressPayloads[1].operationId, fallbackAccepted.handoffToken, "fallback operation id")
assertEqual(
	fallbackIngressPayloads[1].partyId,
	string.format("handoff_party:%d:%s", 6102, fallbackAccepted.handoffToken),
	"fallback deterministic handoff party id"
)
assertEqual(fallbackIngressPayloads[1].targetRealmId, "realm-77", "fallback target realm propagated")
assertEqual(fallbackIngressPayloads[1].partyMemberUserIds[1], 6102, "fallback handoff member user id")
local afterFallbackDiagnostics = ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
assertEqual(afterFallbackDiagnostics.totalAttempts, 2, "fallback diagnostics total attempts")
assertEqual(afterFallbackDiagnostics.primaryAttempts, 2, "fallback diagnostics primary attempts")
assertEqual(afterFallbackDiagnostics.primarySucceeded, 1, "fallback diagnostics primary successes")
assertEqual(afterFallbackDiagnostics.primaryFailed, 1, "fallback diagnostics primary failures")
assertEqual(afterFallbackDiagnostics.fallbackAttempts, 1, "fallback diagnostics fallback attempts")
assertEqual(afterFallbackDiagnostics.fallbackSucceeded, 1, "fallback diagnostics fallback successes")
assertEqual(afterFallbackDiagnostics.fallbackFailed, 0, "fallback diagnostics fallback failures")
assertEqual(afterFallbackDiagnostics.lastPath, "fallback_party_matchmaking", "fallback diagnostics last path")
assertEqual(afterFallbackDiagnostics.lastReason, "accepted", "fallback diagnostics last reason")
assertEqual(
	afterFallbackDiagnostics.lastPrimaryReason,
	"admission_queue_unavailable",
	"fallback diagnostics captures primary unavailability"
)

globalEnv._PartyMatchmakingAdmissionService_QueryAPI = nil
local unavailable = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(6102), {
	flow = "hub_to_realm",
	targetRealmId = "realm-77",
})
assertEqual(unavailable.ok, false, "missing ingress api rejected")
assertEqual(unavailable.reason, "admission_queue_unavailable", "missing ingress api reason")
assertEqual(unavailable.retryable, true, "missing ingress api retryable")
local afterUnavailableDiagnostics = ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
assertEqual(afterUnavailableDiagnostics.totalAttempts, 3, "unavailable diagnostics total attempts")
assertEqual(afterUnavailableDiagnostics.primaryAttempts, 3, "unavailable diagnostics primary attempts")
assertEqual(afterUnavailableDiagnostics.primaryFailed, 2, "unavailable diagnostics primary failures")
assertEqual(afterUnavailableDiagnostics.fallbackAttempts, 2, "unavailable diagnostics fallback attempts")
assertEqual(afterUnavailableDiagnostics.fallbackSucceeded, 1, "unavailable diagnostics fallback successes")
assertEqual(afterUnavailableDiagnostics.fallbackFailed, 1, "unavailable diagnostics fallback failures")
assertEqual(afterUnavailableDiagnostics.lastPath, "fallback_party_matchmaking", "unavailable diagnostics last path")
assertEqual(
	afterUnavailableDiagnostics.lastFallbackReason,
	"admission_queue_unavailable",
	"unavailable diagnostics fallback reason"
)

globalEnv._ProfileTeleportAdmissionService_QueryAPI = {
	RequestTeleportHandoffAdmission = function(_payload: any): any
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
local afterExceptionDiagnostics = ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
assertEqual(afterExceptionDiagnostics.totalAttempts, 4, "exception diagnostics total attempts")
assertEqual(afterExceptionDiagnostics.primaryAttempts, 4, "exception diagnostics primary attempts")
assertEqual(afterExceptionDiagnostics.primaryFailed, 3, "exception diagnostics primary failures")
assertEqual(afterExceptionDiagnostics.fallbackAttempts, 2, "exception diagnostics fallback attempts unchanged")
assertEqual(afterExceptionDiagnostics.lastPath, "primary_profile_teleport", "exception diagnostics last path")
assertEqual(afterExceptionDiagnostics.lastReason, "admission_enqueue_failed", "exception diagnostics last reason")
assertEqual(
	afterExceptionDiagnostics.lastPrimaryReason,
	"admission_enqueue_failed",
	"exception diagnostics primary reason"
)

print("profile_teleport_handoff_admission_ingress_runtime_entrypoint: all checks passed")
