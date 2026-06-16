--!strict

local RealmReservedServerAllocationState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/RealmReservedServerAllocationState")
local LiveRealmHubRouting = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")
local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")

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

assertTrue(
	RealmReservedServerAllocationState.IsStablePlaceholderAccessCode("giant_realm_ps_9002", 9002),
	"stable placeholder detected"
)
assertTrue(
	not RealmReservedServerAllocationState.IsUsableReservedAccessCode("giant_realm_ps_9002", 9002),
	"stable placeholder is not usable"
)
assertTrue(
	RealmReservedServerAllocationState.IsUsableReservedAccessCode("reserved-code-9002", 9002),
	"real reserved code is usable"
)

local built = RealmReservedServerAllocationState.BuildAllocationRecord({
	ownerUserId = 9002,
	reservedAccessCode = "reserved-code-9002",
	destinationPlaceId = 12345,
	allocatedAt = 100,
	created = true,
})
assertTrue(built.accepted, "allocation record built")
assertEqual(built.record.realmId, "giant_realm_9002", "allocation realm id")

local mirror = RealmReservedServerAllocationState.ToMirrorRecord(built.record :: any, 101)
assertTrue(mirror ~= nil, "mirror record built")
local encoded, encodeReason = RealmReservedServerAllocationState.EncodeMirrorRecord(mirror :: any)
assertEqual(encodeReason, nil, "mirror encode reason")
assertEqual(type(encoded), "string", "mirror encoded")

local decoded, decodeReason = RealmReservedServerAllocationState.DecodeMirrorRecord(encoded)
assertEqual(decodeReason, nil, "mirror decode reason")
assertEqual(decoded.reservedAccessCode, "reserved-code-9002", "mirror round trip access code")

local saveRecord = RealmReservedServerAllocationState.ToSaveRecord(built.record :: any)
local validSave, saveReason = RealmReservedServerAllocationState.ValidateSaveRecord(saveRecord, 9002)
assertTrue(validSave, "save record valid: " .. tostring(saveReason))

local fromSave = RealmReservedServerAllocationState.FromSaveRecord(9002, saveRecord)
assertEqual(fromSave.reservedAccessCode, "reserved-code-9002", "from save access code")

local publicSnapshot = {
	realmId = "giant_realm_9002",
	ownerUserId = 9002,
	privateServerId = "giant_realm_ps_9002",
	accessMode = LiveRealmRegistryState.AccessMode.Public,
	isAvailable = true,
}

local durableResolved = LiveRealmHubRouting.ResolveTeleportAccessCodeDetailed(publicSnapshot, "reserved-code-9002", nil)
assertEqual(durableResolved.accessCode, "reserved-code-9002", "public durable access code resolved")
assertEqual(durableResolved.resolverPath, "durable_allocation", "public durable resolver path")

local liveSnapshot = {
	realmId = "giant_realm_9001",
	ownerUserId = 9001,
	privateServerId = "ps-live-9001",
	accessMode = LiveRealmRegistryState.AccessMode.Private,
	isAvailable = true,
}
local liveResolved = LiveRealmHubRouting.ResolveTeleportAccessCodeDetailed(liveSnapshot, "reserved-code-9001", nil)
assertEqual(liveResolved.accessCode, "ps-live-9001", "live registry access code wins")
assertEqual(liveResolved.resolverPath, "live_registry", "live registry resolver path")

local admissionOk, admissionReason =
	RealmReservedServerAllocationState.ValidateDispatchAdmission("standard", publicSnapshot)
assertTrue(admissionOk, "standard entry accepted for public realm")
assertEqual(admissionReason, "accepted", "standard public admission reason")

local privateAdmissionOk, privateAdmissionReason =
	RealmReservedServerAllocationState.ValidateDispatchAdmission("standard", {
		accessMode = LiveRealmRegistryState.AccessMode.Private,
	})
assertEqual(privateAdmissionOk, false, "standard entry rejected for private realm")
assertEqual(privateAdmissionReason, "entry_access_mode_rejected", "standard private admission reason")

local raidAdmissionOk, raidAdmissionReason = RealmReservedServerAllocationState.ValidateDispatchAdmission("standard", {
	accessMode = LiveRealmRegistryState.AccessMode.RaidEnabled,
})
assertTrue(raidAdmissionOk, "standard entry accepted for raid_enabled realm")
assertEqual(raidAdmissionReason, "accepted", "standard raid_enabled admission reason")

print("realm_reserved_server_allocation_state: all checks passed")
