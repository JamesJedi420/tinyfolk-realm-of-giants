--!nocheck
--!nolint BuiltinGlobalWrite

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local RealmReservedServerAllocationState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/RealmReservedServerAllocationState")
local RealmReservedServerAllocationStore =
	require("../src/ServerScriptService/Services/RealmReservedServerAllocationStore")
local MemoryStoreStructurePolicy = require("../src/ServerScriptService/Services/MemoryStoreStructurePolicy")

require("../src/ServerScriptService/Services/RealmReservedServerAllocationBootstrap.server")

local api = _G._RealmReservedServerAllocationService_QueryAPI
assertTrue(type(api) == "table", "allocation query api present")

api.ResetForTests()

local reserveCalls = 0
local saveCalls = 0

api.ConfigureForTests({
	now = function(): number
		return 200
	end,
	teleportService = {
		ReserveServer = function(_self: any, placeId: number): string
			reserveCalls += 1
			assertEqual(placeId, 12345, "reserve place id")
			return "reserved-code-5001"
		end,
	},
	profilePersistenceGateway = {
		SaveGiantRealmProfile = function(ownerUserId: number): any
			saveCalls += 1
			assertEqual(ownerUserId, 5001, "save owner user id")
			return { ok = true }
		end,
	},
	allocationStore = RealmReservedServerAllocationStore.Create({
		allocationState = RealmReservedServerAllocationState,
		structurePolicy = MemoryStoreStructurePolicy,
	}),
})

local firstEnsure = api.EnsureAllocation({
	ownerUserId = 5001,
	destinationPlaceId = 12345,
})
assertTrue(firstEnsure.accepted, "first ensure accepted")
assertTrue(firstEnsure.created, "first ensure created")
assertEqual(firstEnsure.record.reservedAccessCode, "reserved-code-5001", "first ensure access code")
assertEqual(reserveCalls, 1, "reserve called once")
assertEqual(saveCalls, 1, "save called once")

local secondEnsure = api.EnsureAllocation({
	ownerUserId = 5001,
	destinationPlaceId = 12345,
})
assertTrue(secondEnsure.accepted, "second ensure accepted")
assertEqual(secondEnsure.created, false, "second ensure idempotent")
assertEqual(reserveCalls, 1, "reserve not called again")

local resolve = api.ResolveAccessCodeForRealm("giant_realm_5001")
assertTrue(resolve.accepted, "resolve accepted")
assertEqual(resolve.accessCode, "reserved-code-5001", "resolve access code")

api.ResetForTests()
api.ConfigureForTests({
	allocationStore = RealmReservedServerAllocationStore.Create({
		allocationState = RealmReservedServerAllocationState,
		structurePolicy = MemoryStoreStructurePolicy,
	}),
})

local missing = api.ResolveAccessCodeForRealm("giant_realm_5001")
assertEqual(missing.accepted, false, "missing allocation rejected")
assertEqual(missing.reason, "reserved_server_unallocated", "missing allocation reason")

local applied, applyReason = api.ApplyPersistenceState({
	reservedAccessCode = "reserved-code-7001",
	destinationPlaceId = 12345,
	allocatedAt = 100,
}, 7001)
assertTrue(applied, "apply persistence accepted: " .. tostring(applyReason))

local built = api.BuildPersistenceState(7001)
assertEqual(built.reservedAccessCode, "reserved-code-7001", "build persistence access code")

print("realm_reserved_server_allocation_service_runtime_entrypoint: all checks passed")
