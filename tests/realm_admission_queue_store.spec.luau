--!strict

local RealmAdmissionQueueState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAdmissionQueueState")
local RealmAdmissionQueueStore = require("../src/ServerScriptService/Services/RealmAdmissionQueueStore")
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

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function makeEntry(overrides: any?): any
	local entry = {
		operationId = "op-100",
		partyId = "party-42",
		targetRealmId = "realm-9402",
		entryType = "standard",
		priority = nil,
		createdAt = 100,
		expiration = 200,
		partySize = 2,
		retryCount = 0,
	}
	if overrides ~= nil then
		for key, value in pairs(overrides) do
			entry[key] = value
		end
	end
	return entry
end

local function makeCodec()
	return {
		Encode = function(entry: any): string
			return table.concat({
				entry.operationId,
				entry.partyId,
				entry.targetRealmId,
				entry.entryType,
				tostring(entry.priority),
				tostring(entry.createdAt),
				tostring(entry.expiration),
				tostring(entry.partySize),
				tostring(entry.retryCount),
			}, "|")
		end,
		Decode = function(encoded: string): any
			local parts = string.split(encoded, "|")
			return {
				operationId = parts[1],
				partyId = parts[2],
				targetRealmId = parts[3],
				entryType = parts[4],
				priority = tonumber(parts[5]),
				createdAt = tonumber(parts[6]),
				expiration = tonumber(parts[7]),
				partySize = tonumber(parts[8]),
				retryCount = tonumber(parts[9]),
			}
		end,
	}
end

local function makeQueueAdapter()
	local queueByName: { [string]: { any } } = {}
	local removedIds: { [string]: boolean } = {}
	local calls: { any } = {}
	local sequence = 0
	local adapter: any = {}

	adapter.QueueAddAsync = function(queueName: string, encoded: string, ttlSeconds: number, priority: number)
		table.insert(calls, {
			method = "QueueAddAsync",
			queueName = queueName,
			ttlSeconds = ttlSeconds,
			priority = priority,
		})
		if queueByName[queueName] == nil then
			queueByName[queueName] = {}
		end
		sequence += 1
		table.insert(queueByName[queueName], {
			id = "receipt-" .. tostring(sequence),
			value = encoded,
			priority = priority,
		})
		table.sort(queueByName[queueName], function(a, b)
			if a.priority == b.priority then
				return a.id < b.id
			end
			return a.priority > b.priority
		end)
	end

	adapter.QueueReadAsync = function(
		queueName: string,
		count: number,
		_allOrNothing: boolean,
		waitTimeout: number
	): { any }
		table.insert(calls, {
			method = "QueueReadAsync",
			queueName = queueName,
			count = count,
			waitTimeout = waitTimeout,
		})
		local queue = queueByName[queueName] or {}
		local result = {}
		for _, item in ipairs(queue) do
			if #result >= count then
				break
			end
			if removedIds[item.id] ~= true then
				table.insert(result, {
					id = item.id,
					value = item.value,
				})
			end
		end
		return result
	end

	adapter.QueueRemoveAsync = function(queueName: string, receiptId: string)
		table.insert(calls, {
			method = "QueueRemoveAsync",
			queueName = queueName,
			receiptId = receiptId,
		})
		removedIds[receiptId] = true
	end

	return adapter, queueByName, calls, removedIds
end

local adapter, queueByName, calls, removedIds = makeQueueAdapter()
local store = RealmAdmissionQueueStore.Create({
	adapter = adapter,
	codec = makeCodec(),
	queueState = RealmAdmissionQueueState,
	structurePolicy = MemoryStoreStructurePolicy,
})

local firstEnqueue = store.Enqueue(makeEntry())
assertTrue(firstEnqueue.accepted, "first enqueue accepted")
assertEqual(firstEnqueue.snapshot.priority, 100, "first enqueue derived priority")

local secondEnqueue = store.Enqueue(makeEntry({
	operationId = "op-101",
	entryType = "rescue_contract",
	expiration = 210,
}))
assertTrue(secondEnqueue.accepted, "second enqueue accepted")
assertEqual(secondEnqueue.snapshot.priority, 300, "rescue priority applied")

assertEqual(calls[1].method, "QueueAddAsync", "first adapter call add")
assertEqual(calls[1].queueName, "tin_realm_admission_queue_v1", "queue name from policy")
assertEqual(calls[1].ttlSeconds, 600, "queue add ttl from policy")

local read = store.ReadBatch(2)
assertTrue(read.accepted, "read accepted")
assertEqual(#read.items, 2, "read returns two items")
assertEqual(read.items[1].entry.entryType, "rescue_contract", "higher priority read first")
assertEqual(read.items[2].entry.entryType, "standard", "lower priority read second")
assertEqual(calls[3].waitTimeout, 5, "read uses non-zero visibility timeout")

local remove = store.Remove(read.items[1].receiptId)
assertTrue(remove.accepted, "remove accepted")
assertTrue(removedIds[read.items[1].receiptId] == true, "receipt removed")

local readAfterRemove = store.ReadBatch(5)
assertTrue(readAfterRemove.accepted, "read after remove accepted")
assertEqual(#readAfterRemove.items, 1, "removed entry not read again")

local queueName = "tin_realm_admission_queue_v1"
table.insert(queueByName[queueName], {
	id = "receipt-malformed",
	value = "bad|payload",
	priority = 0,
})
local malformedRead = store.ReadBatch(5)
assertTrue(malformedRead.accepted, "malformed read accepted")
local malformedItem: any = nil
for _, item in ipairs(malformedRead.items) do
	if item.receiptId == "receipt-malformed" then
		malformedItem = item
		break
	end
end
assertTrue(malformedItem ~= nil, "malformed item surfaced")
assertEqual(malformedItem.reason, "target_realm_id_invalid", "malformed decode reason")
assertTrue(removedIds["receipt-malformed"] == true, "malformed entry removed")

local badEntry = store.Enqueue(makeEntry({ operationId = "bad:op" }))
assertFalse(badEntry.accepted, "invalid queue key rejected")
assertEqual(badEntry.reason, "key_part_segment_invalid", "invalid queue key reason")

local unavailableStore = RealmAdmissionQueueStore.Create({
	codec = makeCodec(),
	queueState = RealmAdmissionQueueState,
	structurePolicy = MemoryStoreStructurePolicy,
})
local unavailableRead = unavailableStore.ReadBatch(1)
assertFalse(unavailableRead.accepted, "missing adapter read rejected")
assertEqual(unavailableRead.reason, "adapter_unavailable", "missing adapter reason")

print("realm_admission_queue_store: all checks passed")
