--!strict

local MemoryStoreStructurePolicy: any = {}

export type StructureKind = "SortedMap" | "Queue" | "HashMap"

export type StructurePolicy = {
	id: string,
	kind: StructureKind,
	name: string,
	keyPrefix: string,
	ttlSeconds: number,
	maxPayloadBytes: number,
	parts: { string },
	description: string,
}

export type ValidationResult = {
	ok: boolean,
	reason: string?,
	structureId: string?,
	ttlSeconds: number?,
}

MemoryStoreStructurePolicy.MAX_STRUCTURE_NAME_LENGTH = 128
MemoryStoreStructurePolicy.MAX_KEY_LENGTH = 128
MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS = 45 * 24 * 60 * 60
MemoryStoreStructurePolicy.MIN_EXPIRATION_SECONDS = 1
MemoryStoreStructurePolicy.MAX_VALUE_BYTES = 32 * 1024

local STRUCTURE_ORDER = {
	"liveRealmRegistry",
	"realmAdmissionQueue",
	"partyMatchmakingQueue",
	"transferLocks",
	"realmTransferSessions",
	"queueProcessingIdempotency",
	"escapeOutcomeIdempotency",
	"containmentRewardIdempotency",
	"realmResourcePairHistory",
	"activeRealmCapacity",
	"rescueContractQueue",
	"captureTimers",
}

local STRUCTURES: { [string]: StructurePolicy } = {
	liveRealmRegistry = {
		id = "liveRealmRegistry",
		kind = "SortedMap",
		name = "tin_live_realm_registry_v1",
		keyPrefix = "realm",
		ttlSeconds = 120,
		maxPayloadBytes = 2048,
		parts = { "realmId" },
		description = "Live realm advertisement heartbeat records.",
	},
	realmAdmissionQueue = {
		id = "realmAdmissionQueue",
		kind = "Queue",
		name = "tin_realm_admission_queue_v1",
		keyPrefix = "admission",
		ttlSeconds = 600,
		maxPayloadBytes = 4096,
		parts = { "targetRealmId", "operationId" },
		description = "Pending realm admission attempts awaiting capacity.",
	},
	partyMatchmakingQueue = {
		id = "partyMatchmakingQueue",
		kind = "Queue",
		name = "tin_party_matchmaking_queue_v1",
		keyPrefix = "party",
		ttlSeconds = 300,
		maxPayloadBytes = 4096,
		parts = { "partyId", "operationId" },
		description = "Pending party matchmaking attempts before realm selection.",
	},
	transferLocks = {
		id = "transferLocks",
		kind = "HashMap",
		name = "tin_transfer_locks_v1",
		keyPrefix = "handoff",
		ttlSeconds = 90,
		maxPayloadBytes = 1024,
		parts = { "operationId" },
		description = "Short-lived idempotency and teleport handoff locks.",
	},
	realmTransferSessions = {
		id = "realmTransferSessions",
		kind = "HashMap",
		name = "tin_realm_transfer_sessions_v1",
		keyPrefix = "session",
		ttlSeconds = 90,
		maxPayloadBytes = 4096,
		parts = { "realmId" },
		description = "Durable realm session records keyed by realmId for active handoff tokens.",
	},
	queueProcessingIdempotency = {
		id = "queueProcessingIdempotency",
		kind = "HashMap",
		name = "tin_queue_processing_idempotency_v1",
		keyPrefix = "queueop",
		ttlSeconds = 600,
		maxPayloadBytes = 1024,
		parts = { "operationId" },
		description = "Short-lived queue processing idempotency records.",
	},
	escapeOutcomeIdempotency = {
		id = "escapeOutcomeIdempotency",
		kind = "HashMap",
		name = "tin_escape_outcome_idempotency_v1",
		keyPrefix = "escapeop",
		ttlSeconds = MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS,
		maxPayloadBytes = 1024,
		parts = { "operationId" },
		description = "Long-retention escape outcome idempotency records.",
	},
	containmentRewardIdempotency = {
		id = "containmentRewardIdempotency",
		kind = "HashMap",
		name = "tin_containment_reward_idempotency_v1",
		keyPrefix = "containreward",
		ttlSeconds = MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS,
		maxPayloadBytes = 1024,
		parts = { "operationId" },
		description = "Long-retention containment reward idempotency records.",
	},
	realmResourcePairHistory = {
		id = "realmResourcePairHistory",
		kind = "HashMap",
		name = "tin_realm_resource_pair_history_v1",
		keyPrefix = "pair",
		ttlSeconds = 300,
		maxPayloadBytes = 256,
		parts = { "pairKey" },
		description = "Bounded Giant/Tinyfolk pair anti-farming history for realm resource awards.",
	},
	activeRealmCapacity = {
		id = "activeRealmCapacity",
		kind = "HashMap",
		name = "tin_active_realm_capacity_v1",
		keyPrefix = "capacity",
		ttlSeconds = 120,
		maxPayloadBytes = 1024,
		parts = { "realmId" },
		description = "Live occupancy and reserved-slot counters.",
	},
	rescueContractQueue = {
		id = "rescueContractQueue",
		kind = "Queue",
		name = "tin_rescue_contract_queue_v1",
		keyPrefix = "rescue",
		ttlSeconds = 900,
		maxPayloadBytes = 4096,
		parts = { "queueEntryId" },
		description = "Live rescue opportunities readable by hub consumers.",
	},
	captureTimers = {
		id = "captureTimers",
		kind = "SortedMap",
		name = "tin_capture_timers_v1",
		keyPrefix = "capture",
		ttlSeconds = 3600,
		maxPayloadBytes = 2048,
		parts = { "capturedUserId", "realmId" },
		description = "Bounded live capture timeout and expiry records.",
	},
}

local function cloneArray(source: { string }): { string }
	local result = {}
	for _, value in ipairs(source) do
		table.insert(result, value)
	end
	return result
end

local function clonePolicy(policy: StructurePolicy): StructurePolicy
	return {
		id = policy.id,
		kind = policy.kind,
		name = policy.name,
		keyPrefix = policy.keyPrefix,
		ttlSeconds = policy.ttlSeconds,
		maxPayloadBytes = policy.maxPayloadBytes,
		parts = cloneArray(policy.parts),
		description = policy.description,
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

local function isSafeKeySegment(value: string): boolean
	if value == "" then
		return false
	end
	if string.len(value) > 48 then
		return false
	end
	return string.match(value, "^[%w_%.%-]+$") ~= nil
end

local function normalizeKeyPart(value: any): (string?, string?)
	if type(value) == "number" then
		if not isFiniteNumber(value) or value <= 0 or value % 1 ~= 0 then
			return nil, "key_part_number_invalid"
		end
		return tostring(value), nil
	end
	if type(value) ~= "string" then
		return nil, "key_part_type_invalid"
	end
	if not isSafeKeySegment(value) then
		return nil, "key_part_segment_invalid"
	end
	return value, nil
end

local function getPolicy(structureId: any): StructurePolicy?
	if type(structureId) ~= "string" then
		return nil
	end
	return STRUCTURES[structureId]
end

local function hasOnlyExpectedArrayParts(parts: { any }, expectedCount: number): boolean
	for key in pairs(parts) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > expectedCount then
			return false
		end
	end
	return true
end

function MemoryStoreStructurePolicy.GetStructureIds(): { string }
	return cloneArray(STRUCTURE_ORDER)
end

function MemoryStoreStructurePolicy.GetPolicy(structureId: any): StructurePolicy?
	local policy = getPolicy(structureId)
	if policy == nil then
		return nil
	end
	return clonePolicy(policy)
end

function MemoryStoreStructurePolicy.GetAllPolicies(): { StructurePolicy }
	local policies = {}
	for _, structureId in ipairs(STRUCTURE_ORDER) do
		table.insert(policies, clonePolicy(STRUCTURES[structureId]))
	end
	return policies
end

function MemoryStoreStructurePolicy.MakeKey(structureId: any, parts: { any }): (string?, string?)
	local policy = getPolicy(structureId)
	if policy == nil then
		return nil, "unsupported_structure"
	end
	if type(parts) ~= "table" then
		return nil, "key_parts_invalid"
	end
	if #parts ~= #policy.parts then
		return nil, "key_part_count_mismatch"
	end
	if not hasOnlyExpectedArrayParts(parts, #policy.parts) then
		return nil, "key_parts_malformed"
	end

	local keySegments = { policy.keyPrefix }
	for _, value in ipairs(parts) do
		local normalized, reason = normalizeKeyPart(value)
		if normalized == nil then
			return nil, reason
		end
		table.insert(keySegments, normalized)
	end

	local key = table.concat(keySegments, ":")
	if string.len(key) > MemoryStoreStructurePolicy.MAX_KEY_LENGTH then
		return nil, "key_length_exceeded"
	end
	return key, nil
end

function MemoryStoreStructurePolicy.ResolveExpiration(structureId: any, requestedTtlSeconds: any?): ValidationResult
	local policy = getPolicy(structureId)
	if policy == nil then
		return {
			ok = false,
			reason = "unsupported_structure",
		}
	end

	local ttl = if requestedTtlSeconds == nil then policy.ttlSeconds else requestedTtlSeconds
	if not isFiniteNumber(ttl) or ttl % 1 ~= 0 then
		return {
			ok = false,
			reason = "ttl_invalid",
			structureId = policy.id,
		}
	end
	if ttl < MemoryStoreStructurePolicy.MIN_EXPIRATION_SECONDS then
		return {
			ok = false,
			reason = "ttl_too_short",
			structureId = policy.id,
		}
	end
	if ttl > MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS then
		return {
			ok = false,
			reason = "ttl_too_long",
			structureId = policy.id,
		}
	end
	if ttl > policy.ttlSeconds then
		return {
			ok = false,
			reason = "ttl_exceeds_policy",
			structureId = policy.id,
		}
	end

	return {
		ok = true,
		reason = nil,
		structureId = policy.id,
		ttlSeconds = ttl,
	}
end

function MemoryStoreStructurePolicy.ValidatePayloadSize(structureId: any, encodedPayload: any): ValidationResult
	local policy = getPolicy(structureId)
	if policy == nil then
		return {
			ok = false,
			reason = "unsupported_structure",
		}
	end
	if type(encodedPayload) ~= "string" then
		return {
			ok = false,
			reason = "payload_not_encoded_string",
			structureId = policy.id,
		}
	end

	local payloadBytes = string.len(encodedPayload)
	if payloadBytes > policy.maxPayloadBytes then
		return {
			ok = false,
			reason = "payload_policy_limit_exceeded",
			structureId = policy.id,
		}
	end
	if payloadBytes > MemoryStoreStructurePolicy.MAX_VALUE_BYTES then
		return {
			ok = false,
			reason = "payload_platform_limit_exceeded",
			structureId = policy.id,
		}
	end

	return {
		ok = true,
		reason = nil,
		structureId = policy.id,
	}
end

function MemoryStoreStructurePolicy.ValidatePolicySet(): ValidationResult
	for _, structureId in ipairs(STRUCTURE_ORDER) do
		local policy = STRUCTURES[structureId]
		if policy.id ~= structureId then
			return {
				ok = false,
				reason = "policy_id_mismatch",
				structureId = structureId,
			}
		end
		if string.len(policy.name) > MemoryStoreStructurePolicy.MAX_STRUCTURE_NAME_LENGTH then
			return {
				ok = false,
				reason = "structure_name_length_exceeded",
				structureId = structureId,
			}
		end
		local key, keyReason = MemoryStoreStructurePolicy.MakeKey(structureId, policy.parts)
		if key == nil then
			return {
				ok = false,
				reason = keyReason or "policy_key_invalid",
				structureId = structureId,
			}
		end
		local ttlResult = MemoryStoreStructurePolicy.ResolveExpiration(structureId)
		if not ttlResult.ok then
			return ttlResult
		end
		if policy.maxPayloadBytes > MemoryStoreStructurePolicy.MAX_VALUE_BYTES then
			return {
				ok = false,
				reason = "payload_policy_over_platform_limit",
				structureId = structureId,
			}
		end
	end

	return {
		ok = true,
		reason = nil,
	}
end

return MemoryStoreStructurePolicy
