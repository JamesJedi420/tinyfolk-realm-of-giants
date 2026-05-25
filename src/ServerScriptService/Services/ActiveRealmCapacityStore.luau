--!strict

local ActiveRealmCapacityStore: any = {}

export type StoreResult = {
	accepted: boolean,
	reason: string,
	snapshot: any?,
}

local STRUCTURE_ID = "activeRealmCapacity"

local function failure(reason: string, snapshot: any?): StoreResult
	return {
		accepted = false,
		reason = reason,
		snapshot = snapshot,
	}
end

local function success(snapshot: any?): StoreResult
	return {
		accepted = true,
		reason = "accepted",
		snapshot = snapshot,
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

local function resolveKey(policy: any, realmId: any): (string?, string?)
	if not isNonEmptyString(realmId) then
		return nil, "realm_id_invalid"
	end
	if type(policy) ~= "table" or type(policy.MakeKey) ~= "function" then
		return nil, "policy_unavailable"
	end
	return policy.MakeKey(STRUCTURE_ID, { realmId })
end

function ActiveRealmCapacityStore.Create(deps: any?): any
	local depsAny = deps
	local adapter = if type(depsAny) == "table" then depsAny.adapter else nil
	local codec = if type(depsAny) == "table" then depsAny.codec else nil
	local capacityState = if type(depsAny) == "table" then depsAny.capacityState else nil
	local structurePolicy = if type(depsAny) == "table" then depsAny.structurePolicy else nil
	local ttlSeconds = getPolicyTtl(structurePolicy)

	local store: any = {}

	local function encodeEntry(entry: any): (string?, string?)
		if type(codec) ~= "table" or type(codec.Encode) ~= "function" then
			return nil, "codec_unavailable"
		end
		local ok, encoded = pcall(codec.Encode, entry)
		if not ok or type(encoded) ~= "string" then
			return nil, "encode_failed"
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
		if type(codec) ~= "table" or type(codec.Decode) ~= "function" then
			return nil, "codec_unavailable"
		end
		local ok, decoded = pcall(codec.Decode, encoded)
		if not ok then
			return nil, "decode_failed"
		end
		if type(capacityState) ~= "table" or type(capacityState.ValidateEntry) ~= "function" then
			return nil, "state_unavailable"
		end
		local validation = capacityState.ValidateEntry(decoded)
		if not validation.ok then
			return nil, validation.reason or "stored_entry_invalid"
		end
		return validation.entry, nil
	end

	local function readEntry(realmId: any): StoreResult
		local key, keyReason = resolveKey(structurePolicy, realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end
		if type(adapter) ~= "table" or type(adapter.GetAsync) ~= "function" then
			return failure("adapter_unavailable", nil)
		end

		local ok, encoded = pcall(adapter.GetAsync, key)
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
		return success(capacityState.GetSnapshot(entry))
	end

	local function updateEntry(realmId: any, mutate: (any?) -> any): StoreResult
		local key, keyReason = resolveKey(structurePolicy, realmId)
		if key == nil then
			return failure(keyReason or "key_invalid", nil)
		end
		if type(adapter) ~= "table" or type(adapter.UpdateAsync) ~= "function" then
			return failure("adapter_unavailable", nil)
		end

		local latestSnapshot: any? = nil
		local transformFailedReason: string? = nil
		local ok, updateResult = pcall(function()
			return adapter.UpdateAsync(key, function(encoded: any)
				local currentEntry: any? = nil
				if encoded ~= nil then
					local decoded, decodeReason = decodeEntry(encoded)
					if decoded == nil then
						transformFailedReason = decodeReason or "stored_entry_invalid"
						return encoded
					end
					currentEntry = decoded
				end

				local transitionResult = mutate(currentEntry)
				if transitionResult.accepted ~= true then
					transformFailedReason = transitionResult.reason or "transition_rejected"
					latestSnapshot = transitionResult.snapshot
					return encoded
				end

				local nextEntry = transitionResult.entry or transitionResult.snapshot
				local encodedNext, encodeReason = encodeEntry(nextEntry)
				if encodedNext == nil then
					transformFailedReason = encodeReason or "encode_failed"
					latestSnapshot = transitionResult.snapshot
					return encoded
				end

				latestSnapshot = capacityState.GetSnapshot(nextEntry)
				return encodedNext
			end, ttlSeconds)
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

	function store.GetCapacitySnapshot(realmId: any): StoreResult
		return readEntry(realmId)
	end

	function store.RefreshCapacity(input: any): StoreResult
		if type(input) ~= "table" then
			return failure("entry_invalid", nil)
		end
		if type(capacityState) ~= "table" or type(capacityState.NewEntry) ~= "function" then
			return failure("state_unavailable", nil)
		end
		local inputResult = capacityState.NewEntry(input)
		if inputResult.accepted ~= true then
			return failure(inputResult.reason or "entry_invalid", inputResult.snapshot)
		end
		local realmId = input.realmId
		return updateEntry(realmId, function(_currentEntry: any?)
			return inputResult
		end)
	end

	function store.ReserveTinyfolkSlots(realmId: any, count: number, now: number): StoreResult
		return updateEntry(realmId, function(currentEntry: any?)
			if currentEntry == nil then
				return {
					accepted = false,
					reason = "capacity_entry_missing",
					entry = nil,
					snapshot = nil,
				}
			end
			return capacityState.ReserveTinyfolkSlots(currentEntry, count, now)
		end)
	end

	function store.CommitTinyfolkArrival(realmId: any, count: number, now: number): StoreResult
		return updateEntry(realmId, function(currentEntry: any?)
			if currentEntry == nil then
				return {
					accepted = false,
					reason = "capacity_entry_missing",
					entry = nil,
					snapshot = nil,
				}
			end
			return capacityState.CommitTinyfolkArrival(currentEntry, count, now)
		end)
	end

	function store.ReleaseReservedSlots(realmId: any, count: number, now: number): StoreResult
		return updateEntry(realmId, function(currentEntry: any?)
			if currentEntry == nil then
				return {
					accepted = false,
					reason = "capacity_entry_missing",
					entry = nil,
					snapshot = nil,
				}
			end
			return capacityState.ReleaseReservedSlots(currentEntry, count, now)
		end)
	end

	return store
end

return ActiveRealmCapacityStore
