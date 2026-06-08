--!strict

local GiantRealmResourcePairHistoryState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("GiantRealmResourcePairHistoryState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourcePairHistoryState")

local RealmResourcePairHistoryStore: any = {}

local STRUCTURE_ID = "realmResourcePairHistory"
local DEFAULT_RETENTION_SECONDS = 300

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and string.len(value) > 0
end

local function defaultNow(): number
	return os.clock()
end

function RealmResourcePairHistoryStore.Create(deps: any?): any
	local depsAny: any = if type(deps) == "table" then deps else {}
	local adapter = depsAny.adapter
	local structurePolicy = depsAny.structurePolicy
	local retentionSeconds = if type(depsAny.retentionSeconds) == "number" and depsAny.retentionSeconds > 0
		then depsAny.retentionSeconds
		else DEFAULT_RETENTION_SECONDS
	local nowFn = if type(depsAny.now) == "function" then depsAny.now else defaultNow
	local inMemoryByKey: { [string]: string } = {}

	local store: any = {}

	local function resolvePolicy(): (string?, number?, string?)
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

	local function makeKey(pairKey: any): (string?, string?)
		if not isNonEmptyString(pairKey) then
			return nil, "pair_key_invalid"
		end
		if type(structurePolicy) ~= "table" or type(structurePolicy.MakeKey) ~= "function" then
			return nil, "policy_unavailable"
		end
		return structurePolicy.MakeKey(STRUCTURE_ID, { pairKey })
	end

	local function readInMemory(pairKey: string, at: number): number
		local encoded = inMemoryByKey[pairKey]
		local record, _reason = GiantRealmResourcePairHistoryState.DecodeRecord(encoded)
		return GiantRealmResourcePairHistoryState.ResolvePairCount(record, at, retentionSeconds)
	end

	local function writeInMemory(pairKey: string, count: number, at: number)
		inMemoryByKey[pairKey] = GiantRealmResourcePairHistoryState.EncodeRecord(count, at)
	end

	function store.ReadPairCount(pairKey: any, at: any?): number
		local resolvedAt = if type(at) == "number" then at else nowFn()
		local mapName, _ttlSeconds, _policyReason = resolvePolicy()
		if mapName == nil or type(adapter) ~= "table" or type(adapter.HashMapGetAsync) ~= "function" then
			return readInMemory(pairKey, resolvedAt)
		end

		local key, _keyReason = makeKey(pairKey)
		if key == nil then
			return readInMemory(pairKey, resolvedAt)
		end

		local ok, encoded = pcall(adapter.HashMapGetAsync, mapName, key)
		if not ok then
			return readInMemory(pairKey, resolvedAt)
		end
		local record, _reason = GiantRealmResourcePairHistoryState.DecodeRecord(encoded)
		return GiantRealmResourcePairHistoryState.ResolvePairCount(record, resolvedAt, retentionSeconds)
	end

	function store.WritePairCount(pairKey: any, count: any, at: any?): boolean
		if type(count) ~= "number" or count <= 0 or count % 1 ~= 0 then
			return false
		end
		local resolvedAt = if type(at) == "number" then at else nowFn()
		writeInMemory(tostring(pairKey), count, resolvedAt)
		local encoded = inMemoryByKey[tostring(pairKey)]

		local mapName, ttlSeconds, _policyReason = resolvePolicy()
		if
			mapName == nil
			or ttlSeconds == nil
			or type(adapter) ~= "table"
			or type(adapter.HashMapUpdateAsync) ~= "function"
		then
			return true
		end

		local key, _keyReason = makeKey(pairKey)
		if key == nil then
			return true
		end

		local ok = pcall(adapter.HashMapUpdateAsync, mapName, key, function(_current: any): any
			return encoded
		end, ttlSeconds)
		return ok
	end

	return store
end

return RealmResourcePairHistoryStore
