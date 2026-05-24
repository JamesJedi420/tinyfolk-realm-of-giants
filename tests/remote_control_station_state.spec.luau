--!nocheck

local RemoteControlStationConfig = require("../src/ReplicatedStorage/Shared/Config/RemoteControlStationConfig")
local RemoteControlStationState = require("../src/ReplicatedStorage/Shared/GiantRealm/RemoteControlStationState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

do
	local state = RemoteControlStationState.NewStation(
		RemoteControlStationConfig,
		"GiantControlStation_A",
		"GiantControlZone_A",
		100
	)
	assertEqual(state.energy, 3, "new station starts with configured energy")

	local invalid = RemoteControlStationState.CreateBarrier(RemoteControlStationConfig, state, {
		routeId = "EscapeRoute_A",
		createdByUserId = 1,
		now = 100,
	})
	assertFalse(invalid.accepted, "inactive operator cannot create barrier")
	assertEqual(invalid.reason, "operator_not_active", "inactive operator rejection reason")

	local enter = RemoteControlStationState.Enter(state, 1, 100)
	assertTrue(enter.accepted, "operator can enter station")

	local first = RemoteControlStationState.CreateBarrier(RemoteControlStationConfig, state, {
		routeId = "EscapeRoute_A",
		createdByUserId = 1,
		now = 100,
	})
	assertTrue(first.accepted, "active operator can create barrier")
	assertEqual(state.energy, 2, "barrier spends station energy")

	local warning = RemoteControlStationState.GetBarrierSnapshot(RemoteControlStationConfig, first.record, 100.5)
	assertEqual(warning.state, "Warning", "barrier starts in warning phase")

	local active = RemoteControlStationState.GetBarrierSnapshot(RemoteControlStationConfig, first.record, 101)
	assertEqual(active.state, "Active", "barrier becomes active after warning")

	local expired = RemoteControlStationState.GetBarrierSnapshot(RemoteControlStationConfig, first.record, 105)
	assertEqual(expired.state, "Expired", "barrier expires after active window")

	local repeated = RemoteControlStationState.CreateBarrier(RemoteControlStationConfig, state, {
		routeId = "EscapeRoute_A",
		createdByUserId = 1,
		now = 101,
		existingRecord = first.record,
	})
	assertFalse(repeated.accepted, "active barrier rejects repeat")
	assertEqual(repeated.reason, "remote_barrier_active", "repeat active rejection reason")
end

do
	local state = RemoteControlStationState.NewStation(
		RemoteControlStationConfig,
		"GiantControlStation_A",
		"GiantControlZone_A",
		200
	)
	RemoteControlStationState.Enter(state, 10, 200)
	state.energy = 0
	RemoteControlStationState.RecoverEnergy(RemoteControlStationConfig, state, 207.9)
	assertEqual(state.energy, 0, "energy does not recover before interval")
	RemoteControlStationState.RecoverEnergy(RemoteControlStationConfig, state, 208)
	assertEqual(state.energy, 1, "energy recovers on interval")
	RemoteControlStationState.RecoverEnergy(RemoteControlStationConfig, state, 224)
	assertEqual(state.energy, 3, "energy recovery clamps to max")

	local sabotage = RemoteControlStationState.ApplySabotage(RemoteControlStationConfig, state, 22, 225)
	assertTrue(sabotage.accepted, "sabotage accepts valid user")
	assertEqual(state.energy, 2, "sabotage drains energy")
	assertEqual(state.activeOperatorUserId, nil, "sabotage clears operator")
	assertEqual(state.lockoutEndsAt, 231, "sabotage applies lockout")

	local lockedEnter = RemoteControlStationState.Enter(state, 10, 226)
	assertFalse(lockedEnter.accepted, "lockout blocks station enter")
	assertEqual(lockedEnter.reason, "station_locked_out", "lockout enter reason")
end

print("remote_control_station_state: all checks passed")
