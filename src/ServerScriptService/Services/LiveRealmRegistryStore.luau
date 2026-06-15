--!strict

local LiveRealmRegistryStore: any = {}

export type StoreResult = {
	accepted: boolean,
	reason: string,
	snapshot: any?,
	entries: { any }?,
}

local STRUCTURE_ID = "liveRealmRegistry"

local function failure(reason: string, snapshot: any?, entries: { any }?): StoreResult
	return {
		accepted = false,
		reason = reason,
		snapshot = snapshot,
		entries = entries,
	}
end

local function success(snapshot: any?, entries: { any }?): StoreResult
	return {
		accepted = true,
		reason = "accepted",
		snapshot = snapshot,
		entries = entries,
	}
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and string.len(value) > 0
end

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function getPolicyTtl(policy: any): number
	if type(policy) ~= "table" or type(policy.ResolveExpiration) ~= "function" then
		return 1
	end
	local ttl = policy.ResolveExpiration(STRUCTURE_ID)
	if ttl.ok == true and type(ttl.ttlSeconds) == "number" then
		return ttl.ttlSeconds
	end
	return 1
end

local function resolveMapName(policy: any): (string?, string?)
	if type(policy) ~= "table" or type(policy.GetPolicy) ~= "function" then
		return nil, "policy_unavailable"
	end
	local structurePolicy = policy.GetPolicy(STRUCTURE_ID)
	if type(structurePolicy) ~= "table" or not isNonEmptyString(structurePolicy.name) then
		return nil, "policy_unavailable"
	end
	return structurePolicy.name, nil
end

local function resolveKey(policy: any, realmId: any): (string?, string?)
	if not isNonEmptyString(realmId) then
		return nil, "realm_id_invalid"
	end
	if type(policy) ~= "table" or type(policy.MakeKey) ~= "function" then
		return nil, "policy_unavailable"
	end
	return policy.MakeKey(STRUCTURE_ID, { realmId })
end

function LiveRealmRegistryStore.Create(deps: any?): any
	local depsAny = deps
	local adapter = if type(depsAny) == "table" then depsAny.adapter else nil
	local registryState = if type(depsAny) == "table" then depsAny.registryState else nil
	local structurePolicy = if type(depsAny) == "table" then depsAny.structurePolicy else nil
	local ttlSeconds = getPolicyTtl(structurePolicy)
	local inMemoryByKey: { [string]: { value: string, sortKey: number } } = {}

	local store: any = {}

	local function encodeEntry(entry: any): (string?, string?, number?)
		if type(registryState) ~= "table" or type(registryState.EncodeRegistryEntry) ~= "function" then
			return nil, "state_unavailable", nil
		end
		local encoded, reason = registryState.EncodeRegistryEntry(entry)
		if encoded == nil then
			return nil, reason or "encode_failed", nil
		end
		if type(structurePolicy) ~= "table" or type(structurePolicy.ValidatePayloadSize) ~= "function" then
			return nil, "policy_unavailable", nil
		end
		local payloadResult = structurePolicy.ValidatePayloadSize(STRUCTURE_ID, encoded)
		if not payloadResult.ok then
			return nil, payloadResult.reason or "payload_invalid", nil
		end
		local sortKey = registryState.ResolveSortKey(entry)
		if sortKey == nil then
			return nil, "sort_key_invalid", nil
		end
		return encoded, nil, sortKey
	end

	local function decodeEntry(encoded: any): (any?, string?)
		if type(encoded) ~= "string" then
			return nil, "stored_payload_invalid"
		end
		if type(structurePolicy) ~= "table" or type(structurePolicy.ValidatePayloadSize) ~= "function" then
			return nil, "policy_unavailable"
		end
		local payloadResult = structurePolicy.ValidatePayloadSize(STRUCTURE_ID, encoded)
		if not payloadResult.ok then
			return nil, payloadResult.reason or "stored_payload_invalid"
		end
		if type(registryState) ~= "table" or type(registryState.DecodeRegistryEntry) ~= "function" then
			return nil, "state_unavailable"
		end
		return registryState.DecodeRegistryEntry(encoded)
	end

	local function readInMemory(key: string): StoreResult
		local stored = inMemoryByKey[key]
		if stored == nil then
			return success(nil)
		end
		local entry, reason = decodeEntry(stored.value)
		if entry == nil then
			return failure(reason or "stored_entry_invalid", nil)
		end
		return success(registryState.GetSnapshot(entry))
	end

	local function writeInMemory(key: string, encoded: string?, sortKey: number?)
		if encoded == nil or sortKey == nil then
			inMemoryByKey[key] = nil
			return
		end
		inMemoryByKey[key] = {
			value = encoded,
			sortKey = sortKey,
		}
	end

	local function useSortedMap(): boolean
		local mapName, _mapReason = resolveMapName(structurePolicy)
		return mapName ~= nil
			and type(adapter) == "table"
			and type(adapter.SortedMapSetAsync) == "function"
			and type(adapter.SortedMapGetAsync) == "function"
			and type(adapter.SortedMapRemoveAsync) == "function"
			and type(adapter.SortedMapGetRangeAsync) == "function"
	end

	local function readEntry(realmId: any): StoreResult
		local key, keyReason = resolveKey(structurePolicy, realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end

		if not useSortedMap() then
			return readInMemory(key)
		end

		local mapName, mapReason = resolveMapName(structurePolicy)
		if mapName == nil then
			return failure(mapReason or "policy_unavailable", nil)
		end

		local ok, encoded = pcall(adapter.SortedMapGetAsync, mapName, key)
		if not ok then
			return failure("adapter_get_failed", nil)
		end
		if encoded == nil then
			return success(nil)
		end

		local entry, reason = decodeEntry(encoded)
		if entry == nil then
			return failure(reason or "stored_entry_invalid", nil)
		end
		return success(registryState.GetSnapshot(entry))
	end

	local function updateEntry(realmId: any, mutate: (any?) -> any): StoreResult
		local key, keyReason = resolveKey(structurePolicy, realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end

		if not useSortedMap() then
			local currentEntry: any? = nil
			local stored = inMemoryByKey[key]
			if stored ~= nil then
				local decoded, decodeReason = decodeEntry(stored.value)
				if decoded == nil then
					return failure(decodeReason or "stored_entry_invalid", nil)
				end
				currentEntry = decoded
			end

			local transitionResult = mutate(currentEntry)
			if transitionResult.accepted ~= true then
				return failure(transitionResult.reason or "transition_rejected", transitionResult.snapshot)
			end

			local nextEntry = transitionResult.entry or transitionResult.snapshot
			local encodedNext, encodeReason, sortKey = encodeEntry(nextEntry)
			if encodedNext == nil or sortKey == nil then
				return failure(encodeReason or "encode_failed", transitionResult.snapshot)
			end
			writeInMemory(key, encodedNext, sortKey)
			return success(registryState.GetSnapshot(nextEntry))
		end

		local mapName, mapReason = resolveMapName(structurePolicy)
		if mapName == nil then
			return failure(mapReason or "policy_unavailable", nil)
		end

		local latestSnapshot: any? = nil
		local transformFailedReason: string? = nil
		local ok, updateResult = pcall(function()
			local encodedCurrent: any = adapter.SortedMapGetAsync(mapName, key)
			local currentEntry: any? = nil
			if encodedCurrent ~= nil then
				local decoded, decodeReason = decodeEntry(encodedCurrent)
				if decoded == nil then
					transformFailedReason = decodeReason or "stored_entry_invalid"
					return encodedCurrent
				end
				currentEntry = decoded
			end

			local transitionResult = mutate(currentEntry)
			if transitionResult.accepted ~= true then
				transformFailedReason = transitionResult.reason or "transition_rejected"
				latestSnapshot = transitionResult.snapshot
				return encodedCurrent
			end

			local nextEntry = transitionResult.entry or transitionResult.snapshot
			local encodedNext, encodeReason, sortKey = encodeEntry(nextEntry)
			if encodedNext == nil or sortKey == nil then
				transformFailedReason = encodeReason or "encode_failed"
				latestSnapshot = transitionResult.snapshot
				return encodedCurrent
			end

			latestSnapshot = registryState.GetSnapshot(nextEntry)
			adapter.SortedMapSetAsync(mapName, key, encodedNext, sortKey, ttlSeconds)
			return encodedNext
		end)

		if not ok then
			return failure("adapter_update_failed", latestSnapshot)
		end
		if transformFailedReason ~= nil then
			return failure(transformFailedReason, latestSnapshot)
		end
		if updateResult ~= nil and type(updateResult) ~= "string" then
			return failure("adapter_update_result_invalid", latestSnapshot)
		end
		return success(latestSnapshot)
	end

	function store.GetRegistrySnapshot(realmId: any): StoreResult
		return readEntry(realmId)
	end

	function store.PublishRegistryEntry(input: any): StoreResult
		if type(registryState) ~= "table" or type(registryState.NewEntry) ~= "function" then
			return failure("state_unavailable", nil)
		end
		local inputResult = registryState.NewEntry(input)
		if inputResult.accepted ~= true then
			return failure(inputResult.reason or "entry_invalid", inputResult.snapshot)
		end
		local realmId = input.realmId
		return updateEntry(realmId, function(_currentEntry: any?)
			return inputResult
		end)
	end

	function store.RefreshRegistryEntry(realmId: any, patch: any, now: number): StoreResult
		return updateEntry(realmId, function(currentEntry: any?)
			if currentEntry == nil then
				return {
					accepted = false,
					reason = "registry_entry_missing",
					entry = nil,
					snapshot = nil,
				}
			end
			return registryState.RefreshEntry(currentEntry, patch, now)
		end)
	end

	function store.PruneRegistryEntry(realmId: any, now: number): StoreResult
		return updateEntry(realmId, function(currentEntry: any?)
			if currentEntry == nil then
				return {
					accepted = true,
					reason = "accepted",
					entry = nil,
					snapshot = nil,
				}
			end
			return registryState.MarkLifecycle(currentEntry, registryState.Lifecycle.Expired, now)
		end)
	end

	function store.RemoveRegistryEntry(realmId: any): StoreResult
		local key, keyReason = resolveKey(structurePolicy, realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end

		if not useSortedMap() then
			writeInMemory(key, nil, nil)
			return success(nil)
		end

		local mapName, mapReason = resolveMapName(structurePolicy)
		if mapName == nil then
			return failure(mapReason or "policy_unavailable", nil)
		end

		local ok = pcall(adapter.SortedMapRemoveAsync, mapName, key)
		if not ok then
			return failure("adapter_remove_failed", nil)
		end
		return success(nil)
	end

	function store.ListRegistryEntries(limit: any, exclusiveStartKey: any?): StoreResult
		if not isPositiveInteger(limit) then
			return failure("limit_invalid", nil)
		end

		if not useSortedMap() then
			local entries = {}
			for key, stored in pairs(inMemoryByKey) do
				local entry, reason = decodeEntry(stored.value)
				if entry ~= nil then
					local snapshot = registryState.GetSnapshot(entry)
					if snapshot ~= nil then
						table.insert(entries, {
							key = key,
							sortKey = stored.sortKey,
							snapshot = snapshot,
						})
					end
				else
					return failure(reason or "stored_entry_invalid", nil)
				end
			end
			table.sort(entries, function(left: any, right: any): boolean
				if left.sortKey ~= right.sortKey then
					return left.sortKey > right.sortKey
				end
				return left.key < right.key
			end)

			local result = {}
			local skippedExclusive = exclusiveStartKey == nil
			for _, item in ipairs(entries) do
				if skippedExclusive then
					table.insert(result, item.snapshot)
					if #result >= limit then
						break
					end
				elseif item.key == exclusiveStartKey then
					skippedExclusive = true
				end
			end
			return success(nil, result)
		end

		local mapName, mapReason = resolveMapName(structurePolicy)
		if mapName == nil then
			return failure(mapReason or "policy_unavailable", nil)
		end

		local ok, rangeItems = pcall(function()
			return adapter.SortedMapGetRangeAsync(mapName, "descending", limit, exclusiveStartKey)
		end)
		if not ok or type(rangeItems) ~= "table" then
			return failure("adapter_range_failed", nil)
		end

		local snapshots = {}
		for _, item in ipairs(rangeItems) do
			if type(item) == "table" and type(item.value) == "string" then
				local entry, reason = decodeEntry(item.value)
				if entry == nil then
					return failure(reason or "stored_entry_invalid", nil)
				end
				local snapshot = registryState.GetSnapshot(entry)
				if snapshot ~= nil then
					table.insert(snapshots, snapshot)
				end
			end
		end
		return success(nil, snapshots)
	end

	return store
end

return LiveRealmRegistryStore
