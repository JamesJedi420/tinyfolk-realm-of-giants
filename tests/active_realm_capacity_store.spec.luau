--!strict

local ActiveRealmCapacityStore = require("../src/ServerScriptService/Services/ActiveRealmCapacityStore")
local ActiveRealmCapacityState = require("../src/ServerScriptService/Services/ActiveRealmCapacityState")
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

local function makeCodec()
	return {
		Encode = function(entry: any): string
			return table.concat({
				entry.realmId,
				tostring(entry.currentTinyfolk),
				tostring(entry.currentGiants),
				tostring(entry.reservedSlots),
				tostring(entry.maxTinyfolk),
				tostring(entry.maxGiants),
				tostring(entry.updatedAt),
			}, "|")
		end,
		Decode = function(encoded: string): any
			local parts = string.split(encoded, "|")
			return {
				realmId = parts[1],
				currentTinyfolk = tonumber(parts[2]),
				currentGiants = tonumber(parts[3]),
				reservedSlots = tonumber(parts[4]),
				maxTinyfolk = tonumber(parts[5]),
				maxGiants = tonumber(parts[6]),
				updatedAt = tonumber(parts[7]),
			}
		end,
	}
end

local function makeAdapter()
	local storage: { [string]: string } = {}
	local calls: { any } = {}
	local adapter: any = {}

	adapter.GetAsync = function(key: string): string?
		table.insert(calls, { method = "GetAsync", key = key })
		return storage[key]
	end

	adapter.UpdateAsync = function(key: string, transform: (any) -> any, ttlSeconds: number): any
		table.insert(calls, { method = "UpdateAsync", key = key, ttlSeconds = ttlSeconds })
		local nextValue = transform(storage[key])
		storage[key] = nextValue
		return nextValue
	end

	return adapter, storage, calls
end

local adapter, storage, calls = makeAdapter()
local store = ActiveRealmCapacityStore.Create({
	adapter = adapter,
	codec = makeCodec(),
	capacityState = ActiveRealmCapacityState,
	structurePolicy = MemoryStoreStructurePolicy,
})

local refresh = store.RefreshCapacity({
	realmId = "realm-9402",
	currentTinyfolk = 2,
	currentGiants = 1,
	reservedSlots = 0,
	maxTinyfolk = 4,
	maxGiants = 2,
	updatedAt = 100,
})
assertTrue(refresh.accepted, "refresh writes entry")
assertEqual(refresh.reason, "accepted", "refresh reason")
assertEqual(refresh.snapshot.currentTinyfolk, 2, "refresh snapshot current tinyfolk")
assertEqual(calls[1].method, "UpdateAsync", "refresh uses atomic update")
assertEqual(calls[1].key, "capacity:realm-9402", "refresh uses policy key")
assertEqual(calls[1].ttlSeconds, 120, "refresh uses policy ttl")
assertTrue(type(storage["capacity:realm-9402"]) == "string", "refresh stores encoded payload")

local read = store.GetCapacitySnapshot("realm-9402")
assertTrue(read.accepted, "read accepted")
assertEqual(read.snapshot.realmId, "realm-9402", "read snapshot realm")
assertEqual(read.snapshot.currentTinyfolk, 2, "read snapshot tinyfolk")

local reserve = store.ReserveTinyfolkSlots("realm-9402", 2, 110)
assertTrue(reserve.accepted, "reserve accepted")
assertEqual(reserve.snapshot.reservedSlots, 2, "reserve snapshot slots")

local overReserve = store.ReserveTinyfolkSlots("realm-9402", 1, 111)
assertFalse(overReserve.accepted, "over reserve rejected")
assertEqual(overReserve.reason, "tinyfolk_capacity_unavailable", "over reserve reason")
assertEqual(overReserve.snapshot.reservedSlots, 2, "over reserve returns current snapshot")

local commit = store.CommitTinyfolkArrival("realm-9402", 1, 120)
assertTrue(commit.accepted, "commit accepted")
assertEqual(commit.snapshot.currentTinyfolk, 3, "commit increments current")
assertEqual(commit.snapshot.reservedSlots, 1, "commit decrements reserved")

local release = store.ReleaseReservedSlots("realm-9402", 1, 130)
assertTrue(release.accepted, "release accepted")
assertEqual(release.snapshot.reservedSlots, 0, "release decrements reserved")

local missing = store.ReserveTinyfolkSlots("realm-missing", 1, 140)
assertFalse(missing.accepted, "missing entry reserve rejected")
assertEqual(missing.reason, "capacity_entry_missing", "missing entry reason")

storage["capacity:bad"] = "bad|payload"
local malformed = store.GetCapacitySnapshot("bad")
assertFalse(malformed.accepted, "malformed stored payload rejected")
assertEqual(malformed.reason, "current_tinyfolk_invalid", "malformed reason")

local failingAdapter: any = {
	GetAsync = function(_key: string)
		error("boom")
	end,
	UpdateAsync = function(_key: string, _transform: any, _ttlSeconds: number)
		error("boom")
	end,
}
local failingStore = ActiveRealmCapacityStore.Create({
	adapter = failingAdapter,
	codec = makeCodec(),
	capacityState = ActiveRealmCapacityState,
	structurePolicy = MemoryStoreStructurePolicy,
})
local failedGet = failingStore.GetCapacitySnapshot("realm-9402")
assertFalse(failedGet.accepted, "adapter get failure rejected")
assertEqual(failedGet.reason, "adapter_get_failed", "adapter get failure reason")

local failedUpdate = failingStore.RefreshCapacity({
	realmId = "realm-9402",
	currentTinyfolk = 0,
	currentGiants = 1,
	reservedSlots = 0,
	maxTinyfolk = 4,
	maxGiants = 1,
	updatedAt = 200,
})
assertFalse(failedUpdate.accepted, "adapter update failure rejected")
assertEqual(failedUpdate.reason, "adapter_update_failed", "adapter update failure reason")

local unavailableStore = ActiveRealmCapacityStore.Create({
	capacityState = ActiveRealmCapacityState,
	structurePolicy = MemoryStoreStructurePolicy,
})
local unavailable = unavailableStore.GetCapacitySnapshot("realm-9402")
assertFalse(unavailable.accepted, "missing adapter rejected")
assertEqual(unavailable.reason, "adapter_unavailable", "missing adapter reason")

local invalidBeforeAdapter = unavailableStore.RefreshCapacity({
	realmId = "",
	currentTinyfolk = 0,
	currentGiants = 0,
	reservedSlots = 0,
	maxTinyfolk = 4,
	maxGiants = 1,
	updatedAt = 200,
})
assertFalse(invalidBeforeAdapter.accepted, "invalid refresh rejected before adapter")
assertEqual(invalidBeforeAdapter.reason, "realm_id_invalid", "invalid refresh before adapter reason")

local invalidRealm = store.GetCapacitySnapshot("bad:realm")
assertFalse(invalidRealm.accepted, "invalid realm key rejected")
assertEqual(invalidRealm.reason, "key_part_segment_invalid", "invalid realm reason")

storage["capacity:oversized"] = string.rep("x", 1025)
local oversized = store.GetCapacitySnapshot("oversized")
assertFalse(oversized.accepted, "oversized stored payload rejected")
assertEqual(oversized.reason, "payload_policy_limit_exceeded", "oversized payload reason")

print("active_realm_capacity_store: all checks passed")
