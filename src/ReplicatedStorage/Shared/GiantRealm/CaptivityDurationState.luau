--!strict

local CaptivityDurationState: any = {}

CaptivityDurationState.Phases = {
	captured = "captured",
	contained = "contained",
}

local DEFAULT_MAX_CAPTURED_DURATION_SECONDS = 12
local DEFAULT_MAX_CONTAINED_DURATION_SECONDS = 12

do
	local ok, captureConfig = pcall(require, "../Config/CaptureConfig")
	if ok and type(captureConfig) == "table" then
		local configAny = captureConfig :: any
		local maxCaptured = configAny.MaxCapturedDurationSeconds or configAny.MaxCustodyDurationSeconds
		if
			type(maxCaptured) == "number"
			and maxCaptured == maxCaptured
			and maxCaptured > 0
			and maxCaptured < math.huge
		then
			DEFAULT_MAX_CAPTURED_DURATION_SECONDS = maxCaptured
		end
		local maxContained = configAny.MaxContainedDurationSeconds
		if
			type(maxContained) == "number"
			and maxContained == maxContained
			and maxContained > 0
			and maxContained < math.huge
		then
			DEFAULT_MAX_CONTAINED_DURATION_SECONDS = maxContained
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

local function getCaptivityAnchorAt(record: any): number?
	if type(record) ~= "table" then
		return nil
	end
	if isFiniteNumber(record.captivityAnchorAt) then
		return record.captivityAnchorAt
	end
	if isFiniteNumber(record.startedAt) then
		return record.startedAt
	end
	return nil
end

local function getContainmentPhase(record: any): string
	if type(record) ~= "table" then
		return CaptivityDurationState.Phases.captured
	end
	if record.containmentPhase == CaptivityDurationState.Phases.contained then
		return CaptivityDurationState.Phases.contained
	end
	return CaptivityDurationState.Phases.captured
end

function CaptivityDurationState.GetMaxCapturedDurationSeconds(config: any?): number
	local value = if config ~= nil
		then (config :: any).MaxCapturedDurationSeconds or (config :: any).MaxCustodyDurationSeconds
		else nil
	if isFiniteNumber(value) and (value :: number) > 0 then
		return value :: number
	end
	return DEFAULT_MAX_CAPTURED_DURATION_SECONDS
end

function CaptivityDurationState.GetMaxContainedDurationSeconds(config: any?): number
	local value = if config ~= nil then (config :: any).MaxContainedDurationSeconds else nil
	if isFiniteNumber(value) and (value :: number) > 0 then
		return value :: number
	end
	return DEFAULT_MAX_CONTAINED_DURATION_SECONDS
end

function CaptivityDurationState.ValidateRecordBounds(record: any, config: any?): any
	if type(record) ~= "table" then
		return {
			accepted = false,
			reason = "capture_record_invalid",
		}
	end

	local anchorAt = getCaptivityAnchorAt(record)
	if not isFiniteNumber(anchorAt) or not isFiniteNumber(record.expiresAt) then
		return {
			accepted = false,
			reason = "capture_record_timing_invalid",
		}
	end

	local maxCaptured = CaptivityDurationState.GetMaxCapturedDurationSeconds(config)
	if (record.expiresAt :: number) > (anchorAt :: number) + maxCaptured then
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

function CaptivityDurationState.ResolveAbsoluteDeadline(record: any, config: any?): number?
	local anchorAt = getCaptivityAnchorAt(record)
	if not isFiniteNumber(anchorAt) then
		return nil
	end

	local maxCaptured = CaptivityDurationState.GetMaxCapturedDurationSeconds(config)
	local capturedDeadline = (anchorAt :: number) + maxCaptured

	local phase = getContainmentPhase(record)
	if phase == CaptivityDurationState.Phases.contained and isFiniteNumber(record.containedAt) then
		local maxContained = CaptivityDurationState.GetMaxContainedDurationSeconds(config)
		local containedDeadline = (record.containedAt :: number) + maxContained
		return math.min(capturedDeadline, containedDeadline, record.expiresAt)
	end

	return math.min(capturedDeadline, record.expiresAt)
end

function CaptivityDurationState.IsRecordExpired(record: any, now: any, config: any?): boolean
	if not isFiniteNumber(now) then
		return false
	end

	local deadline = CaptivityDurationState.ResolveAbsoluteDeadline(record, config)
	if not isFiniteNumber(deadline) then
		return false
	end

	return (deadline :: number) <= (now :: number)
end

function CaptivityDurationState.ResolveTimeout(record: any, now: any, config: any?): any
	local bounds = CaptivityDurationState.ValidateRecordBounds(record, config)
	if bounds.accepted ~= true then
		return {
			accepted = false,
			reason = bounds.reason,
			shouldEnd = false,
			custodyEndReason = nil,
			fallbackEndReason = nil,
		}
	end

	if not isFiniteNumber(now) then
		return {
			accepted = false,
			reason = "capture_record_now_invalid",
			shouldEnd = false,
			custodyEndReason = nil,
			fallbackEndReason = nil,
		}
	end

	if CaptivityDurationState.IsRecordExpired(record, now, config) then
		return {
			accepted = true,
			reason = "timeout_due",
			shouldEnd = true,
			custodyEndReason = "timeout",
			fallbackEndReason = "safe_return",
		}
	end

	return {
		accepted = true,
		reason = "timeout_not_due",
		shouldEnd = false,
		custodyEndReason = nil,
		fallbackEndReason = nil,
	}
end

function CaptivityDurationState.ResolveTransfer(input: any, config: any?): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "transfer_input_invalid",
			record = nil,
		}
	end

	local record = input.record
	local newCustodianUserId = input.newCustodianUserId
	local now = input.now

	if type(record) ~= "table" then
		return {
			accepted = false,
			reason = "capture_record_invalid",
			record = nil,
		}
	end
	if not isPositiveInteger(newCustodianUserId) then
		return {
			accepted = false,
			reason = "transfer_custodian_invalid",
			record = nil,
		}
	end
	if not isFiniteNumber(now) then
		return {
			accepted = false,
			reason = "transfer_now_invalid",
			record = nil,
		}
	end
	if record.custodianUserId == newCustodianUserId then
		return {
			accepted = false,
			reason = "transfer_custodian_unchanged",
			record = nil,
		}
	end

	local anchorAt = getCaptivityAnchorAt(record)
	if not isFiniteNumber(anchorAt) or not isFiniteNumber(record.expiresAt) then
		return {
			accepted = false,
			reason = "capture_record_timing_invalid",
			record = nil,
		}
	end

	local maxCaptured = CaptivityDurationState.GetMaxCapturedDurationSeconds(config)
	local absoluteDeadline = (anchorAt :: number) + maxCaptured
	if (now :: number) >= absoluteDeadline then
		return {
			accepted = false,
			reason = "captivity_duration_exhausted",
			record = nil,
		}
	end

	local cappedExpiresAt = math.min(record.expiresAt, absoluteDeadline)
	local transferredRecord = {
		custodianUserId = newCustodianUserId,
		targetUserId = record.targetUserId,
		startedAt = record.startedAt,
		expiresAt = cappedExpiresAt,
		captivityAnchorAt = anchorAt,
		containmentPhase = getContainmentPhase(record),
		containedAt = record.containedAt,
	}

	local validation = CaptivityDurationState.ValidateRecordBounds(transferredRecord, config)
	if validation.accepted ~= true then
		return {
			accepted = false,
			reason = validation.reason,
			record = nil,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		record = transferredRecord,
	}
end

return CaptivityDurationState
