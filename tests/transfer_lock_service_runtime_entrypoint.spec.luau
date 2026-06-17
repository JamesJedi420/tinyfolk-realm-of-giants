--!nocheck

local TransferLockService = require("../src/ServerScriptService/Services/TransferLockService")

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

TransferLockService.ResetForTests()
TransferLockService.ConfigureForTests({
	now = function(): number
		return 100
	end,
})

local firstAcquire = TransferLockService.TryAcquire("op-1")
assertTrue(firstAcquire, "first acquire accepted")

local duplicateAcquire = TransferLockService.TryAcquire("op-1")
assertEqual(duplicateAcquire, false, "duplicate acquire rejected")
local diagnosticsAfterDuplicate = TransferLockService.GetDiagnostics()
assertEqual(diagnosticsAfterDuplicate.acquireAttempts, 2, "acquire attempts include duplicate")
assertEqual(diagnosticsAfterDuplicate.acquireSucceeded, 1, "acquire success count")
assertEqual(diagnosticsAfterDuplicate.acquireFailed, 1, "acquire failed count")
assertEqual(diagnosticsAfterDuplicate.failedAcquireCount, 1, "failed acquire count")
assertEqual(diagnosticsAfterDuplicate.lastReason, "transfer_lock_active", "duplicate reason")

TransferLockService.Release("op-1")
local acquireAfterRelease = TransferLockService.TryAcquire("op-1")
assertTrue(acquireAfterRelease, "acquire after release accepted")

TransferLockService.ResetForTests()
TransferLockService.ConfigureForTests({
	now = function(): number
		return 100
	end,
})

assertTrue(TransferLockService.TryAcquire("op-expire", 100), "acquire with explicit now accepted")
assertEqual(TransferLockService.TryAcquire("op-expire", 120), false, "lock still active before ttl")
assertTrue(TransferLockService.TryAcquire("op-expire", 191), "lock re-acquired after ttl expiry")

assertEqual(TransferLockService.TryAcquire("", 200), false, "empty operation id rejected")
assertEqual(TransferLockService.TryAcquire(nil, 200), false, "nil operation id rejected")
local diagnosticsAfterInvalid = TransferLockService.GetDiagnostics()
assertEqual(diagnosticsAfterInvalid.lastReason, "operation_id_invalid", "invalid operation reason")
assertTrue(diagnosticsAfterInvalid.failedAcquireCount >= 2, "invalid operations counted")

print("transfer_lock_service_runtime_entrypoint: all checks passed")
