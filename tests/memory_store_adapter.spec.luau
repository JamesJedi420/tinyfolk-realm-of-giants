--!strict

local MemoryStoreAdapter = require("../src/ServerScriptService/Services/MemoryStoreAdapter")

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

local function makeMemoryStoreService()
	local queuesByName: { [string]: { entries: { any }, removedById: { [string]: boolean }, sequence: number } } = {}
	local hashMapsByName: { [string]: { valuesByKey: { [string]: any } } } = {}

	local function getQueueState(name: string)
		if queuesByName[name] == nil then
			queuesByName[name] = {
				entries = {},
				removedById = {},
				sequence = 0,
			}
		end
		return queuesByName[name]
	end

	local function getMapState(name: string)
		if hashMapsByName[name] == nil then
			hashMapsByName[name] = {
				valuesByKey = {},
			}
		end
		return hashMapsByName[name]
	end

	local service: any = {}
	service.GetQueue = function(_self: any, queueName: string)
		local queueState: any = getQueueState(queueName)
		return {
			AddAsync = function(_queueSelf: any, value: any, _ttlSeconds: number, priority: number)
				queueState.sequence += 1
				table.insert(queueState.entries, {
					id = "receipt-" .. tostring(queueState.sequence),
					value = value,
					priority = priority,
				})
				table.sort(queueState.entries, function(a, b)
					if a.priority == b.priority then
						return a.id < b.id
					end
					return a.priority > b.priority
				end)
			end,
			ReadAsync = function(_queueSelf: any, count: number, _allOrNothing: boolean, _waitTimeout: number)
				local result = {}
				for _, entry in ipairs(queueState.entries) do
					if #result >= count then
						break
					end
					if queueState.removedById[entry.id] ~= true then
						table.insert(result, {
							id = entry.id,
							value = entry.value,
						})
					end
				end
				return result
			end,
			RemoveAsync = function(_queueSelf: any, receiptId: string)
				queueState.removedById[receiptId] = true
			end,
		}
	end
	service.GetHashMap = function(_self: any, mapName: string)
		local mapState = getMapState(mapName)
		return {
			GetAsync = function(_mapSelf: any, key: string)
				return mapState.valuesByKey[key]
			end,
			UpdateAsync = function(_mapSelf: any, key: string, transform: (any) -> any, _ttlSeconds: number)
				local nextValue = transform(mapState.valuesByKey[key])
				mapState.valuesByKey[key] = nextValue
				return nextValue
			end,
		}
	end

	return service
end

local unavailable = MemoryStoreAdapter.CreateDefault({
	activeRealmCapacityMapName = "tin_active_realm_capacity_v1",
})
assertEqual(unavailable, nil, "create default unavailable outside runtime")

local missingConfig = MemoryStoreAdapter.Create({
	memoryStoreService = makeMemoryStoreService(),
})
assertEqual(missingConfig, nil, "missing map name rejects create")

local adapter = MemoryStoreAdapter.Create({
	memoryStoreService = makeMemoryStoreService(),
	activeRealmCapacityMapName = "tin_active_realm_capacity_v1",
})
assertTrue(type(adapter) == "table", "adapter created")

adapter.QueueAddAsync("tin_realm_admission_queue_v1", "payload-a", 600, 100)
adapter.QueueAddAsync("tin_realm_admission_queue_v1", "payload-b", 600, 200)

local queueItems = adapter.QueueReadAsync("tin_realm_admission_queue_v1", 2, false, 5)
assertEqual(#queueItems, 2, "queue read count")
assertEqual(queueItems[1].value, "payload-b", "queue higher priority first")
assertEqual(queueItems[2].value, "payload-a", "queue lower priority second")

adapter.QueueRemoveAsync("tin_realm_admission_queue_v1", queueItems[1].id)
local queueAfterRemove = adapter.QueueReadAsync("tin_realm_admission_queue_v1", 2, false, 5)
assertEqual(#queueAfterRemove, 1, "queue remove hides receipt")
assertEqual(queueAfterRemove[1].value, "payload-a", "queue remove keeps remaining")

local previous = adapter.GetAsync("capacity:realm-1")
assertEqual(previous, nil, "hash map starts empty")

local updated = adapter.UpdateAsync("capacity:realm-1", function(_current: any)
	return "encoded-entry"
end, 120)
assertEqual(updated, "encoded-entry", "hash map update result")
assertEqual(adapter.GetAsync("capacity:realm-1"), "encoded-entry", "hash map persisted value")

local threw = pcall(function()
	adapter.QueueAddAsync("tin_realm_admission_queue_v1", "payload", 0, 100)
end)
assertFalse(threw, "invalid ttl rejects queue add")

local threwUpdate = pcall(function()
	adapter.UpdateAsync("capacity:realm-1", "bad" :: any, 120)
end)
assertFalse(threwUpdate, "invalid transform rejects update")

print("memory_store_adapter: all checks passed")
