--!strict

local CapturePersistenceRules: any = {}

CapturePersistenceRules.SCHEMA_VERSION = 1

CapturePersistenceRules.StorageOwner = "session_runtime"

CapturePersistenceRules.CustodyEndReasons = {
	released = "released",
	rescued = "rescued",
	escaped = "escaped",
	timeout = "timeout",
	logout = "logout",
	safe_return = "safe_return",
	starvation = "starvation",
}

CapturePersistenceRules.ProhibitedEndReasons = {
	sold = "sold",
	deleted = "deleted",
	account_lock = "account_lock",
	permanent = "permanent",
}

CapturePersistenceRules.EscapeActions = {
	escape_route = "escape_route",
	rescue_contract = "rescue_contract",
	counterplay = "counterplay",
	custodian_release = "custodian_release",
	timeout_release = "timeout_release",
	starvation_release = "starvation_release",
	safe_return = "safe_return",
}

local validCustodyEndReasons = {
	[CapturePersistenceRules.CustodyEndReasons.released] = true,
	[CapturePersistenceRules.CustodyEndReasons.rescued] = true,
	[CapturePersistenceRules.CustodyEndReasons.escaped] = true,
	[CapturePersistenceRules.CustodyEndReasons.timeout] = true,
	[CapturePersistenceRules.CustodyEndReasons.logout] = true,
	[CapturePersistenceRules.CustodyEndReasons.safe_return] = true,
	[CapturePersistenceRules.CustodyEndReasons.starvation] = true,
}

local prohibitedEndReasons = {
	[CapturePersistenceRules.ProhibitedEndReasons.sold] = true,
	[CapturePersistenceRules.ProhibitedEndReasons.deleted] = true,
	[CapturePersistenceRules.ProhibitedEndReasons.account_lock] = true,
	[CapturePersistenceRules.ProhibitedEndReasons.permanent] = true,
}

local allowedEscapeActions = {
	[CapturePersistenceRules.EscapeActions.escape_route] = true,
	[CapturePersistenceRules.EscapeActions.rescue_contract] = true,
	[CapturePersistenceRules.EscapeActions.counterplay] = true,
	[CapturePersistenceRules.EscapeActions.custodian_release] = true,
	[CapturePersistenceRules.EscapeActions.timeout_release] = true,
	[CapturePersistenceRules.EscapeActions.starvation_release] = true,
	[CapturePersistenceRules.EscapeActions.safe_return] = true,
}

local DEFAULT_MAX_CUSTODY_DURATION_SECONDS = 12
local DEFAULT_CUSTODY_WINDOW_SECONDS = 8

do
	local ok, captureConfig = pcall(require, "../Config/CaptureConfig")
	if ok and type(captureConfig) == "table" then
		local maxWindow = (captureConfig :: any).MaxCustodyDurationSeconds
		if type(maxWindow) == "number" and maxWindow == maxWindow and maxWindow > 0 and maxWindow < math.huge then
			DEFAULT_MAX_CUSTODY_DURATION_SECONDS = maxWindow
		end
		local custodyWindow = (captureConfig :: any).CustodyWindowSeconds
		if
			type(custodyWindow) == "number"
			and custodyWindow == custodyWindow
			and custodyWindow > 0
			and custodyWindow < math.huge
		then
			DEFAULT_CUSTODY_WINDOW_SECONDS = custodyWindow
		end
	end
end

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
end

function CapturePersistenceRules.GetStorageOwner(): string
	return CapturePersistenceRules.StorageOwner
end

function CapturePersistenceRules.AllowsProfilePersistence(): boolean
	return false
end

function CapturePersistenceRules.GetMaxCustodyDurationSeconds(): number
	return DEFAULT_MAX_CUSTODY_DURATION_SECONDS
end

function CapturePersistenceRules.GetDefaultCustodyWindowSeconds(): number
	return DEFAULT_CUSTODY_WINDOW_SECONDS
end

function CapturePersistenceRules.IsValidCustodyEndReason(endReason: any): boolean
	return type(endReason) == "string" and validCustodyEndReasons[endReason] == true
end

function CapturePersistenceRules.IsProhibitedCustodyEndReason(endReason: any): boolean
	return type(endReason) == "string" and prohibitedEndReasons[endReason] == true
end

function CapturePersistenceRules.ValidateCustodyEndReason(endReason: any): any
	if CapturePersistenceRules.IsProhibitedCustodyEndReason(endReason) then
		return {
			accepted = false,
			reason = "end_reason_prohibited",
		}
	end
	if not CapturePersistenceRules.IsValidCustodyEndReason(endReason) then
		return {
			accepted = false,
			reason = "end_reason_invalid",
		}
	end
	return {
		accepted = true,
		reason = "accepted",
	}
end

function CapturePersistenceRules.ValidateCaptureRecord(record: any, now: any): any
	if type(record) ~= "table" then
		return {
			accepted = false,
			reason = "capture_record_invalid",
		}
	end
	if not isPositiveInteger(record.custodianUserId) then
		return {
			accepted = false,
			reason = "capture_record_custodian_invalid",
		}
	end
	if not isPositiveInteger(record.targetUserId) then
		return {
			accepted = false,
			reason = "capture_record_target_invalid",
		}
	end
	if record.custodianUserId == record.targetUserId then
		return {
			accepted = false,
			reason = "capture_record_self_capture",
		}
	end
	if not isFiniteNumber(record.startedAt) or record.startedAt < 0 then
		return {
			accepted = false,
			reason = "capture_record_started_at_invalid",
		}
	end
	if not isFiniteNumber(record.expiresAt) or record.expiresAt <= record.startedAt then
		return {
			accepted = false,
			reason = "capture_record_expires_at_invalid",
		}
	end
	if not isFiniteNumber(now) or now < 0 then
		return {
			accepted = false,
			reason = "capture_record_now_invalid",
		}
	end

	local maxDuration = CapturePersistenceRules.GetMaxCustodyDurationSeconds()
	if (record.expiresAt - record.startedAt) > maxDuration then
		return {
			accepted = false,
			reason = "capture_record_duration_exceeds_max",
		}
	end

	return {
		accepted = true,
		reason = "accepted",
	}
end

function CapturePersistenceRules.IsRecordExpired(record: any, now: any): boolean
	if type(record) ~= "table" or not isFiniteNumber(record.expiresAt) or not isFiniteNumber(now) then
		return false
	end
	return record.expiresAt <= now
end

function CapturePersistenceRules.ResolveTimeout(record: any, now: any): any
	local validation = CapturePersistenceRules.ValidateCaptureRecord(record, now)
	if validation.accepted ~= true then
		return {
			accepted = false,
			reason = validation.reason,
			shouldEnd = false,
			endReason = nil,
		}
	end

	if CapturePersistenceRules.IsRecordExpired(record, now) then
		return {
			accepted = true,
			reason = "timeout_due",
			shouldEnd = true,
			endReason = CapturePersistenceRules.CustodyEndReasons.timeout,
		}
	end

	return {
		accepted = true,
		reason = "timeout_not_due",
		shouldEnd = false,
		endReason = nil,
	}
end

function CapturePersistenceRules.ResolveLogout(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "logout_input_invalid",
		}
	end
	if not isPositiveInteger(input.userId) then
		return {
			accepted = false,
			reason = "logout_user_id_invalid",
		}
	end

	local recordsToClear: { any } = {}
	if type(input.records) == "table" then
		for _, record in ipairs(input.records) do
			if type(record) == "table" then
				if record.custodianUserId == input.userId or record.targetUserId == input.userId then
					table.insert(recordsToClear, record)
				end
			end
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		endReason = CapturePersistenceRules.CustodyEndReasons.logout,
		clearSessionRuntime = true,
		recordsToClear = recordsToClear,
	}
end

function CapturePersistenceRules.ResolveReconnectRestore(_input: any?): any
	return {
		accepted = true,
		reason = "capture_runtime_not_restored",
		action = "clear_capture_runtime",
		restoreCapture = false,
		clearSessionRuntime = true,
	}
end

function CapturePersistenceRules.ResolveProfileHydration(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "profile_hydration_input_invalid",
		}
	end

	if input.profileCaptureState ~= nil then
		return {
			accepted = true,
			reason = "reject_profile_capture_state",
			action = "clear_capture_runtime",
			restoreCapture = false,
			clearSessionRuntime = true,
		}
	end

	return {
		accepted = true,
		reason = "no_profile_capture_state",
		action = "skip_capture_runtime",
		restoreCapture = false,
		clearSessionRuntime = false,
	}
end

function CapturePersistenceRules.CanTargetPerformEscapeAction(action: any): boolean
	return type(action) == "string" and allowedEscapeActions[action] == true
end

return CapturePersistenceRules
