--!strict

local MemoryStoreStructurePolicy = require("../src/ServerScriptService/Services/MemoryStoreStructurePolicy")
local RealmTransferHandoffState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferHandoffState")
local RealmTransferSessionStore = require("../src/ServerScriptService/Services/RealmTransferSessionStore")

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
	local storage: { [string]: string } = {}
	local calls: { any } = {}
	local adapter: any = {}

	adapter.HashMapGetAsync = function(mapName: string, key: string): string?
		table.insert(calls, { method = "HashMapGetAsync", mapName = mapName, key = key })
		return storage[mapName .. ":" .. key]
	end

	adapter.HashMapUpdateAsync = function(
		mapName: string,
		key: string,
		transform: (any) -> any,
		ttlSeconds: number
	): any
		table.insert(calls, {
			method = "HashMapUpdateAsync",
			mapName = mapName,
			key = key,
			ttlSeconds = ttlSeconds,
		})
		local storageKey = mapName .. ":" .. key
		local nextValue = transform(storage[storageKey])
		storage[storageKey] = nextValue
		return nextValue
	end

	return adapter, storage, calls
end

local targetRealmId = "giant_realm_9402"
local now = 100

local adapter, storage, calls = makeAdapter()
local store = RealmTransferSessionStore.Create({
	adapter = adapter,
	handoffState = RealmTransferHandoffState,
	structurePolicy = MemoryStoreStructurePolicy,
})

local beginTransition = RealmTransferHandoffState.BeginHandoff(nil, {
	userId = 9402,
	targetRealmId = targetRealmId,
	operationId = "handoff:9402:1",
	now = now,
	ttlSeconds = 90,
	realmOwnerUserId = 9402,
})
assertTrue(beginTransition.accepted, "fixture begin accepted")

local write = store.UpdateSessionRecord(targetRealmId, function(_currentRecord: any?)
	return beginTransition
end)
assertTrue(write.accepted, "store write accepted")
assertEqual(write.reason, "accepted", "store write reason")
assertEqual(calls[1].method, "HashMapUpdateAsync", "store uses hash map update")
assertEqual(calls[1].key, "session:giant_realm_9402", "store uses policy key")
assertEqual(calls[1].ttlSeconds, 90, "store uses policy ttl")
assertTrue(
	type(storage["tin_realm_transfer_sessions_v1:session:giant_realm_9402"]) == "string",
	"store persists payload"
)

local read = store.GetSessionRecord(targetRealmId)
assertTrue(read.accepted, "store read accepted")
assertTrue(read.sessionRecord ~= nil, "store read session record")
assertTrue(read.sessionRecord.handoffsByToken["handoff:9402:1"] ~= nil, "store read token")

local consumeTransition: any = nil
local consume = store.UpdateSessionRecord(targetRealmId, function(currentRecord: any?)
	consumeTransition = RealmTransferHandoffState.ConsumeHandoff(currentRecord, {
		userId = 9402,
		handoffToken = "handoff:9402:1",
		now = now + 5,
	})
	return consumeTransition
end)
assertTrue(consume.accepted, "store consume accepted")
assertTrue(consumeTransition.accepted, "consume transition accepted")
assertTrue(consume.sessionRecord.handoffsByToken["handoff:9402:1"] == nil, "consume clears token")

local invalidateTransition: any = nil
local secondBegin = RealmTransferHandoffState.BeginHandoff(nil, {
	userId = 9403,
	targetRealmId = targetRealmId,
	operationId = "handoff:9403:abort",
	now = now + 10,
})
store.UpdateSessionRecord(targetRealmId, function(_currentRecord: any?)
	return secondBegin
end)
local invalidate = store.UpdateSessionRecord(targetRealmId, function(currentRecord: any?)
	invalidateTransition = RealmTransferHandoffState.InvalidateHandoff(currentRecord, {
		handoffToken = "handoff:9403:abort",
		now = now + 11,
	})
	return invalidateTransition
end)
assertTrue(invalidate.accepted, "store invalidate accepted")
assertTrue(invalidateTransition.accepted, "invalidate transition accepted")

local memoryStore = RealmTransferSessionStore.Create({
	handoffState = RealmTransferHandoffState,
	structurePolicy = MemoryStoreStructurePolicy,
})
memoryStore.UpdateSessionRecord(targetRealmId, function(_currentRecord: any?)
	return secondBegin
end)
local memoryRead = memoryStore.GetSessionRecord(targetRealmId)
assertTrue(memoryRead.accepted, "memory fallback read accepted")
assertTrue(memoryRead.sessionRecord ~= nil, "memory fallback stores record")

print("realm_transfer_session_store: all checks passed")
