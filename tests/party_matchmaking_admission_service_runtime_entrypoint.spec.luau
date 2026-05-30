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

local queueAccepted = serviceApi.RequestPartyMatchAdmission({
	partyId = "party-queue-alpha",
	targetRealmId = "realm-17",
	memberUserIds = { 88, 77, 88 },
})
assertEqual(queueAccepted.accepted, true, "queue-match accepted")
assertEqual(queueAccepted.reason, "accepted", "queue-match accepted reason")
assertEqual(queueAccepted.payload.entryType, "matchmaking_queue", "queue-match entry type")
assertEqual(queueAccepted.payload.partySize, 2, "queue-match deduped party size")
assertEqual(queueAccepted.payload.operationId, "party_queue_match_party-queue-alpha_123000", "queue-match operation id")
assertEqual(queueAccepted.payload.partyMemberUserIds[1], 77, "queue-match normalized member ordering first")
assertEqual(queueAccepted.payload.partyMemberUserIds[2], 88, "queue-match normalized member ordering second")
assertEqual(#enqueuePayloads, 2, "queue-match enqueue invoked")

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

serviceApi.ResetForTests()
resetGlobals()

print("party_matchmaking_admission_service_runtime_entrypoint: all checks passed")
