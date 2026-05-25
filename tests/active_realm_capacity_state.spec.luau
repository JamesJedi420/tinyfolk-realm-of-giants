--!strict

local ActiveRealmCapacityState = require("../src/ServerScriptService/Services/ActiveRealmCapacityState")

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
	local entry: any = {
		realmId = "realm-9402",
		currentTinyfolk = 2,
		currentGiants = 1,
		reservedSlots = 1,
		maxTinyfolk = 5,
		maxGiants = 2,
		updatedAt = 100,
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			entry[key] = value
		end
	end
	return entry
end

local created = ActiveRealmCapacityState.NewEntry(makeEntry())
assertTrue(created.accepted, "valid entry accepted")
assertEqual(created.reason, "accepted", "valid entry reason")
assertEqual((created.snapshot :: any).realmId, "realm-9402", "snapshot stores realm id")

local snapshot = ActiveRealmCapacityState.GetSnapshot(created.entry :: any)
assertEqual((snapshot :: any).reservedSlots, 1, "snapshot includes reserved slots")
local mutableSnapshot = snapshot :: any
mutableSnapshot.reservedSlots = 99
local snapshotAfterMutation = ActiveRealmCapacityState.GetSnapshot(created.entry :: any)
assertEqual((snapshotAfterMutation :: any).reservedSlots, 1, "snapshot clone protects entry")

local invalidCases = {
	{ input = nil, reason = "entry_invalid", label = "nil entry" },
	{ input = makeEntry({ realmId = "" }), reason = "realm_id_invalid", label = "empty realm" },
	{ input = makeEntry({ currentTinyfolk = -1 }), reason = "current_tinyfolk_invalid", label = "negative tinyfolk" },
	{ input = makeEntry({ currentGiants = 1.5 }), reason = "current_giants_invalid", label = "fractional giants" },
	{ input = makeEntry({ reservedSlots = -1 }), reason = "reserved_slots_invalid", label = "negative reserved" },
	{ input = makeEntry({ maxTinyfolk = -1 }), reason = "max_tinyfolk_invalid", label = "negative max tinyfolk" },
	{ input = makeEntry({ maxGiants = math.huge }), reason = "max_giants_invalid", label = "infinite max giants" },
	{ input = makeEntry({ updatedAt = -1 }), reason = "updated_at_invalid", label = "negative updated at" },
	{
		input = makeEntry({ currentTinyfolk = 6 }),
		reason = "current_tinyfolk_exceeds_max",
		label = "tinyfolk exceeds max",
	},
	{ input = makeEntry({ currentGiants = 3 }), reason = "current_giants_exceeds_max", label = "giants exceed max" },
	{
		input = makeEntry({ currentTinyfolk = 4, reservedSlots = 2 }),
		reason = "reserved_slots_exceed_capacity",
		label = "reserved exceeds remaining",
	},
}

for _, case in ipairs(invalidCases) do
	local result = ActiveRealmCapacityState.NewEntry(case.input)
	assertFalse(result.accepted, case.label .. " rejected")
	assertEqual(result.reason, case.reason, case.label .. " reason")
end

local refreshed = ActiveRealmCapacityState.Refresh(created.entry :: any, 120)
assertTrue(refreshed.accepted, "refresh accepted")
assertEqual((refreshed.entry :: any).updatedAt, 120, "refresh updates timestamp")

local invalidRefresh = ActiveRealmCapacityState.Refresh(created.entry :: any, 0 / 0)
assertFalse(invalidRefresh.accepted, "invalid refresh timestamp rejected")
assertEqual(invalidRefresh.reason, "updated_at_invalid", "invalid refresh reason")

local reserved = ActiveRealmCapacityState.ReserveTinyfolkSlots(created.entry :: any, 2, 130)
assertTrue(reserved.accepted, "reservation accepted")
assertEqual((reserved.entry :: any).reservedSlots, 3, "reservation increments slots")
assertEqual((reserved.entry :: any).updatedAt, 130, "reservation updates timestamp")

local overCapacity = ActiveRealmCapacityState.ReserveTinyfolkSlots(reserved.entry :: any, 1, 131)
assertFalse(overCapacity.accepted, "over capacity reservation rejected")
assertEqual(overCapacity.reason, "tinyfolk_capacity_unavailable", "over capacity reason")

local invalidReserveCount = ActiveRealmCapacityState.ReserveTinyfolkSlots(created.entry :: any, 0, 132)
assertFalse(invalidReserveCount.accepted, "zero reserve count rejected")
assertEqual(invalidReserveCount.reason, "count_invalid", "zero reserve reason")

local zeroCapacity = ActiveRealmCapacityState.NewEntry(makeEntry({
	currentTinyfolk = 0,
	currentGiants = 0,
	reservedSlots = 0,
	maxTinyfolk = 0,
	maxGiants = 0,
}))
assertTrue(zeroCapacity.accepted, "zero capacity entry accepted")
local zeroCapacityReserve = ActiveRealmCapacityState.ReserveTinyfolkSlots(zeroCapacity.entry :: any, 1, 133)
assertFalse(zeroCapacityReserve.accepted, "zero capacity reserve rejected")
assertEqual(zeroCapacityReserve.reason, "tinyfolk_capacity_unavailable", "zero capacity reserve reason")

local committed = ActiveRealmCapacityState.CommitTinyfolkArrival(reserved.entry :: any, 2, 140)
assertTrue(committed.accepted, "commit accepted")
assertEqual((committed.entry :: any).currentTinyfolk, 4, "commit increments current tinyfolk")
assertEqual((committed.entry :: any).reservedSlots, 1, "commit consumes reserved slots")

local overCommit = ActiveRealmCapacityState.CommitTinyfolkArrival(committed.entry :: any, 2, 141)
assertFalse(overCommit.accepted, "over commit rejected")
assertEqual(overCommit.reason, "reserved_slots_insufficient", "over commit reason")

local released = ActiveRealmCapacityState.ReleaseReservedSlots(committed.entry :: any, 1, 150)
assertTrue(released.accepted, "release accepted")
assertEqual((released.entry :: any).reservedSlots, 0, "release decrements slots")
assertEqual((released.entry :: any).updatedAt, 150, "release updates timestamp")

local overRelease = ActiveRealmCapacityState.ReleaseReservedSlots(released.entry :: any, 1, 151)
assertFalse(overRelease.accepted, "over release rejected")
assertEqual(overRelease.reason, "reserved_slots_insufficient", "over release reason")

assertFalse(ActiveRealmCapacityState.IsStale(created.entry :: any, 219, 120), "entry not stale before ttl")
assertTrue(ActiveRealmCapacityState.IsStale(created.entry :: any, 220, 120), "entry stale at ttl")
assertTrue(ActiveRealmCapacityState.IsStale(created.entry :: any, 200, 1.5), "invalid ttl is stale")

print("active_realm_capacity_state: all checks passed")
