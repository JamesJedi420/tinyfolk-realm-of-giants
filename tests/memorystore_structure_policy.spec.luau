--!strict

local MemoryStoreStructurePolicy = require("../src/ServerScriptService/Services/MemoryStoreStructurePolicy")

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local expectedApi = {
	GetStructureIds = true,
	GetPolicy = true,
	GetAllPolicies = true,
	MakeKey = true,
	ResolveExpiration = true,
	ValidatePayloadSize = true,
	ValidatePolicySet = true,
}

for key, value in pairs(MemoryStoreStructurePolicy) do
	if type(value) == "function" then
		assertTrue(expectedApi[key] == true, "public API has expected function " .. tostring(key))
	end
end
for key in pairs(expectedApi) do
	assertTrue(type(MemoryStoreStructurePolicy[key]) == "function", "public API exposes " .. key)
end

local policySetResult = MemoryStoreStructurePolicy.ValidatePolicySet()
assertEqual(policySetResult.ok, true, "policy set valid")

local structureIds = MemoryStoreStructurePolicy.GetStructureIds()
assertEqual(#structureIds, 11, "structure count")
assertEqual(structureIds[1], "liveRealmRegistry", "stable order first")
assertEqual(structureIds[11], "captureTimers", "stable order last")

local expectedPolicies: { [string]: any } = {
	liveRealmRegistry = {
		kind = "SortedMap",
		name = "tin_live_realm_registry_v1",
		key = "realm:giant-9402",
		ttlSeconds = 120,
		maxPayloadBytes = 2048,
		parts = { "giant-9402" },
	},
	realmAdmissionQueue = {
		kind = "Queue",
		name = "tin_realm_admission_queue_v1",
		key = "admission:realm-9402:op-100",
		ttlSeconds = 600,
		maxPayloadBytes = 4096,
		parts = { "realm-9402", "op-100" },
	},
	partyMatchmakingQueue = {
		kind = "Queue",
		name = "tin_party_matchmaking_queue_v1",
		key = "party:party-42:op-200",
		ttlSeconds = 300,
		maxPayloadBytes = 4096,
		parts = { "party-42", "op-200" },
	},
	transferLocks = {
		kind = "HashMap",
		name = "tin_transfer_locks_v1",
		key = "handoff:op-300",
		ttlSeconds = 90,
		maxPayloadBytes = 1024,
		parts = { "op-300" },
	},
	queueProcessingIdempotency = {
		kind = "HashMap",
		name = "tin_queue_processing_idempotency_v1",
		key = "queueop:op-350",
		ttlSeconds = 600,
		maxPayloadBytes = 1024,
		parts = { "op-350" },
	},
	escapeOutcomeIdempotency = {
		kind = "HashMap",
		name = "tin_escape_outcome_idempotency_v1",
		key = "escapeop:op-375",
		ttlSeconds = MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS,
		maxPayloadBytes = 1024,
		parts = { "op-375" },
	},
	containmentRewardIdempotency = {
		kind = "HashMap",
		name = "tin_containment_reward_idempotency_v1",
		key = "containreward:op-400",
		ttlSeconds = MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS,
		maxPayloadBytes = 1024,
		parts = { "op-400" },
	},
	realmResourcePairHistory = {
		kind = "HashMap",
		name = "tin_realm_resource_pair_history_v1",
		key = "pair:9402.101.defense_escape_outcome",
		ttlSeconds = 300,
		maxPayloadBytes = 256,
		parts = { "9402.101.defense_escape_outcome" },
	},
	activeRealmCapacity = {
		kind = "HashMap",
		name = "tin_active_realm_capacity_v1",
		key = "capacity:realm-9402",
		ttlSeconds = 120,
		maxPayloadBytes = 1024,
		parts = { "realm-9402" },
	},
	rescueContractQueue = {
		kind = "Queue",
		name = "tin_rescue_contract_queue_v1",
		key = "rescue:queue-abc",
		ttlSeconds = 900,
		maxPayloadBytes = 4096,
		parts = { "queue-abc" },
	},
	captureTimers = {
		kind = "SortedMap",
		name = "tin_capture_timers_v1",
		key = "capture:404:realm-9402",
		ttlSeconds = 3600,
		maxPayloadBytes = 2048,
		parts = { 404, "realm-9402" } :: { any },
	},
}

for _, structureId in ipairs(structureIds) do
	local expected = expectedPolicies[structureId]
	local policy = MemoryStoreStructurePolicy.GetPolicy(structureId)
	assertTrue(policy ~= nil, "policy exists " .. structureId)
	assertEqual(policy.id, structureId, structureId .. " id")
	assertEqual(policy.kind, expected.kind, structureId .. " kind")
	assertEqual(policy.name, expected.name, structureId .. " name")
	assertEqual(policy.ttlSeconds, expected.ttlSeconds, structureId .. " ttl")
	assertEqual(policy.maxPayloadBytes, expected.maxPayloadBytes, structureId .. " max payload")
	assertTrue(
		string.len(policy.name) <= MemoryStoreStructurePolicy.MAX_STRUCTURE_NAME_LENGTH,
		structureId .. " name length"
	)

	local key, reason = MemoryStoreStructurePolicy.MakeKey(structureId, expected.parts)
	assertEqual(reason, nil, structureId .. " key reason")
	assertEqual(key, expected.key, structureId .. " key")
	assertTrue(string.len(key :: string) <= MemoryStoreStructurePolicy.MAX_KEY_LENGTH, structureId .. " key length")

	local ttl = MemoryStoreStructurePolicy.ResolveExpiration(structureId)
	assertEqual(ttl.ok, true, structureId .. " default ttl ok")
	assertEqual(ttl.ttlSeconds, expected.ttlSeconds, structureId .. " default ttl")

	local payload = string.rep("x", expected.maxPayloadBytes)
	local payloadResult = MemoryStoreStructurePolicy.ValidatePayloadSize(structureId, payload)
	assertEqual(payloadResult.ok, true, structureId .. " payload limit accepted")

	local tooLargePayload = string.rep("x", expected.maxPayloadBytes + 1)
	local tooLargeResult = MemoryStoreStructurePolicy.ValidatePayloadSize(structureId, tooLargePayload)
	assertEqual(tooLargeResult.ok, false, structureId .. " payload too large rejected")
	assertEqual(tooLargeResult.reason, "payload_policy_limit_exceeded", structureId .. " payload too large reason")
end

local cloneA = MemoryStoreStructurePolicy.GetPolicy("liveRealmRegistry")
local cloneB = MemoryStoreStructurePolicy.GetPolicy("liveRealmRegistry")
cloneA.parts[1] = "mutated"
assertEqual(cloneB.parts[1], "realmId", "policy clone protects parts")

local allPolicies = MemoryStoreStructurePolicy.GetAllPolicies()
allPolicies[1].parts[1] = "mutated"
local livePolicyAfterMutation = MemoryStoreStructurePolicy.GetPolicy("liveRealmRegistry")
assertEqual(livePolicyAfterMutation.parts[1], "realmId", "all policies clone protects parts")

local missingPolicy = MemoryStoreStructurePolicy.GetPolicy("unknown")
assertEqual(missingPolicy, nil, "unknown policy nil")
local nonStringPolicy = MemoryStoreStructurePolicy.GetPolicy(123)
assertEqual(nonStringPolicy, nil, "non-string policy nil")

local unsupportedKey, unsupportedReason = MemoryStoreStructurePolicy.MakeKey("unknown", {})
assertEqual(unsupportedKey, nil, "unsupported key nil")
assertEqual(unsupportedReason, "unsupported_structure", "unsupported key reason")

local invalidPartsKey, invalidPartsReason = MemoryStoreStructurePolicy.MakeKey("activeRealmCapacity", nil :: any)
assertEqual(invalidPartsKey, nil, "invalid parts key nil")
assertEqual(invalidPartsReason, "key_parts_invalid", "invalid parts reason")

local mismatchKey, mismatchReason = MemoryStoreStructurePolicy.MakeKey("activeRealmCapacity", { "realm-a", "extra" })
assertEqual(mismatchKey, nil, "mismatch key nil")
assertEqual(mismatchReason, "key_part_count_mismatch", "mismatch reason")

local malformedParts: { any } = { "realm-a" }
(malformedParts :: any).unexpected = "ignored?"
local malformedKey, malformedReason = MemoryStoreStructurePolicy.MakeKey("activeRealmCapacity", malformedParts)
assertEqual(malformedKey, nil, "malformed parts key nil")
assertEqual(malformedReason, "key_parts_malformed", "malformed parts reason")

local invalidStringKey, invalidStringReason = MemoryStoreStructurePolicy.MakeKey("activeRealmCapacity", { "realm:bad" })
assertEqual(invalidStringKey, nil, "invalid string key nil")
assertEqual(invalidStringReason, "key_part_segment_invalid", "invalid string reason")

local invalidNumberParts: { any } = { -1, "realm-a" }
local invalidNumberKey, invalidNumberReason = MemoryStoreStructurePolicy.MakeKey("captureTimers", invalidNumberParts)
assertEqual(invalidNumberKey, nil, "invalid number key nil")
assertEqual(invalidNumberReason, "key_part_number_invalid", "invalid number reason")

local longSegment = string.rep("a", 49)
local longKey, longReason = MemoryStoreStructurePolicy.MakeKey("activeRealmCapacity", { longSegment })
assertEqual(longKey, nil, "long segment key nil")
assertEqual(longReason, "key_part_segment_invalid", "long segment reason")

local explicitTtl = MemoryStoreStructurePolicy.ResolveExpiration("activeRealmCapacity", 30)
assertEqual(explicitTtl.ok, true, "explicit ttl ok")
assertEqual(explicitTtl.ttlSeconds, 30, "explicit ttl")

local beyondPolicyTtl = MemoryStoreStructurePolicy.ResolveExpiration("activeRealmCapacity", 121)
assertEqual(beyondPolicyTtl.ok, false, "beyond policy ttl rejected")
assertEqual(beyondPolicyTtl.reason, "ttl_exceeds_policy", "beyond policy ttl reason")

local zeroTtl = MemoryStoreStructurePolicy.ResolveExpiration("activeRealmCapacity", 0)
assertEqual(zeroTtl.ok, false, "zero ttl rejected")
assertEqual(zeroTtl.reason, "ttl_too_short", "zero ttl reason")

local fractionalTtl = MemoryStoreStructurePolicy.ResolveExpiration("activeRealmCapacity", 1.5)
assertEqual(fractionalTtl.ok, false, "fractional ttl rejected")
assertEqual(fractionalTtl.reason, "ttl_invalid", "fractional ttl reason")

local tooLongTtl = MemoryStoreStructurePolicy.ResolveExpiration(
	"activeRealmCapacity",
	MemoryStoreStructurePolicy.MAX_EXPIRATION_SECONDS + 1
)
assertEqual(tooLongTtl.ok, false, "too long ttl rejected")
assertEqual(tooLongTtl.reason, "ttl_too_long", "too long ttl reason")

local unsupportedTtl = MemoryStoreStructurePolicy.ResolveExpiration("unknown")
assertEqual(unsupportedTtl.ok, false, "unsupported ttl rejected")
assertEqual(unsupportedTtl.reason, "unsupported_structure", "unsupported ttl reason")

local encodedStringRequired = MemoryStoreStructurePolicy.ValidatePayloadSize("activeRealmCapacity", {})
assertEqual(encodedStringRequired.ok, false, "encoded string required rejected")
assertEqual(encodedStringRequired.reason, "payload_not_encoded_string", "encoded string required reason")

local unsupportedPayload = MemoryStoreStructurePolicy.ValidatePayloadSize("unknown", "")
assertEqual(unsupportedPayload.ok, false, "unsupported payload rejected")
assertEqual(unsupportedPayload.reason, "unsupported_structure", "unsupported payload reason")

print("memorystore_structure_policy: all checks passed")
