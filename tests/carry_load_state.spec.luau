--!strict

local CarryLoadState = require("../src/ReplicatedStorage/Shared/GiantRealm/CarryLoadState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local config = {
	CarryCapacity = 1,
	CarryEncumbrancePerTinyfolk = 0.2,
	CarryMinimumSpeedMultiplier = 0.65,
}

do
	local snapshot = CarryLoadState.Snapshot(config, {})
	assertEqual(snapshot.slotsUsed, 0, "empty load uses zero slots")
	assertEqual(snapshot.capacity, 1, "default capacity exposed")
	assertFalse(snapshot.isEncumbered, "empty load is not encumbered")
	assertFalse(snapshot.isAtCapacity, "empty load below capacity")
	assertEqual(snapshot.speedMultiplier, 1, "empty load preserves full speed")
end

do
	local snapshot = CarryLoadState.Snapshot(config, { 20 })
	assertEqual(snapshot.slotsUsed, 1, "single carried target uses one slot")
	assertTrue(snapshot.isEncumbered, "single carried target encumbers carrier")
	assertTrue(snapshot.isAtCapacity, "single carried target fills default capacity")
	assertTrue(snapshot.isOverloaded, "at-capacity carried load is overloaded")
	assertEqual(snapshot.encumbrance, 0.2, "encumbrance applies per Tinyfolk")
	assertEqual(snapshot.speedMultiplier, 0.8, "speed multiplier applies encumbrance")
end

do
	local result = CarryLoadState.CanAcceptTarget(config, { 20 }, 21)
	assertFalse(result.accepted, "capacity-full load rejects extra target")
	assertEqual(result.reason, "carry_capacity_full", "capacity rejection reason")
end

do
	local heavyConfig = {
		CarryCapacity = 3,
		CarryEncumbrancePerTinyfolk = 0.5,
		CarryMinimumSpeedMultiplier = 0.65,
	}
	local snapshot = CarryLoadState.Snapshot(heavyConfig, { 20, 21 })
	assertEqual(snapshot.slotsUsed, 2, "multi-target snapshot counts valid targets")
	assertEqual(snapshot.speedMultiplier, 0.65, "speed multiplier clamps to configured minimum")
end

do
	local allowed = CarryLoadState.CanPerformCarrierInteraction(config, { 20 }, "placeCarried")
	local debugAllowed = CarryLoadState.CanPerformCarrierInteraction(config, { 20 }, "debugInspect")
	local restricted = CarryLoadState.CanPerformCarrierInteraction(config, { 20 }, "throughGapReach")
	local free = CarryLoadState.CanPerformCarrierInteraction(config, {}, "throughGapReach")

	assertTrue(allowed.accepted, "place remains allowed while carrying")
	assertTrue(debugAllowed.accepted, "debug inspect remains allowed while carrying")
	assertFalse(restricted.accepted, "through-gap reach restricted while carrying")
	assertEqual(restricted.reason, "carrier_encumbered", "carrier restriction reason")
	assertTrue(free.accepted, "free carrier can use through-gap reach")
end

print("carry_load_state: all checks passed")
