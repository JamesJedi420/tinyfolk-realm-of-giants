--!strict

local PartyMatchmakingQueueStore: any = {}

export type StoreResult = {
	accepted: boolean,
	reason: string,
	snapshot: any?,
}

export type ReadResult = {
	accepted: boolean,
	reason: string,
	items: { any },
}

local STRUCTURE_ID = "partyMatchmakingQueue"
local READ_VISIBILITY_TIMEOUT_SECONDS = 5

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

local function readFailure(reason: string): ReadResult
	return {
		accepted = false,
		reason = reason,
		items = {},
	}
end

local function readSuccess(items: { any }): ReadResult
	return {
		accepted = true,
		reason = "accepted",
		items = items,
	}
end

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and string.len(value) > 0
end

local function getPolicy(policy: any): any?
	if type(policy) ~= "table" or type(policy.GetPolicy) ~= "function" then
		return nil
	end
	return policy.GetPolicy(STRUCTURE_ID)
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

local function sanitizeKeyPart(value: string): string
	return (string.gsub(value, ":", "_"))
end

function PartyMatchmakingQueueStore.Create(deps: any?): any
	local depsAny = deps
	local adapter = if type(depsAny) == "table" then depsAny.adapter else nil
	local codec = if type(depsAny) == "table" then depsAny.codec else nil
	local queueState = if type(depsAny) == "table" then depsAny.queueState else nil
	local structurePolicy = if type(depsAny) == "table" then depsAny.structurePolicy else nil
	local ttlSeconds = getPolicyTtl(structurePolicy)
	local policy = getPolicy(structurePolicy)
	local queueName = if type(policy) == "table" then policy.name else nil

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
		if type(queueState) ~= "table" or type(queueState.ValidateEntry) ~= "function" then
			return nil, "state_unavailable"
		end
		local validation = queueState.ValidateEntry(decoded)
		if not validation.ok then
			return nil, validation.reason or "stored_entry_invalid"
		end
		return validation.entry, nil
	end

	local function removeReceipt(receiptId: any): StoreResult
		if not isNonEmptyString(queueName) then
			return failure("policy_unavailable", nil)
		end
		if not isNonEmptyString(receiptId) then
			return failure("receipt_id_invalid", nil)
		end
		if type(adapter) ~= "table" or type(adapter.QueueRemoveAsync) ~= "function" then
			return failure("adapter_unavailable", nil)
		end

		local ok = pcall(adapter.QueueRemoveAsync, queueName, receiptId)
		if not ok then
			return failure("adapter_remove_failed", nil)
		end
		return success(nil)
	end

	function store.Enqueue(input: any): StoreResult
		if not isNonEmptyString(queueName) then
			return failure("policy_unavailable", nil)
		end
		if type(queueState) ~= "table" or type(queueState.NewEntry) ~= "function" then
			return failure("state_unavailable", nil)
		end

		local inputResult = queueState.NewEntry(input)
		if inputResult.ok ~= true then
			return failure(inputResult.reason or "entry_invalid", nil)
		end

		if type(structurePolicy) ~= "table" or type(structurePolicy.MakeKey) ~= "function" then
			return failure("policy_unavailable", nil)
		end
		local queueKey, queueKeyReason = structurePolicy.MakeKey(STRUCTURE_ID, {
			sanitizeKeyPart(inputResult.entry.partyId),
			sanitizeKeyPart(inputResult.entry.operationId),
		})
		if queueKey == nil then
			return failure(queueKeyReason or "queue_key_invalid", nil)
		end

		local entryWithQueueKey: any = table.clone(inputResult.entry)
		entryWithQueueKey.queueKey = queueKey

		local encoded, encodeReason = encodeEntry(entryWithQueueKey)
		if encoded == nil then
			return failure(encodeReason or "encode_failed", nil)
		end

		if type(adapter) ~= "table" or type(adapter.QueueAddAsync) ~= "function" then
			return failure("adapter_unavailable", nil)
		end

		local priority = inputResult.entry.createdAt
		local ok = pcall(adapter.QueueAddAsync, queueName, encoded, ttlSeconds, priority)
		if not ok then
			return failure("adapter_add_failed", nil)
		end
		return success(inputResult.entry)
	end

	function store.ReadBatch(maxItems: any): ReadResult
		if not isNonEmptyString(queueName) then
			return readFailure("policy_unavailable")
		end
		if not isFiniteNumber(maxItems) or maxItems <= 0 or maxItems % 1 ~= 0 then
			return readFailure("max_items_invalid")
		end
		if type(adapter) ~= "table" or type(adapter.QueueReadAsync) ~= "function" then
			return readFailure("adapter_unavailable")
		end

		local ok, queueItems =
			pcall(adapter.QueueReadAsync, queueName, maxItems, false, READ_VISIBILITY_TIMEOUT_SECONDS)
		if not ok then
			return readFailure("adapter_read_failed")
		end
		if type(queueItems) ~= "table" then
			return readFailure("adapter_read_result_invalid")
		end

		local items: { any } = {}
		for _, queueItem in ipairs(queueItems) do
			local queueItemAny = queueItem
			local queueItemId = (queueItemAny :: any).id
			local queueItemValue = (queueItemAny :: any).value
			if type(queueItemAny) == "table" and isNonEmptyString(queueItemId) then
				local entry, decodeReason = decodeEntry(queueItemValue)
				if entry == nil then
					removeReceipt(queueItemId)
					table.insert(items, {
						receiptId = queueItemId,
						entry = nil,
						reason = decodeReason or "stored_entry_invalid",
					})
				else
					table.insert(items, {
						receiptId = queueItemId,
						entry = entry,
						reason = nil,
					})
				end
			end
		end

		return readSuccess(items)
	end

	function store.Remove(receiptId: any): StoreResult
		return removeReceipt(receiptId)
	end

	return store
end

return PartyMatchmakingQueueStore
