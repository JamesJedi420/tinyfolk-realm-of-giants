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

local function newTrap()
	return SnareTrapState.NewRecord(
		"Trap_001",
		SnareTrapConfig.StructureId,
		9001,
		100,
		{ x = 24, y = 0, z = 24 },
		SnareTrapConfig.TriggerRadiusStuds,
		SnareTrapConfig.TriggerDurationSeconds
	)
end

local trap = newTrap()
assertEqual(trap.trapId, "Trap_001", "record stores trap id")
assertEqual(trap.structureId, SnareTrapConfig.StructureId, "record stores structure id")
assertEqual(trap.status, SnareTrapState.Status.Armed, "record starts armed")
assertTrue(SnareTrapState.IsActive(trap, 110), "record is active before trigger")

local missTriggered, missReason, missNext = SnareTrapState.ResolveContact(trap, 4200, { x = 100, y = 0, z = 100 }, 111)
assertTrue(not missTriggered, "out-of-range contact does not trigger")
assertEqual(missReason, "snare_trap_out_of_range", "out-of-range reason is deterministic")
assertTrue(missNext ~= nil, "out-of-range contact returns snapshot copy")

local invalidTriggered, invalidReason, invalidNext = SnareTrapState.ResolveContact(trap, 4200, nil, 111)
assertTrue(not invalidTriggered, "malformed contact position does not trigger")
assertEqual(invalidReason, "snare_trap_invalid_contact_position", "malformed contact reason is deterministic")
assertTrue(invalidNext ~= nil, "malformed contact still returns snapshot copy")

local triggered, reason, nextTrap = SnareTrapState.ResolveContact(trap, 4200, { x = 24, y = 0, z = 24 }, 112)
assertTrue(triggered, "in-range contact triggers")
assertEqual(reason, "triggered", "trigger reason is deterministic")
assertTrue(nextTrap ~= nil, "trigger returns updated record")
if nextTrap then
	assertEqual(nextTrap.status, SnareTrapState.Status.Triggered, "triggered record stores status")
	assertEqual(nextTrap.triggeredByUserId, 4200, "triggered record stores triggering user id")
	assertEqual(nextTrap.triggeredAt, 112, "triggered record stores trigger time")
	assertTrue(not SnareTrapState.IsActive(nextTrap, 113), "triggered record is not armed afterward")
end

local disarmed, disarmReason, disarmedTrap = SnareTrapState.ResolveDisarm(newTrap(), 5100, 115)
assertTrue(disarmed, "armed trap can be disarmed")
assertEqual(disarmReason, "disarmed", "disarm reason is deterministic")
assertEqual(disarmedTrap.status, SnareTrapState.Status.Disarmed, "disarm stores status")
assertEqual(disarmedTrap.resolvedByUserId, 5100, "disarm stores actor")

local rescueAccepted, rescueReason, rescuedTrap = SnareTrapState.ResolveRescue(nextTrap, 5101, 116)
assertTrue(rescueAccepted, "triggered trap can be rescued")
assertEqual(rescueReason, "rescued", "rescue reason is deterministic")
assertEqual(rescuedTrap.status, SnareTrapState.Status.Rescued, "rescue stores status")

local rescueAgain, rescueAgainReason = SnareTrapState.ResolveRescue(rescuedTrap, 5102, 117)
assertTrue(not rescueAgain, "terminal trap cannot be rescued again")
assertEqual(rescueAgainReason, "snare_trap_terminal", "terminal rescue reason is deterministic")

local expired, expiryReason, expiredTrap = SnareTrapState.ResolveExpiry(newTrap(), 131)
assertTrue(expired, "trap expires after duration")
assertEqual(expiryReason, "expired", "expiry reason is deterministic")
assertEqual(expiredTrap.status, SnareTrapState.Status.Expired, "expiry stores status")

local invalidated, invalidatedReason, invalidatedTrap = SnareTrapState.ResolveInvalidated(newTrap(), 118)
assertTrue(invalidated, "active trap can be invalidated")
assertEqual(invalidatedReason, "invalidated", "invalidated reason is deterministic")
assertEqual(invalidatedTrap.status, SnareTrapState.Status.Invalidated, "invalidated stores status")

local destroyed, destroyedReason, destroyedTrap = SnareTrapState.ResolveDestroyed(newTrap(), 119)
assertTrue(destroyed, "active trap can be destroyed")
assertEqual(destroyedReason, "destroyed", "destroy reason is deterministic")
assertEqual(destroyedTrap.status, SnareTrapState.Status.Destroyed, "destroy stores status")

local snapshot = SnareTrapState.BuildSnapshot(nextTrap, 113)
assertTrue(snapshot ~= nil, "snapshot is available for triggered record")
if snapshot then
	assertEqual(snapshot.trapId, "Trap_001", "snapshot preserves trap id")
	assertEqual(snapshot.status, SnareTrapState.Status.Triggered, "snapshot preserves status")
	assertTrue(not snapshot.active, "snapshot marks triggered trap inactive")
	assertTrue(not snapshot.armed, "snapshot marks triggered trap unarmed")
	snapshot.center.x = 999
	local cleanSnapshot = SnareTrapState.BuildSnapshot(nextTrap, 113)
	assertEqual(cleanSnapshot.center.x, 24, "snapshot center is cloned")
end

print("snare_trap_state: all checks passed")
