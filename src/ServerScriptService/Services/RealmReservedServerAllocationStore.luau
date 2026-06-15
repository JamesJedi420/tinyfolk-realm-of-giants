--!strict

local RealmReservedServerAllocationStore: any = {}

export type StoreResult = {
	accepted: boolean,
	reason: string,
	record: any?,
}

local STRUCTURE_ID = "realmReservedServerAllocation"

local function failure(reason: string, record: any?): StoreResult
	return {
		accepted = false,
		reason = reason,
		record = record,
	}
end

local function success(record: any?): StoreResult
	return {
		accepted = true,
		reason = "accepted",
		record = record,
	}
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and string.len(value) > 0
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

function RealmReservedServerAllocationStore.Create(deps: any?): any
	local depsAny = deps
	local adapter = if type(depsAny) == "table" then depsAny.adapter else nil
	local allocationState = if type(depsAny) == "table" then depsAny.allocationState else nil
	local structurePolicy = if type(depsAny) == "table" then depsAny.structurePolicy else nil
	local ttlSeconds = getPolicyTtl(structurePolicy)
	local inMemoryByKey: { [string]: string } = {}

	local store: any = {}

	local function encodeRecord(record: any): (string?, string?)
		if type(allocationState) ~= "table" or type(allocationState.EncodeMirrorRecord) ~= "function" then
			return nil, "state_unavailable"
		end
		local encoded, reason = allocationState.EncodeMirrorRecord(record)
		if encoded == nil then
			return nil, reason or "encode_failed"
		end
		if type(structurePolicy) ~= "table" or type(structurePolicy.ValidatePayloadSize) ~= "function" then
			return nil, "policy_unavailable"
		end
		local payloadResult = structurePolicy.ValidatePayloadSize(STRUCTURE_ID, encoded)
		if not payloadResult.ok then
			return nil, payloadResult.reason or "payload_invalid"
		end
		return encoded, nil
	end

	local function decodeRecord(encoded: any): (any?, string?)
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
		if type(allocationState) ~= "table" or type(allocationState.DecodeMirrorRecord) ~= "function" then
			return nil, "state_unavailable"
		end
		return allocationState.DecodeMirrorRecord(encoded)
	end

	function store.ResetForTests()
		table.clear(inMemoryByKey)
	end

	function store.GetAllocationRecord(realmId: any): StoreResult
		local key, keyReason = resolveKey(structurePolicy, realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end

		local mapName, _mapReason = resolveMapName(structurePolicy)
		if mapName ~= nil and type(adapter) == "table" and type(adapter.HashMapGetAsync) == "function" then
			local ok, encoded = pcall(adapter.HashMapGetAsync, mapName, key)
			if not ok then
				return failure("adapter_get_failed", nil)
			end
			if encoded == nil then
				return success(nil)
			end
			local record, reason = decodeRecord(encoded)
			if record == nil then
				return failure(reason or "stored_entry_invalid", nil)
			end
			return success(record)
		end

		local encoded = inMemoryByKey[key]
		if encoded == nil then
			return success(nil)
		end
		local record, reason = decodeRecord(encoded)
		if record == nil then
			return failure(reason or "stored_entry_invalid", nil)
		end
		return success(record)
	end

	function store.PublishAllocationRecord(record: any): StoreResult
		if type(record) ~= "table" then
			return failure("allocation_record_invalid", nil)
		end
		local key, keyReason = resolveKey(structurePolicy, record.realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end

		local encoded, encodeReason = encodeRecord(record)
		if encoded == nil then
			return failure(encodeReason or "encode_failed", nil)
		end

		local mapName, _mapReason = resolveMapName(structurePolicy)
		if mapName ~= nil and type(adapter) == "table" and type(adapter.HashMapUpdateAsync) == "function" then
			local ok = pcall(adapter.HashMapUpdateAsync, mapName, key, function(_current: any): any
				return encoded
			end, ttlSeconds)
			if not ok then
				return failure("adapter_update_failed", record)
			end
		end

		inMemoryByKey[key] = encoded
		return success(record)
	end

	return store
end

return RealmReservedServerAllocationStore
