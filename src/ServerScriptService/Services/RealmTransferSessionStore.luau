--!strict

local RealmTransferSessionStore: any = {}

export type StoreResult = {
	accepted: boolean,
	reason: string,
	sessionRecord: any?,
}

local STRUCTURE_ID = "realmTransferSessions"

local function failure(reason: string, sessionRecord: any?): StoreResult
	return {
		accepted = false,
		reason = reason,
		sessionRecord = sessionRecord,
	}
end

local function success(sessionRecord: any?): StoreResult
	return {
		accepted = true,
		reason = "accepted",
		sessionRecord = sessionRecord,
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

function RealmTransferSessionStore.Create(deps: any?): any
	local depsAny = deps
	local adapter = if type(depsAny) == "table" then depsAny.adapter else nil
	local handoffState = if type(depsAny) == "table" then depsAny.handoffState else nil
	local structurePolicy = if type(depsAny) == "table" then depsAny.structurePolicy else nil
	local ttlSeconds = getPolicyTtl(structurePolicy)
	local inMemoryByKey: { [string]: string } = {}

	local store: any = {}

	local function encodeRecord(record: any): (string?, string?)
		if type(handoffState) ~= "table" or type(handoffState.EncodeSessionRecord) ~= "function" then
			return nil, "state_unavailable"
		end
		local encoded, reason = handoffState.EncodeSessionRecord(record)
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
		if type(handoffState) ~= "table" or type(handoffState.DecodeSessionRecord) ~= "function" then
			return nil, "state_unavailable"
		end
		return handoffState.DecodeSessionRecord(encoded)
	end

	local function readInMemory(key: string): StoreResult
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

	local function writeInMemory(key: string, encoded: string?)
		if encoded == nil then
			inMemoryByKey[key] = nil
			return
		end
		inMemoryByKey[key] = encoded
	end

	local function updateRecord(realmId: any, mutate: (any?) -> any): StoreResult
		local key, keyReason = resolveKey(structurePolicy, realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end

		local mapName, _mapReason = resolveMapName(structurePolicy)
		local useHashMap = mapName ~= nil
			and type(adapter) == "table"
			and type(adapter.HashMapUpdateAsync) == "function"

		if not useHashMap then
			local currentRecord: any? = nil
			local encoded = inMemoryByKey[key]
			if encoded ~= nil then
				local decoded, decodeReason = decodeRecord(encoded)
				if decoded == nil then
					return failure(decodeReason or "stored_entry_invalid", nil)
				end
				currentRecord = decoded
			end

			local transitionResult = mutate(currentRecord)
			if transitionResult.accepted ~= true then
				return failure(transitionResult.reason or "transition_rejected", transitionResult.sessionRecord)
			end

			local nextRecord = transitionResult.sessionRecord
			if nextRecord == nil then
				writeInMemory(key, nil)
				return success(nil)
			end

			local encodedNext, encodeReason = encodeRecord(nextRecord)
			if encodedNext == nil then
				return failure(encodeReason or "encode_failed", transitionResult.sessionRecord)
			end
			writeInMemory(key, encodedNext)
			return success(nextRecord)
		end

		local latestRecord: any? = nil
		local transformFailedReason: string? = nil
		local ok, updateResult = pcall(function()
			return adapter.HashMapUpdateAsync(mapName, key, function(encoded: any)
				local currentRecord: any? = nil
				if encoded ~= nil then
					local decoded, decodeReason = decodeRecord(encoded)
					if decoded == nil then
						transformFailedReason = decodeReason or "stored_entry_invalid"
						return encoded
					end
					currentRecord = decoded
				end

				local transitionResult = mutate(currentRecord)
				if transitionResult.accepted ~= true then
					transformFailedReason = transitionResult.reason or "transition_rejected"
					latestRecord = transitionResult.sessionRecord
					return encoded
				end

				local nextRecord = transitionResult.sessionRecord
				latestRecord = nextRecord
				if nextRecord == nil then
					return nil
				end

				local encodedNext, encodeReason = encodeRecord(nextRecord)
				if encodedNext == nil then
					transformFailedReason = encodeReason or "encode_failed"
					return encoded
				end
				return encodedNext
			end, ttlSeconds)
		end)

		if not ok then
			return failure("adapter_update_failed", latestRecord)
		end
		if transformFailedReason ~= nil then
			return failure(transformFailedReason, latestRecord)
		end
		if updateResult ~= nil and type(updateResult) ~= "string" then
			return failure("adapter_update_result_invalid", latestRecord)
		end
		return success(latestRecord)
	end

	function store.ResetForTests()
		table.clear(inMemoryByKey)
	end

	function store.GetSessionRecord(realmId: any): StoreResult
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

		return readInMemory(key)
	end

	function store.UpdateSessionRecord(realmId: any, mutate: (any?) -> any): StoreResult
		return updateRecord(realmId, mutate)
	end

	return store
end

return RealmTransferSessionStore
