--!strict

local MemoryStoreAdapter: any = {}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonNegativeInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value < 0 then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return string.len(value) > 0
end

local function hasMethod(target: any, methodName: string): boolean
	if target == nil then
		return false
	end

	local ok, member = pcall(function()
		return (target :: any)[methodName]
	end)
	if not ok then
		return false
	end
	return type(member) == "function"
end

function MemoryStoreAdapter.Create(config: any?): any?
	local configAny: any = config
	local memoryStoreService = if type(configAny) == "table" then configAny.memoryStoreService else nil
	local activeRealmCapacityMapName = if type(configAny) == "table" then configAny.activeRealmCapacityMapName else nil
	local liveRealmRegistryMapName = if type(configAny) == "table" then configAny.liveRealmRegistryMapName else nil

	if memoryStoreService == nil then
		return nil
	end
	if not isNonEmptyString(activeRealmCapacityMapName) and not isNonEmptyString(liveRealmRegistryMapName) then
		return nil
	end
	if not hasMethod(memoryStoreService, "GetQueue") then
		return nil
	end
	if not hasMethod(memoryStoreService, "GetHashMap") then
		return nil
	end
	if isNonEmptyString(liveRealmRegistryMapName) and not hasMethod(memoryStoreService, "GetSortedMap") then
		return nil
	end

	local queueByName: { [string]: any } = {}
	local hashMapByName: { [string]: any } = {}
	local sortedMapByName: { [string]: any } = {}
	local activeCapacityMap: any? = nil

	local function getQueue(queueName: any): any?
		if not isNonEmptyString(queueName) then
			return nil
		end
		if queueByName[queueName] ~= nil then
			return queueByName[queueName]
		end

		local queue = memoryStoreService:GetQueue(queueName)
		if
			queue == nil
			or not hasMethod(queue, "AddAsync")
			or not hasMethod(queue, "ReadAsync")
			or not hasMethod(queue, "RemoveAsync")
		then
			return nil
		end
		queueByName[queueName] = queue
		return queue
	end

	local function getActiveCapacityMap(): any?
		if not isNonEmptyString(activeRealmCapacityMapName) then
			return nil
		end
		if activeCapacityMap ~= nil then
			return activeCapacityMap
		end

		local hashMap = memoryStoreService:GetHashMap(activeRealmCapacityMapName)
		if hashMap == nil or not hasMethod(hashMap, "GetAsync") or not hasMethod(hashMap, "UpdateAsync") then
			return nil
		end
		activeCapacityMap = hashMap
		return hashMap
	end

	local function getSortedMap(mapName: any): any?
		if not isNonEmptyString(mapName) then
			return nil
		end
		if sortedMapByName[mapName] ~= nil then
			return sortedMapByName[mapName]
		end

		local sortedMap = memoryStoreService:GetSortedMap(mapName)
		if
			sortedMap == nil
			or not hasMethod(sortedMap, "SetAsync")
			or not hasMethod(sortedMap, "GetAsync")
			or not hasMethod(sortedMap, "RemoveAsync")
			or not hasMethod(sortedMap, "GetRangeAsync")
		then
			return nil
		end
		sortedMapByName[mapName] = sortedMap
		return sortedMap
	end

	local function getHashMap(mapName: any): any?
		if not isNonEmptyString(mapName) then
			return nil
		end
		if hashMapByName[mapName] ~= nil then
			return hashMapByName[mapName]
		end

		local hashMap = memoryStoreService:GetHashMap(mapName)
		if hashMap == nil or not hasMethod(hashMap, "GetAsync") or not hasMethod(hashMap, "UpdateAsync") then
			return nil
		end
		hashMapByName[mapName] = hashMap
		return hashMap
	end

	local adapter: any = {}

	function adapter.QueueAddAsync(queueName: any, value: any, ttlSeconds: any, priority: any)
		if not isNonEmptyString(queueName) then
			error("queue_name_invalid")
		end
		if not isPositiveInteger(ttlSeconds) then
			error("ttl_seconds_invalid")
		end
		if not isNonNegativeInteger(priority) then
			error("priority_invalid")
		end

		local queue = getQueue(queueName)
		if queue == nil or type(queue.AddAsync) ~= "function" then
			error("queue_unavailable")
		end
		queue:AddAsync(value, ttlSeconds, priority)
	end

	function adapter.QueueReadAsync(queueName: any, count: any, allOrNothing: any, waitTimeout: any): { any }
		if not isNonEmptyString(queueName) then
			error("queue_name_invalid")
		end
		if not isPositiveInteger(count) then
			error("count_invalid")
		end
		if type(allOrNothing) ~= "boolean" then
			error("all_or_nothing_invalid")
		end
		if not isNonNegativeInteger(waitTimeout) then
			error("wait_timeout_invalid")
		end

		local queue = getQueue(queueName)
		if queue == nil or type(queue.ReadAsync) ~= "function" then
			error("queue_unavailable")
		end

		local items = queue:ReadAsync(count, allOrNothing, waitTimeout)
		if type(items) ~= "table" then
			error("queue_read_result_invalid")
		end
		return items
	end

	function adapter.QueueRemoveAsync(queueName: any, receiptId: any)
		if not isNonEmptyString(queueName) then
			error("queue_name_invalid")
		end
		if not isNonEmptyString(receiptId) then
			error("receipt_id_invalid")
		end

		local queue = getQueue(queueName)
		if queue == nil or type(queue.RemoveAsync) ~= "function" then
			error("queue_unavailable")
		end
		queue:RemoveAsync(receiptId)
	end

	function adapter.GetAsync(key: any): any
		if not isNonEmptyString(key) then
			error("key_invalid")
		end

		local hashMap = getActiveCapacityMap()
		if hashMap == nil or type(hashMap.GetAsync) ~= "function" then
			error("hash_map_unavailable")
		end

		return hashMap:GetAsync(key)
	end

	function adapter.UpdateAsync(key: any, transform: any, ttlSeconds: any): any
		if not isNonEmptyString(key) then
			error("key_invalid")
		end
		if type(transform) ~= "function" then
			error("transform_invalid")
		end
		if not isPositiveInteger(ttlSeconds) then
			error("ttl_seconds_invalid")
		end

		local hashMap = getActiveCapacityMap()
		if hashMap == nil or type(hashMap.UpdateAsync) ~= "function" then
			error("hash_map_unavailable")
		end

		return hashMap:UpdateAsync(key, transform, ttlSeconds)
	end

	function adapter.HashMapGetAsync(mapName: any, key: any): any
		if not isNonEmptyString(mapName) then
			error("map_name_invalid")
		end
		if not isNonEmptyString(key) then
			error("key_invalid")
		end

		local hashMap = getHashMap(mapName)
		if hashMap == nil or type(hashMap.GetAsync) ~= "function" then
			error("hash_map_unavailable")
		end

		return hashMap:GetAsync(key)
	end

	function adapter.HashMapUpdateAsync(mapName: any, key: any, transform: any, ttlSeconds: any): any
		if not isNonEmptyString(mapName) then
			error("map_name_invalid")
		end
		if not isNonEmptyString(key) then
			error("key_invalid")
		end
		if type(transform) ~= "function" then
			error("transform_invalid")
		end
		if not isPositiveInteger(ttlSeconds) then
			error("ttl_seconds_invalid")
		end

		local hashMap = getHashMap(mapName)
		if hashMap == nil or type(hashMap.UpdateAsync) ~= "function" then
			error("hash_map_unavailable")
		end

		return hashMap:UpdateAsync(key, transform, ttlSeconds)
	end

	function adapter.SortedMapSetAsync(mapName: any, key: any, value: any, sortKey: any, ttlSeconds: any)
		if not isNonEmptyString(mapName) then
			error("sorted_map_name_invalid")
		end
		if not isNonEmptyString(key) then
			error("key_invalid")
		end
		if type(value) ~= "string" then
			error("value_invalid")
		end
		if not isFiniteNumber(sortKey) then
			error("sort_key_invalid")
		end
		if not isPositiveInteger(ttlSeconds) then
			error("ttl_seconds_invalid")
		end

		local sortedMap = getSortedMap(mapName)
		if sortedMap == nil or type(sortedMap.SetAsync) ~= "function" then
			error("sorted_map_unavailable")
		end
		sortedMap:SetAsync(key, value, ttlSeconds, sortKey)
	end

	function adapter.SortedMapGetAsync(mapName: any, key: any): any
		if not isNonEmptyString(mapName) then
			error("sorted_map_name_invalid")
		end
		if not isNonEmptyString(key) then
			error("key_invalid")
		end

		local sortedMap = getSortedMap(mapName)
		if sortedMap == nil or type(sortedMap.GetAsync) ~= "function" then
			error("sorted_map_unavailable")
		end
		return sortedMap:GetAsync(key)
	end

	function adapter.SortedMapRemoveAsync(mapName: any, key: any)
		if not isNonEmptyString(mapName) then
			error("sorted_map_name_invalid")
		end
		if not isNonEmptyString(key) then
			error("key_invalid")
		end

		local sortedMap = getSortedMap(mapName)
		if sortedMap == nil or type(sortedMap.RemoveAsync) ~= "function" then
			error("sorted_map_unavailable")
		end
		sortedMap:RemoveAsync(key)
	end

	function adapter.SortedMapGetRangeAsync(mapName: any, direction: any, count: any, exclusiveStartKey: any?): { any }
		if not isNonEmptyString(mapName) then
			error("sorted_map_name_invalid")
		end
		if direction ~= "ascending" and direction ~= "descending" then
			error("sort_direction_invalid")
		end
		if not isPositiveInteger(count) then
			error("count_invalid")
		end
		if exclusiveStartKey ~= nil and not isNonEmptyString(exclusiveStartKey) then
			error("exclusive_start_key_invalid")
		end

		local sortedMap = getSortedMap(mapName)
		if sortedMap == nil or type(sortedMap.GetRangeAsync) ~= "function" then
			error("sorted_map_unavailable")
		end

		local sortDirection = if direction == "descending"
			then Enum.SortDirection.Descending
			else Enum.SortDirection.Ascending
		local items = sortedMap:GetRangeAsync(sortDirection, count, exclusiveStartKey)
		if type(items) ~= "table" then
			error("sorted_map_range_result_invalid")
		end

		local normalized = {}
		for _, item in ipairs(items) do
			if type(item) == "table" then
				table.insert(normalized, {
					key = item.key,
					value = item.value,
					sortKey = item.sortKey,
				})
			end
		end
		return normalized
	end

	return adapter
end

function MemoryStoreAdapter.CreateDefault(config: any?): any?
	local configAny: any = config

	local memoryStoreService: any? = nil
	if game ~= nil and type(game.GetService) == "function" then
		local ok, service = pcall(function()
			return game:GetService("MemoryStoreService")
		end)
		if ok and service ~= nil then
			memoryStoreService = service
		end
	end
	if memoryStoreService == nil then
		return nil
	end

	local activeRealmCapacityMapName = if type(configAny) == "table" then configAny.activeRealmCapacityMapName else nil
	local liveRealmRegistryMapName = if type(configAny) == "table" then configAny.liveRealmRegistryMapName else nil
	return MemoryStoreAdapter.Create({
		memoryStoreService = memoryStoreService,
		activeRealmCapacityMapName = activeRealmCapacityMapName,
		liveRealmRegistryMapName = liveRealmRegistryMapName,
	})
end

return MemoryStoreAdapter
