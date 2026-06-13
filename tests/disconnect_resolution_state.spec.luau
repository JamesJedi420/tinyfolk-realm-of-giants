--!strict

local CapturePersistenceRules = require("../src/ReplicatedStorage/Shared/GiantRealm/CapturePersistenceRules")
local DisconnectResolutionState = require("../src/ReplicatedStorage/Shared/GiantRealm/DisconnectResolutionState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertTableLength(value: { any }, expected: number, label: string)
	assertEqual(#value, expected, label)
end

do
	local logoutPlan = DisconnectResolutionState.ResolveLogout({
		userId = 100,
		records = {
			{ custodianUserId = 100, targetUserId = 200, startedAt = 1, expiresAt = 10 },
		},
	})
	assertTrue(logoutPlan.accepted, "custodian logout accepted")
	assertEqual(logoutPlan.endReason, CapturePersistenceRules.CustodyEndReasons.logout, "custodian logout end reason")
	assertTableLength(logoutPlan.targetsToSafeReturn, 1, "custodian logout queues one target safe return")
	assertEqual(logoutPlan.targetsToSafeReturn[1], 200, "custodian logout target user id")
	assertEqual(
		logoutPlan.persistReturnPendingForDisconnectingUser,
		false,
		"custodian logout does not persist return pending"
	)
end

do
	local logoutPlan = DisconnectResolutionState.ResolveLogout({
		userId = 200,
		records = {
			{ custodianUserId = 100, targetUserId = 200, startedAt = 1, expiresAt = 10 },
		},
	})
	assertTrue(logoutPlan.accepted, "target logout accepted")
	assertTableLength(logoutPlan.targetsToSafeReturn, 0, "target logout does not queue safe return")
	assertEqual(logoutPlan.persistReturnPendingForDisconnectingUser, true, "target logout persists return pending")
end

do
	local logoutPlan = DisconnectResolutionState.ResolveLogout({
		userId = 300,
		records = {
			{ custodianUserId = 300, targetUserId = 400, startedAt = 1, expiresAt = 10 },
			{ custodianUserId = 300, targetUserId = 401, startedAt = 1, expiresAt = 10 },
		},
	})
	assertTableLength(logoutPlan.targetsToSafeReturn, 2, "multi-target custodian logout queues both targets")
	assertEqual(logoutPlan.targetsToSafeReturn[1], 400, "first target safe return")
	assertEqual(logoutPlan.targetsToSafeReturn[2], 401, "second target safe return")
end

do
	local reconnectPlan = DisconnectResolutionState.ResolveReconnect({
		hasSafeLocation = true,
	})
	assertEqual(
		reconnectPlan.action,
		DisconnectResolutionState.Actions.spawn_safe_location,
		"safe location reconnect action"
	)
	assertTrue(reconnectPlan.clearSessionRuntime, "safe location reconnect clears session runtime")
end

do
	local reconnectPlan = DisconnectResolutionState.ResolveReconnect({
		hasPendingRecovery = true,
	})
	assertEqual(
		reconnectPlan.action,
		DisconnectResolutionState.Actions.orchestrate_pending_handoff,
		"pending recovery reconnect action"
	)
end

do
	local reconnectPlan = DisconnectResolutionState.ResolveReconnect({
		restoreCaptureRequested = true,
	})
	assertEqual(reconnectPlan.restoreCapture, false, "capture runtime not restored on reconnect")
	assertTrue(reconnectPlan.clearSessionRuntime, "reconnect clears session runtime when capture restore requested")
end

print("disconnect_resolution_state: all checks passed")
