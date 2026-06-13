local CaptivityDurationState = require("../src/ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState")

local function assertEqual(actual: any, expected: any, message: string)
	if actual ~= expected then
		error(string.format("%s (expected=%s actual=%s)", message, tostring(expected), tostring(actual)))
	end
	print("PASS [" .. message .. "]")
end

local function assertTrue(value: any, message: string)
	if value ~= true then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function assertFalse(value: any, message: string)
	if value ~= false then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function makeRecord(overrides: any?): any
	local record = {
		custodianUserId = 100,
		targetUserId = 200,
		startedAt = 10,
		expiresAt = 18,
		captivityAnchorAt = 10,
		containmentPhase = CaptivityDurationState.Phases.captured,
		containedAt = nil,
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			record[key] = value
		end
	end
	return record
end

assertTrue(CaptivityDurationState.GetMaxCapturedDurationSeconds(nil) >= 8, "max captured duration configured")
assertTrue(CaptivityDurationState.GetMaxContainedDurationSeconds(nil) >= 8, "max contained duration configured")

local valid = CaptivityDurationState.ValidateRecordBounds(makeRecord(), nil)
assertTrue(valid.accepted == true, "valid record bounds accepted")

local tooLong = CaptivityDurationState.ValidateRecordBounds(makeRecord({ expiresAt = 30 }), nil)
assertFalse(tooLong.accepted == true, "record bounds reject excessive window")
assertEqual(tooLong.reason, "capture_record_duration_exceeds_max", "record bounds reason")

local windowTimeout = CaptivityDurationState.ResolveTimeout(makeRecord(), 18, nil)
assertTrue(windowTimeout.shouldEnd == true, "window timeout ends custody")
assertEqual(windowTimeout.custodyEndReason, "timeout", "window timeout custody reason")
assertEqual(windowTimeout.fallbackEndReason, "safe_return", "window timeout fallback reason")

local pending = CaptivityDurationState.ResolveTimeout(makeRecord(), 12, nil)
assertFalse(pending.shouldEnd == true, "timeout not due before deadline")

local containedRecord = makeRecord({
	containmentPhase = CaptivityDurationState.Phases.contained,
	containedAt = 15,
	expiresAt = 22,
	captivityAnchorAt = 10,
})
local containedTimeout = CaptivityDurationState.ResolveTimeout(containedRecord, 21, {
	MaxCapturedDurationSeconds = 12,
	MaxContainedDurationSeconds = 5,
})
assertTrue(containedTimeout.shouldEnd == true, "contained duration cap ends custody")

local transfer = CaptivityDurationState.ResolveTransfer({
	record = makeRecord(),
	newCustodianUserId = 300,
	now = 12,
}, nil)
assertTrue(transfer.accepted == true, "transfer accepted")
assertEqual(transfer.record.custodianUserId, 300, "transfer updates custodian")
assertEqual(transfer.record.startedAt, 10, "transfer preserves startedAt")
assertEqual(transfer.record.captivityAnchorAt, 10, "transfer preserves captivity anchor")
assertEqual(transfer.record.expiresAt, 18, "transfer preserves expiresAt")

local exhaustedTransfer = CaptivityDurationState.ResolveTransfer({
	record = makeRecord(),
	newCustodianUserId = 300,
	now = 23,
}, nil)
assertFalse(exhaustedTransfer.accepted == true, "transfer rejected after captivity exhausted")
assertEqual(exhaustedTransfer.reason, "captivity_duration_exhausted", "transfer exhausted reason")

print("captivity_duration_state: all checks passed")
