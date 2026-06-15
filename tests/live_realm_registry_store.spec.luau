--!strict

local LiveRealmRegistryStore = require("../src/ServerScriptService/Services/LiveRealmRegistryStore")
local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
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

local function makeSortedMapAdapter()
	local storage: { [string]: { value: string, sortKey: number } } = {}
	local calls: { any } = {}
	local adapter: any = {}

	adapter.SortedMapSetAsync = function(
		_mapName: string,
		key: string,
		value: string,
		sortKey: number,
		ttlSeconds: number
	)
		table.insert(calls, {
			method = "SortedMapSetAsync",
			key = key,
			value = value,
			sortKey = sortKey,
			ttlSeconds = ttlSeconds,
		})
		storage[key] = {
			value = value,
			sortKey = sortKey,
		}
	end

	adapter.SortedMapGetAsync = function(_mapName: string, key: string): string?
		table.insert(calls, { method = "SortedMapGetAsync", key = key })
		local stored = storage[key]
		if stored == nil then
			return nil
		end
		return stored.value
	end

	adapter.SortedMapRemoveAsync = function(_mapName: string, key: string)
		table.insert(calls, { method = "SortedMapRemoveAsync", key = key })
		storage[key] = nil
	end

	adapter.SortedMapGetRangeAsync = function(
		_mapName: string,
		direction: string,
		count: number,
		exclusiveStartKey: string?
	)
		table.insert(calls, {
			method = "SortedMapGetRangeAsync",
			direction = direction,
			count = count,
			exclusiveStartKey = exclusiveStartKey,
		})
		local items = {}
		for key, stored in pairs(storage) do
			table.insert(items, {
				key = key,
				value = stored.value,
				sortKey = stored.sortKey,
			})
		end
		table.sort(items, function(left: any, right: any): boolean
			if direction == "descending" then
				if left.sortKey ~= right.sortKey then
					return left.sortKey > right.sortKey
				end
				return left.key < right.key
			end
			if left.sortKey ~= right.sortKey then
				return left.sortKey < right.sortKey
			end
			return left.key < right.key
		end)

		local result = {}
		local skippedExclusive = exclusiveStartKey == nil
		for _, item in ipairs(items) do
			if skippedExclusive then
				table.insert(result, item)
				if #result >= count then
					break
				end
			elseif item.key == exclusiveStartKey then
				skippedExclusive = true
			end
		end
		return result
	end

	return adapter, storage, calls
end

local adapter, storage, calls = makeSortedMapAdapter()
local store = LiveRealmRegistryStore.Create({
	adapter = adapter,
	registryState = LiveRealmRegistryState,
	structurePolicy = MemoryStoreStructurePolicy,
})

local publish = store.PublishRegistryEntry({
	realmId = "giant_realm_9001",
	ownerUserId = 9001,
	privateServerId = "giant_realm_ps_9001",
	jobId = "job-1",
	accessMode = LiveRealmRegistryState.AccessMode.Public,
	playerCount = 1,
	capacity = 8,
	dangerRating = 0.4,
	updatedAt = 100,
	lifecycle = LiveRealmRegistryState.Lifecycle.Active,
})
assertTrue(publish.accepted, "publish accepted")
assertEqual(publish.snapshot.jobId, "job-1", "publish snapshot job id")
assertEqual(calls[1].method, "SortedMapGetAsync", "publish reads before set")
assertEqual(calls[2].method, "SortedMapSetAsync", "publish uses sorted map set")

local refresh = store.RefreshRegistryEntry("giant_realm_9001", {
	playerCount = 3,
	jobId = "job-2",
}, 110)
assertTrue(refresh.accepted, "refresh accepted")
assertEqual(refresh.snapshot.playerCount, 3, "refresh player count")
assertEqual(refresh.snapshot.jobId, "job-2", "refresh job id")

local snapshot = store.GetRegistrySnapshot("giant_realm_9001")
assertTrue(snapshot.accepted, "get snapshot accepted")
assertEqual(snapshot.snapshot.realmId, "giant_realm_9001", "get snapshot realm id")

local list = store.ListRegistryEntries(10, nil)
assertTrue(list.accepted, "list accepted")
assertEqual(#list.entries, 1, "list count")
assertEqual(list.entries[1].jobId, "job-2", "list entry job id")

local prune = store.PruneRegistryEntry("giant_realm_9001", 200)
assertTrue(prune.accepted, "prune accepted")
assertEqual(prune.snapshot.lifecycle, LiveRealmRegistryState.Lifecycle.Expired, "prune lifecycle")

local remove = store.RemoveRegistryEntry("giant_realm_9001")
assertTrue(remove.accepted, "remove accepted")
assertEqual(storage["realm:giant_realm_9001"], nil, "storage cleared")

local memoryOnlyStore = LiveRealmRegistryStore.Create({
	registryState = LiveRealmRegistryState,
	structurePolicy = MemoryStoreStructurePolicy,
})
local callCountBeforeMemory = #calls
local memoryPublish = memoryOnlyStore.PublishRegistryEntry({
	realmId = "giant_realm_9002",
	ownerUserId = 9002,
	privateServerId = "giant_realm_ps_9002",
	jobId = "job-memory",
	accessMode = LiveRealmRegistryState.AccessMode.Public,
	playerCount = 1,
	capacity = 8,
	dangerRating = 0.2,
	updatedAt = 50,
	lifecycle = LiveRealmRegistryState.Lifecycle.Active,
})
assertTrue(memoryPublish.accepted, "memory publish accepted")
assertEqual(#calls, callCountBeforeMemory, "memory store does not call sorted map adapter")

print("live_realm_registry_store.spec.luau: all checks passed")
