--!nocheck
local SnareTrapConfig = require("../src/ReplicatedStorage/Shared/Config/SnareTrapConfig")
local SnareTrapState = require("../src/ReplicatedStorage/Shared/GiantRealm/SnareTrapState")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected %q got %q", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local trap = SnareTrapState.NewRecord(
	SnareTrapConfig.StructureId,
	9001,
	100,
	{ x = 24, y = 0, z = 24 },
	SnareTrapConfig.TriggerRadiusStuds,
	SnareTrapConfig.TriggerDurationSeconds
)

assertEqual(trap.structureId, SnareTrapConfig.StructureId, "record stores structure id")
assertEqual(trap.placedByUserId, 9001, "record stores placer user id")
assertTrue(SnareTrapState.IsActive(trap, 110), "record is active before trigger")

local missTriggered, missReason, missNext = SnareTrapState.ResolveContact(trap, 4200, { x = 100, y = 0, z = 100 }, 111)
assertTrue(not missTriggered, "out-of-range contact does not trigger")
assertEqual(missReason, "snare_trap_out_of_range", "out-of-range reason is deterministic")
assertTrue(missNext ~= nil, "out-of-range contact returns snapshot copy")

local invalidTriggered, invalidReason, invalidNext = SnareTrapState.ResolveContact(trap, 4200, nil, 111)
assertTrue(not invalidTriggered, "malformed contact position does not trigger")
assertEqual(invalidReason, "snare_trap_invalid_contact_position", "malformed contact reason is deterministic")
assertTrue(invalidNext ~= nil, "malformed contact still returns snapshot copy")

local invalidUserTriggered, invalidUserReason, invalidUserNext =
	SnareTrapState.ResolveContact(trap, nil, { x = 24, y = 0, z = 24 }, 111)
assertTrue(not invalidUserTriggered, "malformed triggering user does not trigger")
assertEqual(
	invalidUserReason,
	"snare_trap_invalid_triggering_user",
	"malformed triggering user reason is deterministic"
)
assertTrue(invalidUserNext ~= nil, "malformed triggering user still returns snapshot copy")

local triggered, reason, nextTrap = SnareTrapState.ResolveContact(trap, 4200, { x = 24, y = 0, z = 24 }, 112)
assertTrue(triggered, "in-range contact triggers")
assertEqual(reason, "triggered", "trigger reason is deterministic")
assertTrue(nextTrap ~= nil, "trigger returns updated record")
if nextTrap then
	assertEqual(nextTrap.triggeredByUserId, 4200, "triggered record stores triggering user id")
	assertEqual(nextTrap.triggeredAt, 112, "triggered record stores trigger time")
	assertTrue(not SnareTrapState.IsActive(nextTrap, 113), "triggered record is inactive afterward")
end

local snapshot = SnareTrapState.BuildSnapshot(nextTrap, 113)
assertTrue(snapshot ~= nil, "snapshot is available for triggered record")
if snapshot then
	assertEqual(snapshot.structureId, SnareTrapConfig.StructureId, "snapshot preserves structure id")
	assertTrue(not snapshot.active, "snapshot marks triggered trap inactive")
	assertTrue(not snapshot.armed, "snapshot marks triggered trap unarmed")
end
