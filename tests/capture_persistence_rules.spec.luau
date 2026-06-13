--!strict

local CapturePersistenceRules = require("../src/ReplicatedStorage/Shared/GiantRealm/CapturePersistenceRules")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function makeRecord(startedAt: number, expiresAt: number): any
	return {
		custodianUserId = 100,
		targetUserId = 200,
		startedAt = startedAt,
		expiresAt = expiresAt,
	}
end

do
	assertEqual(CapturePersistenceRules.SCHEMA_VERSION, 1, "schema version")
	assertEqual(CapturePersistenceRules.GetStorageOwner(), "session_runtime", "storage owner")
	assertFalse(CapturePersistenceRules.AllowsProfilePersistence(), "no profile persistence")
	assertTrue(CapturePersistenceRules.GetMaxCustodyDurationSeconds() >= 8, "max duration configured")
end

do
	for _, reason in pairs(CapturePersistenceRules.CustodyEndReasons) do
		assertTrue(CapturePersistenceRules.IsValidCustodyEndReason(reason), "valid end reason " .. reason)
	end

	assertFalse(CapturePersistenceRules.IsValidCustodyEndReason("sold"), "sold invalid")
	assertTrue(CapturePersistenceRules.IsProhibitedCustodyEndReason("sold"), "sold prohibited")
	assertTrue(CapturePersistenceRules.IsProhibitedCustodyEndReason("account_lock"), "account lock prohibited")

	local valid = CapturePersistenceRules.ValidateCustodyEndReason("rescued")
	assertTrue(valid.accepted == true, "validate rescued accepted")
	assertEqual(valid.reason, "accepted", "validate rescued reason")

	local prohibited = CapturePersistenceRules.ValidateCustodyEndReason("permanent")
	assertFalse(prohibited.accepted == true, "validate permanent rejected")
	assertEqual(prohibited.reason, "end_reason_prohibited", "validate permanent reason")

	local invalid = CapturePersistenceRules.ValidateCustodyEndReason("unknown")
	assertFalse(invalid.accepted == true, "validate unknown rejected")
	assertEqual(invalid.reason, "end_reason_invalid", "validate unknown reason")
end

do
	local record = makeRecord(10, 18)
	local valid = CapturePersistenceRules.ValidateCaptureRecord(record, 12)
	assertTrue(valid.accepted == true, "record validates")

	local tooLong = makeRecord(0, CapturePersistenceRules.GetMaxCustodyDurationSeconds() + 5)
	local tooLongResult = CapturePersistenceRules.ValidateCaptureRecord(tooLong, 1)
	assertFalse(tooLongResult.accepted == true, "record duration capped")
	assertEqual(tooLongResult.reason, "capture_record_duration_exceeds_max", "record duration reason")
end

do
	local record = makeRecord(10, 18)
	assertFalse(CapturePersistenceRules.IsRecordExpired(record, 17), "not expired before window")
	assertTrue(CapturePersistenceRules.IsRecordExpired(record, 18), "expired at window")

	local timeout = CapturePersistenceRules.ResolveTimeout(record, 18)
	assertTrue(timeout.accepted == true, "timeout resolve accepted")
	assertTrue(timeout.shouldEnd == true, "timeout should end")
	assertEqual(timeout.endReason, CapturePersistenceRules.CustodyEndReasons.timeout, "timeout end reason")

	local pending = CapturePersistenceRules.ResolveTimeout(record, 12)
	assertTrue(pending.shouldEnd == false, "timeout not due yet")
end

do
	local logout = CapturePersistenceRules.ResolveLogout({
		userId = 100,
		records = {
			makeRecord(1, 9),
			{
				custodianUserId = 300,
				targetUserId = 400,
				startedAt = 2,
				expiresAt = 10,
			},
		},
	})
	assertTrue(logout.accepted == true, "logout accepted")
	assertEqual(logout.endReason, CapturePersistenceRules.CustodyEndReasons.logout, "logout end reason")
	assertTrue(logout.clearSessionRuntime == true, "logout clears runtime")
	assertEqual(#logout.recordsToClear, 1, "logout clears custodian record only")

	local targetLogout = CapturePersistenceRules.ResolveLogout({
		userId = 200,
		records = { makeRecord(1, 9) },
	})
	assertEqual(#targetLogout.recordsToClear, 1, "logout clears target record")
end

do
	local reconnect = CapturePersistenceRules.ResolveReconnectRestore(nil)
	assertTrue(reconnect.accepted == true, "reconnect accepted")
	assertFalse(reconnect.restoreCapture == true, "reconnect never restores capture")
	assertTrue(reconnect.clearSessionRuntime == true, "reconnect clears runtime")

	local hydration = CapturePersistenceRules.ResolveProfileHydration({
		profileCaptureState = { targetUserId = 1 },
	})
	assertTrue(hydration.accepted == true, "profile hydration accepted")
	assertFalse(hydration.restoreCapture == true, "profile hydration never restores")
	assertEqual(hydration.action, "clear_capture_runtime", "profile hydration clears")

	local emptyHydration = CapturePersistenceRules.ResolveProfileHydration({})
	assertEqual(emptyHydration.action, "skip_capture_runtime", "empty profile hydration skips")
end

do
	assertTrue(
		CapturePersistenceRules.CanTargetPerformEscapeAction(CapturePersistenceRules.EscapeActions.escape_route),
		"escape route allowed"
	)
	assertTrue(
		CapturePersistenceRules.CanTargetPerformEscapeAction(CapturePersistenceRules.EscapeActions.rescue_contract),
		"rescue allowed"
	)
	assertTrue(
		CapturePersistenceRules.CanTargetPerformEscapeAction(CapturePersistenceRules.EscapeActions.struggle),
		"struggle allowed"
	)
	assertTrue(
		CapturePersistenceRules.CanTargetPerformEscapeAction(CapturePersistenceRules.EscapeActions.ally_rescue_assist),
		"ally assist allowed"
	)
	assertFalse(CapturePersistenceRules.CanTargetPerformEscapeAction("delete_account"), "delete account blocked")
end

print("capture_persistence_rules: all checks passed")
