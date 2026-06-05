--!nocheck

local globalEnv: any = _G

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

local function resetGlobals()
	globalEnv._PartyMatchmakingAdmissionService_QueryAPI = nil
	globalEnv._PartyMatchmakingRealmResolver_QueryAPI = nil
	globalEnv._RealmAdmissionQueue_QueryAPI = nil
end

resetGlobals()
require("../src/ServerScriptService/Services/PartyMatchmakingRealmResolverService")
require("../src/ServerScriptService/Services/PartyMatchmakingAdmissionService.server")

local resolverApi = globalEnv._PartyMatchmakingRealmResolver_QueryAPI
assertTrue(type(resolverApi) == "table", "resolver query api published")
assertTrue(type(resolverApi.ResolveTargetRealmId) == "function", "resolver function published")

local serviceApi = globalEnv._PartyMatchmakingAdmissionService_QueryAPI
assertTrue(type(serviceApi) == "table", "service query api published")
assertTrue(type(serviceApi.RequestPartyAdmission) == "function", "request function published")
assertTrue(type(serviceApi.RequestPartyMatchAdmission) == "function", "match admission function published")
assertTrue(type(serviceApi.GetAdmissionDiagnostics) == "function", "diagnostics function published")

local enqueuePayloads = {}
local admissionQueueApi = {
	EnqueueAdmission = function(payload: any)
		table.insert(enqueuePayloads, payload)
		return {
			accepted = true,
			reason = "accepted",
			snapshot = {
				operationId = payload.operationId,
				partyId = payload.partyId,
			},
		}
	end,
}

serviceApi.ConfigureForTests({
	now = function()
		return 123
	end,
	admissionQueueApi = admissionQueueApi,
})

local accepted = serviceApi.RequestPartyAdmission({
	partyId = "party-alpha",
	targetRealmId = "realm-17",
	memberUserIds = { 44, 19, 44 },
})
assertEqual(accepted.accepted, true, "accepted admission request")
assertEqual(accepted.reason, "accepted", "accepted reason")
assertEqual(accepted.payload.entryType, "direct_invite", "direct invite entry type")
assertEqual(accepted.payload.partySize, 2, "deduped party size")
assertEqual(accepted.payload.operationId, "party_match_party-alpha_123000", "generated operation id")
assertEqual(accepted.payload.targetRealmId, "realm-17", "target realm id")
assertEqual(accepted.payload.partyMemberUserIds[1], 19, "normalized member ordering first")
assertEqual(accepted.payload.partyMemberUserIds[2], 44, "normalized member ordering second")
assertEqual(#enqueuePayloads, 1, "enqueue invoked once")
local acceptedDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(acceptedDiagnostics.totalRequests, 1, "diagnostics total requests after first acceptance")
assertEqual(acceptedDiagnostics.resolverAttempts, 1, "diagnostics resolver attempts after first acceptance")
assertEqual(acceptedDiagnostics.resolverSucceeded, 1, "diagnostics resolver success after first acceptance")
assertEqual(acceptedDiagnostics.resolverFallbackDirectTargetUsed, 0, "diagnostics direct target fallback baseline")
assertEqual(acceptedDiagnostics.enqueueAttempts, 1, "diagnostics enqueue attempts after first acceptance")
assertEqual(acceptedDiagnostics.enqueueSucceeded, 1, "diagnostics enqueue success after first acceptance")
assertEqual(acceptedDiagnostics.enqueueFailed, 0, "diagnostics enqueue failures baseline")
assertEqual(acceptedDiagnostics.lastEntryType, "direct_invite", "diagnostics last entry type first acceptance")
assertEqual(acceptedDiagnostics.lastResolverPath, "resolver_query", "diagnostics last resolver path first acceptance")
assertEqual(acceptedDiagnostics.lastReason, "accepted", "diagnostics last reason first acceptance")

local queueAccepted = serviceApi.RequestPartyMatchAdmission({
	partyId = "party-queue-alpha",
	targetRealmId = "realm-17",
	memberUserIds = { 88, 77, 88 },
})
assertEqual(queueAccepted.accepted, true, "queue-match accepted")
assertEqual(queueAccepted.reason, "accepted", "queue-match accepted reason")
assertEqual(queueAccepted.payload.entryType, "direct_invite", "queue-match entry type")
assertEqual(queueAccepted.payload.partySize, 2, "queue-match deduped party size")
assertEqual(queueAccepted.payload.operationId, "party_queue_match_party-queue-alpha_123000", "queue-match operation id")
assertEqual(queueAccepted.payload.partyMemberUserIds[1], 77, "queue-match normalized member ordering first")
assertEqual(queueAccepted.payload.partyMemberUserIds[2], 88, "queue-match normalized member ordering second")
assertEqual(#enqueuePayloads, 2, "queue-match enqueue invoked")
local queueAcceptedDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(queueAcceptedDiagnostics.totalRequests, 2, "diagnostics total requests after queue acceptance")
assertEqual(queueAcceptedDiagnostics.lastEntryType, "direct_invite", "diagnostics last entry type queue acceptance")
assertEqual(queueAcceptedDiagnostics.enqueueAttempts, 2, "diagnostics enqueue attempts after queue acceptance")
assertEqual(queueAcceptedDiagnostics.enqueueSucceeded, 2, "diagnostics enqueue success after queue acceptance")

resolverApi.ConfigureForTests({
	resolveFallbackTargetRealmId = function(input: any)
		assertEqual(input.partyId, "party-resolved", "resolver receives party id")
		return "realm-from-resolver"
	end,
})

local resolvedAccepted = serviceApi.RequestPartyAdmission({
	partyId = "party-resolved",
	memberUserIds = { 101, 102 },
})
assertEqual(resolvedAccepted.accepted, true, "resolver accepted request")
assertEqual(resolvedAccepted.payload.targetRealmId, "realm-from-resolver", "resolver target realm applied")
assertEqual(#enqueuePayloads, 3, "resolver accepted path enqueues")
local resolvedDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(resolvedDiagnostics.resolverSucceeded, 3, "diagnostics resolver success after resolver query")
assertEqual(resolvedDiagnostics.lastResolverPath, "resolver_query", "diagnostics resolver query path")
assertEqual(resolvedDiagnostics.lastResolverReason, "accepted", "diagnostics resolver query reason")

serviceApi.ConfigureForTests({
	now = function()
		return 200
	end,
	admissionQueueApi = nil,
})
local missingQueue = serviceApi.RequestPartyAdmission({
	partyId = "party-no-queue",
	targetRealmId = "realm-17",
	memberUserIds = { 1 },
})
assertEqual(missingQueue.accepted, false, "missing queue rejected")
assertEqual(missingQueue.reason, "admission_queue_unavailable", "missing queue reason")
local missingQueueDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(missingQueueDiagnostics.enqueueAttempts, 4, "diagnostics enqueue attempts include missing queue")
assertEqual(missingQueueDiagnostics.enqueueFailed, 1, "diagnostics enqueue failures include missing queue")
assertEqual(
	missingQueueDiagnostics.lastEnqueueReason,
	"admission_queue_unavailable",
	"diagnostics missing queue enqueue reason"
)

serviceApi.ConfigureForTests({
	now = function()
		return 201
	end,
	admissionQueueApi = admissionQueueApi,
})
local invalidMembers = serviceApi.RequestPartyAdmission({
	partyId = "party-invalid-members",
	targetRealmId = "realm-17",
	memberUserIds = { -5 },
})
assertEqual(invalidMembers.accepted, false, "invalid members rejected")
assertEqual(invalidMembers.reason, "admission_party_members_invalid", "invalid members reason")
local invalidMembersDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(invalidMembersDiagnostics.enqueueAttempts, 5, "diagnostics enqueue attempts include invalid members")
assertEqual(invalidMembersDiagnostics.enqueueFailed, 2, "diagnostics enqueue failures include invalid members")
assertEqual(
	invalidMembersDiagnostics.lastEnqueueReason,
	"admission_party_members_invalid",
	"diagnostics invalid members enqueue reason"
)

serviceApi.ConfigureForTests({
	now = function()
		return 202
	end,
	admissionQueueApi = admissionQueueApi,
	targetRealmResolver = {},
})
resolverApi.ResetForTests()
globalEnv._PartyMatchmakingRealmResolver_QueryAPI = nil

local resolverUnavailable = serviceApi.RequestPartyAdmission({
	partyId = "party-no-resolver",
	memberUserIds = { 77 },
})
assertEqual(resolverUnavailable.accepted, false, "resolver unavailable rejected")
assertEqual(resolverUnavailable.reason, "target_realm_unavailable", "resolver unavailable reason")
assertEqual(#enqueuePayloads, 3, "resolver unavailable does not enqueue")
local resolverUnavailableDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(
	resolverUnavailableDiagnostics.resolverFailed >= 1,
	true,
	"diagnostics resolver failures include unavailable"
)
assertEqual(
	resolverUnavailableDiagnostics.lastResolverPath,
	"resolver_unavailable",
	"diagnostics resolver unavailable path"
)
assertEqual(
	resolverUnavailableDiagnostics.lastReason,
	"target_realm_unavailable",
	"diagnostics resolver unavailable reason"
)

serviceApi.ConfigureForTests({
	now = function()
		return 202
	end,
	admissionQueueApi = admissionQueueApi,
	targetRealmResolver = {
		ResolveTargetRealmId = function(_input: any)
			return {
				accepted = false,
				reason = "target_realm_missing",
			}
		end,
	},
})
local unresolvedRealm = serviceApi.RequestPartyAdmission({
	partyId = "party-no-realm",
	memberUserIds = { 5 },
})
assertEqual(unresolvedRealm.accepted, false, "unresolved realm rejected")
assertEqual(unresolvedRealm.reason, "target_realm_missing", "unresolved realm reason")
assertEqual(#enqueuePayloads, 3, "resolver rejection does not enqueue")
local unresolvedDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(unresolvedDiagnostics.lastResolverPath, "resolver_rejected", "diagnostics resolver rejected path")
assertEqual(unresolvedDiagnostics.lastResolverReason, "target_realm_missing", "diagnostics resolver rejected reason")
assertEqual(unresolvedDiagnostics.lastReason, "target_realm_missing", "diagnostics resolver rejected request reason")

serviceApi.ConfigureForTests({
	now = function()
		return 203
	end,
	admissionQueueApi = {
		EnqueueAdmission = function(_payload: any)
			return {
				accepted = false,
				reason = "queue_backpressure",
			}
		end,
	},
})
local enqueueRejected = serviceApi.RequestPartyAdmission({
	partyId = "party-backpressure",
	targetRealmId = "realm-17",
	memberUserIds = { 5 },
})
assertEqual(enqueueRejected.accepted, false, "enqueue rejection propagated")
assertEqual(enqueueRejected.reason, "queue_backpressure", "enqueue rejection reason")
local enqueueRejectedDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(enqueueRejectedDiagnostics.enqueueFailed >= 3, true, "diagnostics enqueue failures include backpressure")
assertEqual(enqueueRejectedDiagnostics.lastEnqueueReason, "queue_backpressure", "diagnostics enqueue rejection reason")

serviceApi.ConfigureForTests({
	now = function()
		return 204
	end,
	admissionQueueApi = {
		EnqueueAdmission = function(_payload: any)
			error("boom")
		end,
	},
})
local enqueueFailed = serviceApi.RequestPartyAdmission({
	partyId = "party-throw",
	targetRealmId = "realm-17",
	memberUserIds = { 5 },
})
assertEqual(enqueueFailed.accepted, false, "enqueue throw rejected")
assertEqual(enqueueFailed.reason, "admission_enqueue_failed", "enqueue throw reason")
local enqueueFailedDiagnostics = serviceApi.GetAdmissionDiagnostics()
assertEqual(enqueueFailedDiagnostics.enqueueFailed >= 4, true, "diagnostics enqueue failures include throw")
assertEqual(enqueueFailedDiagnostics.lastEnqueueReason, "admission_enqueue_failed", "diagnostics enqueue throw reason")
assertEqual(enqueueFailedDiagnostics.lastReason, "admission_enqueue_failed", "diagnostics enqueue throw last reason")

serviceApi.ResetForTests()
resetGlobals()

print("party_matchmaking_admission_service_runtime_entrypoint: all checks passed")
