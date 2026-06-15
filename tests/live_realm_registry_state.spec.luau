--!strict

local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function makeEntry(overrides: any?): any
	local input = {
		realmId = "giant_realm_9001",
		ownerUserId = 9001,
		privateServerId = "giant_realm_ps_9001",
		jobId = "job-abc",
		accessMode = LiveRealmRegistryState.AccessMode.Public,
		playerCount = 2,
		capacity = 8,
		dangerRating = 0.5,
		updatedAt = 100,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			input[key] = value
		end
	end
	return input
end

assertEqual(
	LiveRealmRegistryState.FormatRealmId(9001),
	RealmTransferState.FormatRealmId(9001),
	"format realm id parity"
)

local created = LiveRealmRegistryState.NewEntry(makeEntry())
assertTrue(created.accepted, "entry accepted")
assertEqual(created.entry.realmId, "giant_realm_9001", "realm id")
assertEqual(created.entry.jobId, "job-abc", "job id separate from realm id")

local mismatch = LiveRealmRegistryState.NewEntry(makeEntry({
	realmId = "giant_realm_9002",
}))
assertFalse(mismatch.accepted, "realm owner mismatch rejected")
assertEqual(mismatch.reason, "realm_owner_mismatch", "realm owner mismatch reason")

local encoded, encodeReason = LiveRealmRegistryState.EncodeRegistryEntry(created.entry :: any)
assertEqual(encodeReason, nil, "encode reason")
assertTrue(type(encoded) == "string", "encoded payload")

local decoded, decodeReason = LiveRealmRegistryState.DecodeRegistryEntry(encoded)
assertEqual(decodeReason, nil, "decode reason")
assertEqual(decoded.jobId, "job-abc", "decoded job id")
assertEqual(decoded.realmId, "giant_realm_9001", "decoded realm id")

local refreshed = LiveRealmRegistryState.RefreshEntry(created.entry :: any, {
	playerCount = 4,
	jobId = "job-next",
	lifecycle = LiveRealmRegistryState.Lifecycle.Active,
}, 120)
assertTrue(refreshed.accepted, "refresh accepted")
assertEqual(refreshed.entry.playerCount, 4, "refresh player count")
assertEqual(refreshed.entry.jobId, "job-next", "refresh job id")

assertTrue(LiveRealmRegistryState.IsAvailable(created.entry :: any, 100, 120), "active entry available before ttl")
assertTrue(
	LiveRealmRegistryState.IsAvailable(refreshed.entry :: any, 120, 120),
	"active entry available at refresh time"
)
assertFalse(LiveRealmRegistryState.IsAvailable(refreshed.entry :: any, 241, 120), "active entry stale after ttl")

local availability = LiveRealmRegistryState.BuildAvailabilitySnapshot(refreshed.entry :: any, 120, 120)
assertTrue(availability ~= nil, "availability snapshot")
assertTrue(availability.isAvailable, "availability true")
assertEqual(availability.privateServerId, "giant_realm_ps_9001", "availability private server id")
assertEqual((availability :: any).jobId, nil, "availability omits job id")

local publishInput, buildReason = LiveRealmRegistryState.BuildPublishInput({
	ownerUserId = 9001,
	now = 50,
	privateServerId = "ps-live",
	jobId = "job-live",
	playerCount = 1,
})
assertEqual(buildReason, nil, "publish input reason")
assertEqual(publishInput.realmId, "giant_realm_9001", "publish realm id")
assertEqual(publishInput.privateServerId, "ps-live", "publish private server id")
assertEqual(publishInput.lifecycle, LiveRealmRegistryState.Lifecycle.Starting, "publish default lifecycle")

local stablePrivateServerId = LiveRealmRegistryState.ResolveStablePrivateServerId(9001, "")
assertEqual(stablePrivateServerId, "giant_realm_ps_9001", "stable private server fallback")

print("live_realm_registry_state.spec.luau: all checks passed")
