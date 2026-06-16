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
	globalEnv._ProfileTeleportAdmissionService_QueryAPI = nil
	globalEnv._RealmAdmissionQueue_QueryAPI = nil
end

resetGlobals()
require("../src/ServerScriptService/Services/ProfileTeleportAdmissionService.server")

local serviceApi = globalEnv._ProfileTeleportAdmissionService_QueryAPI
assertTrue(type(serviceApi) == "table", "service query api published")
assertTrue(type(serviceApi.RequestTeleportHandoffAdmission) == "function", "request function published")
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
		return 456
	end,
	admissionQueueApi = admissionQueueApi,
})

local accepted = serviceApi.RequestTeleportHandoffAdmission({
	userId = 8101,
	handoffToken = "handoff_token_1",
	targetRealmId = "realm-42",
})
assertEqual(accepted.accepted, true, "accepted teleport admission")
assertEqual(accepted.reason, "accepted", "accepted reason")
assertEqual(accepted.payload.entryType, "direct_invite", "accepted entry type")
assertEqual(accepted.payload.operationId, "handoff_token_1", "operation id defaults to handoff token")
assertEqual(
	accepted.payload.partyId,
	"handoff_party:8101:handoff_token_1",
	"party id defaults to deterministic handoff format"
)
assertEqual(accepted.payload.partyMemberUserIds[1], 8101, "single handoff member id")
assertEqual(accepted.payload.targetRealmId, "realm-42", "target realm propagated")
assertEqual(#enqueuePayloads, 1, "enqueue invoked once")
local diagnosticsAfterAccepted = serviceApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterAccepted.enqueueAttempts, 1, "accepted diagnostics enqueue attempts")
assertEqual(diagnosticsAfterAccepted.enqueueSucceeded, 1, "accepted diagnostics enqueue success")
assertEqual(diagnosticsAfterAccepted.enqueueFailed, 0, "accepted diagnostics enqueue failures")
assertEqual(diagnosticsAfterAccepted.lastReason, "accepted", "accepted diagnostics last reason")

local explicit = serviceApi.RequestTeleportHandoffAdmission({
	userId = 8102,
	handoffToken = "handoff_token_2",
	operationId = "operation_custom_2",
	partyId = "party_custom_2",
	targetRealmId = "realm-43",
})
assertEqual(explicit.accepted, true, "explicit payload accepted")
assertEqual(explicit.payload.operationId, "operation_custom_2", "explicit operation id preserved")
assertEqual(explicit.payload.partyId, "party_custom_2", "explicit party id preserved")
local diagnosticsAfterExplicit = serviceApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterExplicit.enqueueAttempts, 2, "explicit diagnostics enqueue attempts")
assertEqual(diagnosticsAfterExplicit.enqueueSucceeded, 2, "explicit diagnostics enqueue success")
assertEqual(diagnosticsAfterExplicit.lastReason, "accepted", "explicit diagnostics last reason")

serviceApi.ConfigureForTests({
	now = function()
		return 457
	end,
	admissionQueueApi = nil,
})
local missingQueue = serviceApi.RequestTeleportHandoffAdmission({
	userId = 8103,
	handoffToken = "handoff_token_missing_queue",
	targetRealmId = "realm-44",
})
assertEqual(missingQueue.accepted, false, "missing queue rejected")
assertEqual(missingQueue.reason, "admission_queue_unavailable", "missing queue reason")
local diagnosticsAfterMissingQueue = serviceApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterMissingQueue.enqueueAttempts, 3, "missing queue diagnostics enqueue attempts")
assertEqual(diagnosticsAfterMissingQueue.enqueueSucceeded, 2, "missing queue diagnostics enqueue success")
assertEqual(diagnosticsAfterMissingQueue.enqueueFailed, 1, "missing queue diagnostics enqueue failures")
assertEqual(
	diagnosticsAfterMissingQueue.lastReason,
	"admission_queue_unavailable",
	"missing queue diagnostics last reason"
)

serviceApi.ConfigureForTests({
	now = function()
		return 458
	end,
	admissionQueueApi = admissionQueueApi,
})
local invalidUser = serviceApi.RequestTeleportHandoffAdmission({
	userId = -4,
	handoffToken = "handoff_token_invalid_user",
	targetRealmId = "realm-44",
})
assertEqual(invalidUser.accepted, false, "invalid user rejected")
assertEqual(invalidUser.reason, "admission_user_id_invalid", "invalid user reason")
local diagnosticsAfterInvalidUser = serviceApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterInvalidUser.enqueueAttempts, 3, "invalid user diagnostics enqueue attempts unchanged")
assertEqual(diagnosticsAfterInvalidUser.enqueueFailed, 1, "invalid user diagnostics enqueue failures unchanged")
assertEqual(diagnosticsAfterInvalidUser.lastReason, "admission_user_id_invalid", "invalid user diagnostics last reason")

local invalidToken = serviceApi.RequestTeleportHandoffAdmission({
	userId = 8104,
	targetRealmId = "realm-44",
})
assertEqual(invalidToken.accepted, false, "invalid token rejected")
assertEqual(invalidToken.reason, "handoff_token_invalid", "invalid token reason")
local diagnosticsAfterInvalidToken = serviceApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterInvalidToken.enqueueAttempts, 3, "invalid token diagnostics enqueue attempts unchanged")
assertEqual(diagnosticsAfterInvalidToken.enqueueFailed, 1, "invalid token diagnostics enqueue failures unchanged")
assertEqual(diagnosticsAfterInvalidToken.lastReason, "handoff_token_invalid", "invalid token diagnostics last reason")

serviceApi.ConfigureForTests({
	now = function()
		return 459
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
local enqueueRejected = serviceApi.RequestTeleportHandoffAdmission({
	userId = 8105,
	handoffToken = "handoff_token_rejected",
	targetRealmId = "realm-45",
})
assertEqual(enqueueRejected.accepted, false, "enqueue rejection propagated")
assertEqual(enqueueRejected.reason, "queue_backpressure", "enqueue rejection reason")
local diagnosticsAfterRejected = serviceApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterRejected.enqueueAttempts, 4, "rejected diagnostics enqueue attempts")
assertEqual(diagnosticsAfterRejected.enqueueSucceeded, 2, "rejected diagnostics enqueue success")
assertEqual(diagnosticsAfterRejected.enqueueFailed, 2, "rejected diagnostics enqueue failures")
assertEqual(diagnosticsAfterRejected.lastReason, "queue_backpressure", "rejected diagnostics last reason")

local permissionFactory = require("../src/ServerScriptService/Services/RealmPermissionService.server")
permissionFactory(game, {
	listLiveRealmAvailability = function(_limit: number?, _at: number?): { any }
		return {
			{
				realmId = "realm-locked-teleport",
				ownerUserId = 9901,
				privateServerId = "ps-locked-teleport",
				accessMode = "private",
				playerCount = 1,
				capacity = 8,
				dangerRating = 0.5,
				lifecycle = "active",
				isAvailable = true,
				updatedAt = 200,
			},
		}
	end,
})
serviceApi.ConfigureForTests({
	now = function()
		return 460
	end,
	admissionQueueApi = admissionQueueApi,
	listLiveRealmAvailability = function(_limit: number?, _at: number?): { any }
		return {
			{
				realmId = "realm-locked-teleport",
				ownerUserId = 9901,
				privateServerId = "ps-locked-teleport",
				accessMode = "private",
				playerCount = 1,
				capacity = 8,
				dangerRating = 0.5,
				lifecycle = "active",
				isAvailable = true,
				updatedAt = 200,
			},
		}
	end,
})
local lockedRejected = serviceApi.RequestTeleportHandoffAdmission({
	userId = 8106,
	handoffToken = "handoff_token_locked",
	targetRealmId = "realm-locked-teleport",
})
assertEqual(lockedRejected.accepted, false, "locked realm teleport admission rejected")
assertEqual(lockedRejected.reason, "realm_access_locked", "locked realm teleport rejection reason")
local diagnosticsAfterLocked = serviceApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterLocked.enqueueAttempts, 4, "locked realm does not enqueue")
assertEqual(diagnosticsAfterLocked.lastReason, "realm_access_locked", "locked realm diagnostics reason")

serviceApi.ResetForTests()
resetGlobals()

print("profile_teleport_admission_service_runtime_entrypoint: all checks passed")
