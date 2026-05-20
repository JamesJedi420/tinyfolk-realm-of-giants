--!strict

local TransportEscapeState = require("../src/ReplicatedStorage/Shared/GiantRealm/TransportEscapeState")

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
	local state = TransportEscapeState.NewState({
		EndpointId = "TransportEndpoint_Main",
		Capacity = 2,
		StartupDurationSeconds = 4,
		LaunchDurationSeconds = 2,
		MaxStartupInterruptions = 1,
	})

	local registerFuel = TransportEscapeState.RegisterRequiredComponent(state, "Fuel")
	assertTrue(registerFuel.accepted, "register fuel accepted")
	assertEqual(
		registerFuel.state.phase,
		TransportEscapeState.EndpointPhases.Assembling,
		"phase assembling after first required"
	)

	local registerWheel = TransportEscapeState.RegisterRequiredComponent(registerFuel.state, "Wheel")
	assertTrue(registerWheel.accepted, "register wheel accepted")

	local heldFuel = TransportEscapeState.SetComponentHeld(registerWheel.state, "Fuel", 101, 10)
	assertTrue(heldFuel.accepted, "set fuel held accepted")
	assertEqual(
		heldFuel.state.componentsById.Fuel.state,
		TransportEscapeState.ComponentStates.Held,
		"fuel enters held state"
	)

	local droppedFuel = TransportEscapeState.SetComponentDropped(heldFuel.state, "Fuel", 11)
	assertTrue(droppedFuel.accepted, "set fuel dropped accepted")
	assertEqual(
		droppedFuel.state.componentsById.Fuel.state,
		TransportEscapeState.ComponentStates.Dropped,
		"fuel enters dropped state"
	)

	local lostFuel = TransportEscapeState.SetComponentLost(droppedFuel.state, "Fuel", 12)
	assertTrue(lostFuel.accepted, "set fuel lost accepted")
	assertEqual(
		lostFuel.state.componentsById.Fuel.state,
		TransportEscapeState.ComponentStates.Lost,
		"fuel enters lost state"
	)

	local recoveredFuel = TransportEscapeState.SetComponentRecovered(lostFuel.state, "Fuel", 102, 13)
	assertTrue(recoveredFuel.accepted, "set fuel recovered accepted")
	assertEqual(
		recoveredFuel.state.componentsById.Fuel.state,
		TransportEscapeState.ComponentStates.Recovered,
		"fuel enters recovered state"
	)

	local blockedWheel = TransportEscapeState.SetComponentBlocked(recoveredFuel.state, "Wheel", 14)
	assertTrue(blockedWheel.accepted, "set wheel blocked accepted")
	assertEqual(
		blockedWheel.state.componentsById.Wheel.state,
		TransportEscapeState.ComponentStates.Blocked,
		"wheel enters blocked state"
	)

	local deliveredFuel = TransportEscapeState.SetComponentDelivered(blockedWheel.state, "Fuel", 102, 15)
	assertTrue(deliveredFuel.accepted, "set fuel delivered accepted")
	assertEqual(
		deliveredFuel.state.componentsById.Fuel.state,
		TransportEscapeState.ComponentStates.Delivered,
		"fuel enters delivered state"
	)
	assertEqual(
		deliveredFuel.state.phase,
		TransportEscapeState.EndpointPhases.Assembling,
		"single component does not assemble"
	)

	local installedWheel = TransportEscapeState.SetComponentInstalled(deliveredFuel.state, "Wheel", 103, 16)
	assertTrue(installedWheel.accepted, "set wheel installed accepted")
	assertEqual(
		installedWheel.state.phase,
		TransportEscapeState.EndpointPhases.Assembled,
		"all required components assemble"
	)

	local boardOperator = TransportEscapeState.BoardPassenger(installedWheel.state, 101, { asOperator = true })
	assertTrue(boardOperator.accepted, "operator board accepted")
	assertEqual(boardOperator.state.phase, TransportEscapeState.EndpointPhases.Boarding, "phase switches to boarding")
	assertEqual(boardOperator.state.operatorUserId, 101, "operator assigned")

	local boardPassenger = TransportEscapeState.BoardPassenger(boardOperator.state, 102, nil)
	assertTrue(boardPassenger.accepted, "passenger board accepted")
	assertEqual(boardPassenger.state.boardedByUserId[102], true, "passenger tracked as boarded")

	local overCapacity = TransportEscapeState.BoardPassenger(boardPassenger.state, 103, nil)
	assertFalse(overCapacity.accepted, "over-capacity board rejected")
	assertEqual(overCapacity.reason, "transport_full", "over-capacity reason")

	local startup = TransportEscapeState.StartStartup(boardPassenger.state, 101, 20)
	assertTrue(startup.accepted, "startup accepted")
	assertEqual(startup.state.phase, TransportEscapeState.EndpointPhases.Startup, "phase startup")
	assertEqual(startup.state.startupEndsAt, 24, "startup end timestamp deterministic")

	local interrupted = TransportEscapeState.InterruptStartup(startup.state, 21)
	assertTrue(interrupted.accepted, "startup interruption accepted")
	assertEqual(
		interrupted.state.phase,
		TransportEscapeState.EndpointPhases.Boarding,
		"interruption returns to boarding"
	)
	assertEqual(interrupted.state.startupInterruptionsUsed, 1, "interrupt count increments")

	local restart = TransportEscapeState.StartStartup(interrupted.state, 101, 30)
	assertTrue(restart.accepted, "startup restart accepted")

	local interruptLimit = TransportEscapeState.InterruptStartup(restart.state, 31)
	assertFalse(interruptLimit.accepted, "second interruption rejected by bound")
	assertEqual(interruptLimit.reason, "interrupt_limit_reached", "bounded interruption reason")

	local launchStarted = TransportEscapeState.ResolveTime(restart.state, 34)
	assertTrue(launchStarted.accepted, "resolve startup->launch accepted")
	assertEqual(launchStarted.reason, "launch_started", "launch transition reason")
	assertEqual(launchStarted.state.phase, TransportEscapeState.EndpointPhases.Launched, "phase launched")
	assertEqual(launchStarted.state.launchEndsAt, 36, "launch end timestamp deterministic")

	local departed = TransportEscapeState.ResolveTime(launchStarted.state, 36)
	assertTrue(departed.accepted, "resolve launch->departed accepted")
	assertEqual(departed.reason, "departed", "departure transition reason")
	assertEqual(departed.state.phase, TransportEscapeState.EndpointPhases.Departed, "phase departed")

	local departureOutcome = TransportEscapeState.ResolveDepartureOutcome(departed.state, { 101, 102, 103, 104 })
	assertTrue(departureOutcome.canResolve, "departure outcome can resolve in departed phase")
	assertEqual(#departureOutcome.boardedEscapedUserIds, 2, "boarded escaped count")
	assertEqual(departureOutcome.boardedEscapedUserIds[1], 101, "operator escaped")
	assertEqual(departureOutcome.boardedEscapedUserIds[2], 102, "passenger escaped")
	assertEqual(#departureOutcome.unboardedRemainingUserIds, 2, "unboarded remain count")
	assertEqual(departureOutcome.unboardedRemainingUserIds[1], 103, "unboarded remains includes 103")
	assertEqual(departureOutcome.unboardedRemainingUserIds[2], 104, "unboarded remains includes 104")
end

print("transport_escape_state: all checks passed")
