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
	globalEnv._RescueAdmissionService_QueryAPI = nil
	globalEnv._RealmAdmissionQueue_QueryAPI = nil
end

resetGlobals()
require("../src/ServerScriptService/Services/RescueAdmissionService.server")

local serviceApi = globalEnv._RescueAdmissionService_QueryAPI
assertTrue(type(serviceApi) == "table", "service query api published")
assertTrue(type(serviceApi.RequestRescueContractAdmission) == "function", "request function published")

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
		return 321
	end,
	admissionQueueApi = admissionQueueApi,
})

local accepted = serviceApi.RequestRescueContractAdmission({
	partyId = "rescue-party-alpha",
	targetRealmId = "realm-77",
	partyMemberUserIds = { 7101, 7102, 7103 },
})
assertEqual(accepted.accepted, true, "accepted rescue admission")
assertEqual(accepted.reason, "accepted", "accepted reason")
assertEqual(accepted.payload.entryType, "rescue_contract", "forced rescue entry type")
assertEqual(accepted.payload.operationId, "rescue_admission_rescue-party-alpha_321000", "generated operation id")
assertEqual(accepted.payload.partySize, 3, "party size set")
assertEqual(accepted.payload.targetRealmId, "realm-77", "target realm applied")
assertEqual(#enqueuePayloads, 1, "enqueue invoked once")

local explicit = serviceApi.RequestRescueContractAdmission({
	operationId = "rescue_accept_queue_1",
	partyId = "rescue-party-bravo",
	targetRealmId = "realm-88",
	memberUserIds = { 7201, 7202, 7202 },
})
assertEqual(explicit.accepted, true, "explicit operation accepted")
assertEqual(explicit.payload.operationId, "rescue_accept_queue_1", "explicit operation id preserved")
assertEqual(explicit.payload.partyMemberUserIds[1], 7201, "normalized member first")
assertEqual(explicit.payload.partyMemberUserIds[2], 7202, "normalized member second")

serviceApi.ConfigureForTests({
	now = function()
		return 322
	end,
	admissionQueueApi = nil,
})
local missingQueue = serviceApi.RequestRescueContractAdmission({
	partyId = "rescue-party-no-queue",
	targetRealmId = "realm-77",
	memberUserIds = { 1 },
})
assertEqual(missingQueue.accepted, false, "missing queue rejected")
assertEqual(missingQueue.reason, "admission_queue_unavailable", "missing queue reason")

serviceApi.ConfigureForTests({
	now = function()
		return 323
	end,
	admissionQueueApi = admissionQueueApi,
})
local invalidMembers = serviceApi.RequestRescueContractAdmission({
	partyId = "rescue-party-invalid-members",
	targetRealmId = "realm-77",
	memberUserIds = { -9 },
})
assertEqual(invalidMembers.accepted, false, "invalid members rejected")
assertEqual(invalidMembers.reason, "admission_party_members_invalid", "invalid members reason")

serviceApi.ConfigureForTests({
	now = function()
		return 324
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
local enqueueRejected = serviceApi.RequestRescueContractAdmission({
	partyId = "rescue-party-backpressure",
	targetRealmId = "realm-77",
	memberUserIds = { 5 },
})
assertEqual(enqueueRejected.accepted, false, "enqueue rejection propagated")
assertEqual(enqueueRejected.reason, "queue_backpressure", "enqueue rejection reason")

serviceApi.ResetForTests()
resetGlobals()

print("rescue_admission_service_runtime_entrypoint: all checks passed")
