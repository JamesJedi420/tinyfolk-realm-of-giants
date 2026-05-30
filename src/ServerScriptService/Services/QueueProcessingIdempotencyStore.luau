--!strict

local QueueProcessingIdempotencyStore: any = {}

local STRUCTURE_ID = "queueProcessingIdempotency"

export type StoreResult = {
	accepted: boolean,
	reason: string,
	status: string?,
	snapshot: any?,
}

local function failure(reason: string, status: string?, snapshot: any?): StoreResult
	return {
		accepted = false,
		reason = reason,
		status = status,
		snapshot = snapshot,
	}
end

local function success(status: string, snapshot: any?): StoreResult
	return {
		accepted = true,
		reason = "accepted",
		status = status,
		snapshot = snapshot,
	}
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return string.len(value) > 0
end

local function defaultNow(): number
	return os.clock()
end

local function cloneRecord(record: any): any?
	if type(record) ~= "table" then
		return nil
	end
	return table.clone(record)
end

local function resolvePolicy(structurePolicy: any): (string?, number?, string?)
	if type(structurePolicy) ~= "table" or type(structurePolicy.GetPolicy) ~= "function" then
		return nil, nil, "policy_unavailable"
	end
	local policy = structurePolicy.GetPolicy(STRUCTURE_ID)
	if type(policy) ~= "table" or not isNonEmptyString(policy.name) then
		return nil, nil, "policy_unavailable"
	end
	if type(structurePolicy.ResolveExpiration) ~= "function" then
		return nil, nil, "policy_unavailable"
	end
	local ttlResult = structurePolicy.ResolveExpiration(STRUCTURE_ID)
	if type(ttlResult) ~= "table" or ttlResult.ok ~= true or type(ttlResult.ttlSeconds) ~= "number" then
		return nil, nil, "policy_unavailable"
	end
	return policy.name, ttlResult.ttlSeconds, nil
end

function QueueProcessingIdempotencyStore.Create(deps: any?): any
	local depsAny = deps
	local adapter = if type(depsAny) == "table" then depsAny.adapter else nil
	local structurePolicy = if type(depsAny) == "table" then depsAny.structurePolicy else nil
	local nowFn = if type(depsAny) == "table" and type(depsAny.now) == "function" then depsAny.now else defaultNow

	local store: any = {}

	local function makeKey(operationId: any): (string?, string?)
		if not isNonEmptyString(operationId) then
			return nil, "operation_id_invalid"
		end
		if type(structurePolicy) ~= "table" or type(structurePolicy.MakeKey) ~= "function" then
			return nil, "policy_unavailable"
		end
		return structurePolicy.MakeKey(STRUCTURE_ID, { operationId })
	end

	local function update(operationId: any, transform: (any) -> any): (any?, string?)
		local mapName, ttlSeconds, policyReason = resolvePolicy(structurePolicy)
		if mapName == nil or ttlSeconds == nil then
			return nil, policyReason or "policy_unavailable"
		end
		local key, keyReason = makeKey(operationId)
		if key == nil then
			return nil, keyReason or "operation_id_invalid"
		end
		if type(adapter) ~= "table" or type(adapter.HashMapUpdateAsync) ~= "function" then
			return nil, "adapter_unavailable"
		end

		local ok, result = pcall(adapter.HashMapUpdateAsync, mapName, key, transform, ttlSeconds)
		if not ok then
			return nil, "adapter_update_failed"
		end
		return result, nil
	end

	function store.TryBegin(operationId: any): StoreResult
		local existingStatus: string? = nil
		local result, reason = update(operationId, function(current: any): any
			if type(current) == "table" then
				local status = current.status
				if status == "completed" or status == "processing" then
					existingStatus = status
					return current
				end
			end
			existingStatus = nil
			return {
				operationId = operationId,
				status = "processing",
				updatedAt = nowFn(),
			}
		end)
		if result == nil then
			return failure(reason or "adapter_update_failed", nil, nil)
		end
		if type(result) ~= "table" then
			return failure("record_invalid", nil, nil)
		end
		if result.status == "completed" then
			return success("completed", cloneRecord(result))
		end
		if result.status == "processing" and result.operationId == operationId then
			if existingStatus == "processing" then
				return failure("already_processing", "processing", cloneRecord(result))
			end
			return success("begun", cloneRecord(result))
		end
		return failure("record_invalid", nil, cloneRecord(result))
	end

	function store.MarkCompleted(operationId: any): StoreResult
		local result, reason = update(operationId, function(_current: any): any
			return {
				operationId = operationId,
				status = "completed",
				updatedAt = nowFn(),
			}
		end)
		if result == nil then
			return failure(reason or "adapter_update_failed", nil, nil)
		end
		return success("completed", cloneRecord(result))
	end

	function store.ReleaseProcessing(operationId: any): StoreResult
		local result, reason = update(operationId, function(current: any): any
			if type(current) == "table" and current.status == "processing" then
				return nil
			end
			return current
		end)
		if reason ~= nil then
			return failure(reason, nil, nil)
		end
		return success("released", cloneRecord(result))
	end

	return store
end

return QueueProcessingIdempotencyStore
