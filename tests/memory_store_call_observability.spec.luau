--!nocheck

local MemoryStoreCallObservability = require("../src/ServerScriptService/Services/MemoryStoreCallObservability")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function _assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

MemoryStoreCallObservability.ResetForTests()

assertEqual(
	MemoryStoreCallObservability.ClassifyError("MemoryStore request was throttled. Try again."),
	"memory_store_throttled",
	"classify throttled"
)
assertEqual(
	MemoryStoreCallObservability.ClassifyError("Partition limit reached for structure"),
	"memory_store_partition_limit",
	"classify partition limit"
)
assertEqual(MemoryStoreCallObservability.ClassifyError("hash_map_unavailable"), "memory_store_other", "classify other")

local loggedMessages: { string } = {}
MemoryStoreCallObservability.ConfigureForTests({
	now = function()
		return 100
	end,
	warn = function(message: string)
		table.insert(loggedMessages, message)
	end,
})

MemoryStoreCallObservability.RecordFailure("QueueAddAsync", "tin_realm_admission_queue_v1", "request was throttled")
MemoryStoreCallObservability.RecordFailure("QueueAddAsync", "tin_realm_admission_queue_v1", "request was throttled")
MemoryStoreCallObservability.RecordFailure(
	"SortedMapSetAsync",
	"tin_live_realm_registry_v1",
	"partition limit exceeded"
)

local diagnostics = MemoryStoreCallObservability.GetDiagnostics()
assertEqual(diagnostics.throttledCount, 2, "throttled counter")
assertEqual(diagnostics.partitionLimitCount, 1, "partition counter")
assertEqual(diagnostics.totalFailures, 3, "total failures")
assertEqual(diagnostics.lastReason, "memory_store_partition_limit", "last reason")
assertEqual(diagnostics.lastOperation, "SortedMapSetAsync", "last operation")
assertEqual(#loggedMessages, 2, "coalesced duplicate throttle logs")

MemoryStoreCallObservability.ConfigureForTests({
	now = function()
		return 200
	end,
	warn = function(message: string)
		table.insert(loggedMessages, message)
	end,
})
MemoryStoreCallObservability.RecordFailure("QueueAddAsync", "tin_realm_admission_queue_v1", "request was throttled")
assertEqual(#loggedMessages, 3, "logs again after coalesce window")

MemoryStoreCallObservability.ResetForTests()
print("memory_store_call_observability: all checks passed")
