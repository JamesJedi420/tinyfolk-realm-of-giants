--!nocheck

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local EventStateOwnershipModel = require("../src/ReplicatedStorage/Shared/GiantRealm/EventStateOwnershipModel")
local globalEnv: any = getfenv()

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

ProfilePersistenceGateway.ResetForTests()

do
	local writeBackCalls: { any } = {}
	local reconnectCalls: { any } = {}

	local overrideModel = {
		ResolveWriteBackPlan = function(input: any): any
			table.insert(writeBackCalls, input)
			return {
				accepted = true,
				reason = "from_override_write_back",
				outcome = input.outcome,
			}
		end,
		ResolveReconnectRestore = function(input: any): any
			table.insert(reconnectCalls, input)
			return {
				accepted = true,
				reason = "from_override_reconnect",
				phase = input.phase,
			}
		end,
	}

	globalEnv._EventStateOwnershipModel_QueryAPI = overrideModel
	_G._EventStateOwnershipModel_QueryAPI = overrideModel

	local writeBackResult = ProfilePersistenceGateway.ResolveEventOutcomeWriteBack({
		outcome = EventStateOwnershipModel.Outcomes.capture,
	})
	assertEqual(writeBackResult.reason, "from_override_write_back", "gateway delegates write-back to contract seam")
	assertEqual(#writeBackCalls, 1, "override write-back called exactly once")
	assertEqual(
		writeBackCalls[1].outcome,
		EventStateOwnershipModel.Outcomes.capture,
		"override write-back input forwarded"
	)

	local reconnectResult = ProfilePersistenceGateway.ResolveReconnectRestoreAction({
		phase = "active",
		expectedSessionId = "s1",
		activeSessionId = "s1",
		hasSessionRuntime = true,
	})
	assertEqual(reconnectResult.reason, "from_override_reconnect", "gateway delegates reconnect to contract seam")
	assertEqual(#reconnectCalls, 1, "override reconnect called exactly once")
	assertEqual(reconnectCalls[1].phase, "active", "override reconnect input forwarded")
end

globalEnv._EventStateOwnershipModel_QueryAPI = nil
_G._EventStateOwnershipModel_QueryAPI = nil

do
	local outcomes = {
		EventStateOwnershipModel.Outcomes.capture,
		EventStateOwnershipModel.Outcomes.escape,
		EventStateOwnershipModel.Outcomes.defense,
		EventStateOwnershipModel.Outcomes.returnToRealm,
	}

	for _, outcome in ipairs(outcomes) do
		local directPlan = EventStateOwnershipModel.ResolveWriteBackPlan({ outcome = outcome })
		local gatewayPlan = ProfilePersistenceGateway.ResolveEventOutcomeWriteBack({ outcome = outcome })

		assertEqual(gatewayPlan.accepted, directPlan.accepted, "matrix accepted parity " .. outcome)
		assertEqual(gatewayPlan.reason, directPlan.reason, "matrix reason parity " .. outcome)
		assertEqual(
			gatewayPlan.scopes.playerProfile,
			directPlan.scopes.playerProfile,
			"matrix player scope " .. outcome
		)
		assertEqual(gatewayPlan.scopes.realmProfile, directPlan.scopes.realmProfile, "matrix realm scope " .. outcome)
		assertEqual(
			gatewayPlan.scopes.sessionRuntime,
			directPlan.scopes.sessionRuntime,
			"matrix session scope " .. outcome
		)
		assertEqual(gatewayPlan.sessionAction, directPlan.sessionAction, "matrix session action " .. outcome)
	end

	local invalidPlan = ProfilePersistenceGateway.ResolveEventOutcomeWriteBack({ outcome = "bad" })
	assertEqual(invalidPlan.accepted, false, "matrix invalid outcome rejected")
	assertEqual(invalidPlan.reason, "write_back_outcome_unknown", "matrix invalid outcome reason")
end

do
	local reconnectCases = {
		{
			label = "active matching with runtime",
			input = {
				phase = "active",
				expectedSessionId = "s1",
				activeSessionId = "s1",
				hasSessionRuntime = true,
			},
		},
		{
			label = "resolved matching",
			input = {
				phase = "resolved",
				expectedSessionId = "s1",
				activeSessionId = "s1",
				hasSessionRuntime = true,
			},
		},
		{
			label = "active mismatched session",
			input = {
				phase = "active",
				expectedSessionId = "s1",
				activeSessionId = "s2",
				hasSessionRuntime = true,
			},
		},
		{
			label = "no active session",
			input = {
				phase = "none",
			},
		},
	}

	for _, caseInfo in ipairs(reconnectCases) do
		local directAction = EventStateOwnershipModel.ResolveReconnectRestore(caseInfo.input)
		local gatewayAction = ProfilePersistenceGateway.ResolveReconnectRestoreAction(caseInfo.input)

		assertEqual(gatewayAction.accepted, directAction.accepted, "reconnect accepted parity " .. caseInfo.label)
		assertEqual(gatewayAction.reason, directAction.reason, "reconnect reason parity " .. caseInfo.label)
		assertEqual(gatewayAction.action, directAction.action, "reconnect action parity " .. caseInfo.label)
		assertEqual(
			gatewayAction.reapplySessionRuntime,
			directAction.reapplySessionRuntime,
			"reconnect reapply parity " .. caseInfo.label
		)
		assertEqual(
			gatewayAction.clearSessionRuntime,
			directAction.clearSessionRuntime,
			"reconnect clear parity " .. caseInfo.label
		)
	end

	local invalidReconnect = ProfilePersistenceGateway.ResolveReconnectRestoreAction({ phase = "invalid" })
	assertEqual(invalidReconnect.accepted, false, "reconnect invalid phase rejected")
	assertEqual(invalidReconnect.reason, "reconnect_phase_invalid", "reconnect invalid phase reason")
end

print("profile_persistence_gateway_runtime_entrypoint: all checks passed")
