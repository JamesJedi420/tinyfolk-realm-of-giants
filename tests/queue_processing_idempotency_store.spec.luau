--!strict

local QueueProcessingIdempotencyStore = require("../src/ServerScriptService/Services/QueueProcessingIdempotencyStore")
local MemoryStoreStructurePolicy = require("../src/ServerScriptService/Services/MemoryStoreStructurePolicy")

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

local function makeAdapter()
	local valuesByMap: { [string]: { [string]: any } } = {}
	local calls: { any } = {}
	local adapter = {
		HashMapUpdateAsync = function(mapName: string, key: string, transform: (any) -> any, ttlSeconds: number)
			table.insert(calls, {
				mapName = mapName,
				key = key,
				ttlSeconds = ttlSeconds,
			})
			if valuesByMap[mapName] == nil then
				valuesByMap[mapName] = {}
			end
			local nextValue = transform(valuesByMap[mapName][key])
			valuesByMap[mapName][key] = nextValue
			return nextValue
		end,
	}
	return adapter, calls, valuesByMap
end

do
	local nowAt = 100
	local adapter, calls, valuesByMap = makeAdapter()
	local store = QueueProcessingIdempotencyStore.Create({
		adapter = adapter,
		structurePolicy = MemoryStoreStructurePolicy,
		now = function(): number
			return nowAt
		end,
	})

	local begun = store.TryBegin("op-1")
	assertTrue(begun.accepted, "begin accepted")
	assertEqual(begun.status, "begun", "begin status")
	assertEqual(calls[1].mapName, "tin_queue_processing_idempotency_v1", "policy map name")
	assertEqual(calls[1].key, "queueop:op-1", "policy key")
	assertEqual(calls[1].ttlSeconds, 600, "policy ttl")

	local duplicateProcessing = store.TryBegin("op-1")
	assertEqual(duplicateProcessing.accepted, false, "processing duplicate rejected")
	assertEqual(duplicateProcessing.reason, "already_processing", "processing duplicate reason")
	assertEqual(duplicateProcessing.status, "processing", "processing duplicate status")

	nowAt = 110
	local released = store.ReleaseProcessing("op-1")
	assertTrue(released.accepted, "release accepted")
	assertEqual(valuesByMap.tin_queue_processing_idempotency_v1["queueop:op-1"], nil, "release clears record")

	local begunAgain = store.TryBegin("op-1")
	assertTrue(begunAgain.accepted, "begin after release accepted")
	assertEqual(begunAgain.status, "begun", "begin after release status")

	local completed = store.MarkCompleted("op-1")
	assertTrue(completed.accepted, "completed accepted")
	assertEqual(completed.status, "completed", "completed status")

	local duplicateCompleted = store.TryBegin("op-1")
	assertTrue(duplicateCompleted.accepted, "completed duplicate accepted for cleanup")
	assertEqual(duplicateCompleted.status, "completed", "completed duplicate status")
end

do
	local missingAdapterStore = QueueProcessingIdempotencyStore.Create({
		structurePolicy = MemoryStoreStructurePolicy,
	})
	local missingAdapterResult = missingAdapterStore.TryBegin("op-2")
	assertEqual(missingAdapterResult.accepted, false, "missing adapter rejected")
	assertEqual(missingAdapterResult.reason, "adapter_unavailable", "missing adapter reason")

	local missingPolicyStore = QueueProcessingIdempotencyStore.Create({
		adapter = makeAdapter(),
	})
	local missingPolicyResult = missingPolicyStore.TryBegin("op-3")
	assertEqual(missingPolicyResult.accepted, false, "missing policy rejected")
	assertEqual(missingPolicyResult.reason, "policy_unavailable", "missing policy reason")

	local invalidOperation = QueueProcessingIdempotencyStore.Create({
		adapter = makeAdapter(),
		structurePolicy = MemoryStoreStructurePolicy,
	}).TryBegin("")
	assertEqual(invalidOperation.accepted, false, "invalid operation rejected")
	assertEqual(invalidOperation.reason, "operation_id_invalid", "invalid operation reason")
end

do
	local adapter, calls = makeAdapter()
	local store = QueueProcessingIdempotencyStore.Create({
		adapter = adapter,
		structurePolicy = MemoryStoreStructurePolicy,
		structureId = "escapeOutcomeIdempotency",
	})
	local begun = store.TryBegin("escape-op-1")
	assertTrue(begun.accepted, "escape idempotency begin accepted")
	assertEqual(calls[1].mapName, "tin_escape_outcome_idempotency_v1", "escape policy map name")
	assertEqual(calls[1].key, "escapeop:escape-op-1", "escape policy key")
	assertEqual(calls[1].ttlSeconds, MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS, "escape policy ttl")
end

do
	local adapter, calls = makeAdapter()
	local store = QueueProcessingIdempotencyStore.Create({
		adapter = adapter,
		structurePolicy = MemoryStoreStructurePolicy,
		structureId = "containmentRewardIdempotency",
	})
	local begun = store.TryBegin("containment-op-1")
	assertTrue(begun.accepted, "containment reward idempotency begin accepted")
	assertEqual(calls[1].mapName, "tin_containment_reward_idempotency_v1", "containment policy map name")
	assertEqual(calls[1].key, "containreward:containment-op-1", "containment policy key")
	assertEqual(calls[1].ttlSeconds, MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS, "containment policy ttl")
end

print("queue_processing_idempotency_store: all checks passed")
