--!strict

local CapturePersistenceRules = require("./CapturePersistenceRules")

local DisconnectResolutionState: any = {}

DisconnectResolutionState.Actions = {
	default_spawn = "default_spawn",
	spawn_safe_location = "spawn_safe_location",
	orchestrate_pending_handoff = "orchestrate_pending_handoff",
}

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function uniquePositiveIntegers(values: { any }): { number }
	local seen: { [number]: boolean } = {}
	local result: { number } = {}
	for _, value in ipairs(values) do
		if isPositiveInteger(value) and seen[value] ~= true then
			seen[value] = true
			table.insert(result, value)
		end
	end
	return result
end

function DisconnectResolutionState.ResolveLogout(input: any): any
	local basePlan = CapturePersistenceRules.ResolveLogout(input)
	if basePlan.accepted ~= true then
		return basePlan
	end

	local disconnectingUserId = if type(input) == "table" then input.userId else nil
	if not isPositiveInteger(disconnectingUserId) then
		return {
			accepted = false,
			reason = "logout_user_id_invalid",
		}
	end

	local recordsToClear = if type(basePlan.recordsToClear) == "table" then basePlan.recordsToClear else {}
	local targetsToSafeReturn: { number } = {}
	local persistReturnPending = false

	for _, record in ipairs(recordsToClear) do
		if type(record) == "table" then
			if record.custodianUserId == disconnectingUserId and record.targetUserId ~= disconnectingUserId then
				table.insert(targetsToSafeReturn, record.targetUserId)
			end
			if record.targetUserId == disconnectingUserId then
				persistReturnPending = true
			end
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		endReason = basePlan.endReason or CapturePersistenceRules.CustodyEndReasons.logout,
		clearSessionRuntime = basePlan.clearSessionRuntime == true,
		recordsToClear = recordsToClear,
		targetsToSafeReturn = uniquePositiveIntegers(targetsToSafeReturn),
		persistReturnPendingForDisconnectingUser = persistReturnPending,
	}
end

function DisconnectResolutionState.ResolveReconnect(input: any?): any
	local payload = if type(input) == "table" then input else {}
	if payload.restoreCaptureRequested == true then
		return {
			accepted = true,
			reason = "capture_runtime_not_restored",
			action = DisconnectResolutionState.Actions.default_spawn,
			restoreCapture = false,
			clearSessionRuntime = true,
		}
	end

	if payload.hasPendingRecovery == true then
		return {
			accepted = true,
			reason = "pending_recovery_handoff",
			action = DisconnectResolutionState.Actions.orchestrate_pending_handoff,
			restoreCapture = false,
			clearSessionRuntime = true,
		}
	end

	if payload.hasSafeLocation == true then
		return {
			accepted = true,
			reason = "safe_location_spawn",
			action = DisconnectResolutionState.Actions.spawn_safe_location,
			restoreCapture = false,
			clearSessionRuntime = true,
		}
	end

	return {
		accepted = true,
		reason = "default_spawn",
		action = DisconnectResolutionState.Actions.default_spawn,
		restoreCapture = false,
		clearSessionRuntime = payload.clearSessionRuntime == true,
	}
end

return DisconnectResolutionState
