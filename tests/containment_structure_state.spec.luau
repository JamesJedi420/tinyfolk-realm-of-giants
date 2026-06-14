--!strict

local ContainmentStructureConfig = require("../src/ReplicatedStorage/Shared/Config/ContainmentStructureConfig")
local ContainmentStructureState = require("../src/ReplicatedStorage/Shared/GiantRealm/ContainmentStructureState")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function newRecord()
	return ContainmentStructureState.NewRecord(
		"ContainmentStructure_A",
		"cage",
		"ContainmentStructureZone_A",
		2,
		true,
		nil,
		ContainmentStructureConfig
	)
end

do
	local record = newRecord()
	assertEqual(ContainmentStructureState.OccupantCount(record), 0, "new record has zero occupants")
	assertTrue(
		ContainmentStructureState.HasEscapeInteraction(ContainmentStructureConfig, record),
		"cage exposes escape interaction"
	)
end

do
	local record = newRecord()
	local assign = ContainmentStructureState.AssignOccupant(record, 4201)
	assertTrue(assign.accepted, "first assign accepts")
	assertEqual(assign.record.occupantUserIds[1], 4201, "occupant stored")
	assertEqual(ContainmentStructureState.OccupantCount(assign.record), 1, "occupant count is one")
end

do
	local record = newRecord()
	local first = ContainmentStructureState.AssignOccupant(record, 4201)
	local second = ContainmentStructureState.AssignOccupant(first.record, 4202)
	assertTrue(second.accepted, "second assign accepts within capacity")
	assertEqual(ContainmentStructureState.OccupantCount(second.record), 2, "occupant count is two")
	local third = ContainmentStructureState.AssignOccupant(second.record, 4203)
	assertFalse(third.accepted, "third assign rejects at capacity")
	assertEqual(third.reason, "structure_capacity_full", "capacity full reason")
end

do
	local record = newRecord()
	local first = ContainmentStructureState.AssignOccupant(record, 4201)
	local repeatAssign = ContainmentStructureState.AssignOccupant(first.record, 4201)
	assertFalse(repeatAssign.accepted, "duplicate occupant rejects")
	assertEqual(repeatAssign.reason, "occupant_already_assigned", "duplicate occupant reason")
end

do
	local record = newRecord()
	local assigned = ContainmentStructureState.AssignOccupant(record, 4201)
	local removed = ContainmentStructureState.RemoveOccupant(assigned.record, 4201)
	assertTrue(removed.accepted, "remove occupant accepts")
	assertEqual(ContainmentStructureState.OccupantCount(removed.record), 0, "occupant count clears")
end

do
	local record = newRecord()
	local canRescue =
		ContainmentStructureState.CanRescueOccupant(ContainmentStructureConfig, record, 9001, 4201, true, true, 8)
	assertFalse(canRescue.accepted, "rescue rejects without occupant")
	assertEqual(canRescue.reason, "occupant_not_found", "missing occupant reason")

	local assigned = ContainmentStructureState.AssignOccupant(record, 4201)
	local rescueReady = ContainmentStructureState.CanRescueOccupant(
		ContainmentStructureConfig,
		assigned.record,
		9001,
		4201,
		true,
		true,
		8
	)
	assertTrue(rescueReady.accepted, "rescue accepts for assigned occupant in range")
end

print("containment_structure_state: all checks passed")
