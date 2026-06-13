--!strict

local DefensivePropConfig = require("../src/ReplicatedStorage/Shared/Config/DefensivePropConfig")
local DefensivePropState = require("../src/ReplicatedStorage/Shared/GiantRealm/DefensivePropState")

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
	return DefensivePropState.NewRecord("DefensiveProp_A", "crate", "DefensivePropZone_A", true)
end

do
	local record = newRecord()
	assertEqual(DefensivePropState.ResolveStatus(DefensivePropConfig, record, 10), "Ready", "new record is Ready")
end

do
	local record = newRecord()
	local drop = DefensivePropState.CreateDrop(DefensivePropConfig, record, 4201, 20)
	assertTrue(drop.accepted, "drop accepts")
	assertEqual(drop.snapshot.state, "Dropped", "drop enters Dropped startup phase")
	assertEqual(drop.record.barrierStartupEndsAt, 21, "startup ends deterministically")
	assertEqual(drop.record.barrierActiveEndsAt, 26, "active ends after startup")
	assertFalse(
		DefensivePropState.BlocksGiantMacroRoutes(DefensivePropConfig, drop.record, 20.5),
		"startup does not block giant routes"
	)
	assertTrue(
		DefensivePropState.BlocksGiantMacroRoutes(DefensivePropConfig, drop.record, 22),
		"active phase blocks giant routes"
	)
end

do
	local record = newRecord()
	local drop = DefensivePropState.CreateDrop(DefensivePropConfig, record, 4201, 30)
	local repeated = DefensivePropState.CreateDrop(DefensivePropConfig, drop.record, 4201, 30.5)
	assertFalse(repeated.accepted, "startup drop cannot be refreshed immediately")
	assertEqual(repeated.reason, "prop_not_ready", "repeated drop reason")
end

do
	local record = newRecord()
	local drop = DefensivePropState.CreateDrop(DefensivePropConfig, record, 4201, 40)
	local startBreak = DefensivePropState.StartBreak(DefensivePropConfig, drop.record, 9001, 41)
	assertTrue(startBreak.accepted, "giant can start break during active phase")
	assertTrue(startBreak.snapshot.breakInProgress, "break marks in-progress window")
	local earlyComplete = DefensivePropState.CompleteBreak(DefensivePropConfig, startBreak.record, 9001, 41.5)
	assertFalse(earlyComplete.accepted, "early break completion rejects")
	assertEqual(earlyComplete.reason, "break_in_progress", "early break reason")
	local complete = DefensivePropState.CompleteBreak(DefensivePropConfig, startBreak.record, 9001, 43)
	assertTrue(complete.accepted, "completed break accepts")
	assertEqual(complete.snapshot.state, "Broken", "completed break enters Broken")
end

do
	local record = newRecord()
	assertFalse(
		select(1, DefensivePropState.CanApplyBarrierContact(DefensivePropConfig, record, 10, nil)),
		"ready prop rejects barrier contact"
	)

	local drop = DefensivePropState.CreateDrop(DefensivePropConfig, record, 4201, 100)
	assertFalse(
		select(1, DefensivePropState.CanApplyBarrierContact(DefensivePropConfig, drop.record, 100.5, nil)),
		"startup phase rejects barrier contact"
	)
	assertTrue(
		select(1, DefensivePropState.CanApplyBarrierContact(DefensivePropConfig, drop.record, 102, nil)),
		"blocked phase accepts barrier contact"
	)

	local stagger = DefensivePropState.ApplyBarrierContact(DefensivePropConfig, drop.record, 102, nil)
	assertTrue(stagger.accepted, "barrier contact stagger accepts during blocked phase")
	assertEqual(stagger.reason, "barrier_contact_stagger", "stagger reason without break")
	assertEqual(stagger.staggerSeconds, 0.75, "stagger duration from config")

	local cooldown = DefensivePropState.ApplyBarrierContact(DefensivePropConfig, drop.record, 102.5, 102)
	assertFalse(cooldown.accepted, "barrier contact respects cooldown")
	assertEqual(cooldown.reason, "barrier_contact_cooldown", "cooldown reason")

	local breakDrop = DefensivePropState.CreateDrop(DefensivePropConfig, newRecord(), 4201, 110)
	local breakStart = DefensivePropState.StartBreak(DefensivePropConfig, breakDrop.record, 9001, 112)
	assertTrue(breakStart.accepted, "break start for interruption test")
	local interrupted = DefensivePropState.ApplyBarrierContact(DefensivePropConfig, breakStart.record, 112.5, nil)
	assertTrue(interrupted.accepted, "barrier contact accepts during break")
	assertTrue(interrupted.breakInterrupted, "barrier contact interrupts break")
	assertEqual(interrupted.reason, "barrier_contact_break_interrupted", "break interruption reason")
	assertFalse(interrupted.snapshot.breakInProgress, "break progress cleared after interruption")
end

do
	local record = newRecord()
	record.enabled = false
	assertEqual(
		DefensivePropState.ResolveStatus(DefensivePropConfig, record, 10),
		"Disabled",
		"disabled prop resolves Disabled"
	)
end

do
	local record = newRecord()
	local drop = DefensivePropState.CreateDrop(DefensivePropConfig, record, 4201, 50)
	local resolved, changed = DefensivePropState.ResolveLifecycle(DefensivePropConfig, drop.record, 63)
	assertTrue(changed, "expired obstacle triggers lifecycle transition")
	assertEqual(
		DefensivePropState.ResolveStatus(DefensivePropConfig, resolved, 63),
		"Resetting",
		"expired obstacle enters Resetting"
	)
end

print("defensive_prop_state: all checks passed")
