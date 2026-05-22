--!nocheck
local RescueContractState = require("../src/ReplicatedStorage/Shared/GiantRealm/RescueContractState")

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

local function makeRequestInput(overrides: any?): any
	local input = {
		now = 100,
		rescuerUserId = 1,
		targetUserId = 2,
		rescuerRole = "Tinyfolk",
		targetRole = "Tinyfolk",
		rescuerAlive = true,
		targetDowned = true,
		targetCarried = false,
		targetProtected = false,
		inRange = true,
		targetRealmOwnerUserId = 9001,
		entryRouteId = "RescueEntryRoute_A",
		entryRouteKind = "RescueEntry",
		rescueWindowSeconds = 12,
	}

	if overrides ~= nil then
		for key, value in overrides do
			input[key] = value
		end
	end

	return input
end

do
	local state = RescueContractState.NewState()
	local rejected = RescueContractState.ResolveRequest(state, makeRequestInput({ rescuerRole = "Giant" }))

	assertFalse(rejected.accepted, "rescuer role gate rejects non-tinyfolk")
	assertEqual(rejected.reason, "rescuer_not_tinyfolk", "rescuer role rejection reason")
end

do
	local state = RescueContractState.NewState()
	local rejected = RescueContractState.ResolveRequest(state, makeRequestInput({ targetDowned = false }))

	assertFalse(rejected.accepted, "target must be downed")
	assertEqual(rejected.reason, "target_not_downed", "target downed rejection reason")
end

do
	local state = RescueContractState.NewState()
	local targetRoleRejected = RescueContractState.ResolveRequest(state, makeRequestInput({ targetRole = "Giant" }))
	assertFalse(targetRoleRejected.accepted, "target role gate rejects non-tinyfolk")
	assertEqual(targetRoleRejected.reason, "target_not_tinyfolk", "target role rejection reason")

	local rescuerAliveRejected = RescueContractState.ResolveRequest(state, makeRequestInput({ rescuerAlive = false }))
	assertFalse(rescuerAliveRejected.accepted, "rescuer must be alive")
	assertEqual(rescuerAliveRejected.reason, "rescuer_not_alive", "rescuer alive rejection reason")
end

do
	local state = RescueContractState.NewState()
	local carried = RescueContractState.ResolveRequest(state, makeRequestInput({ targetCarried = true }))
	assertFalse(carried.accepted, "carried target rejected")
	assertEqual(carried.reason, "target_carried", "carried rejection reason")

	local protected = RescueContractState.ResolveRequest(state, makeRequestInput({ targetProtected = true }))
	assertFalse(protected.accepted, "protected target rejected")
	assertEqual(protected.reason, "target_safe_zone_protected", "safe-zone rejection reason")

	local outOfRange = RescueContractState.ResolveRequest(state, makeRequestInput({ inRange = false }))
	assertFalse(outOfRange.accepted, "out-of-range target rejected")
	assertEqual(outOfRange.reason, "target_out_of_range", "out-of-range rejection reason")
end

do
	local state = RescueContractState.NewState()
	local invalidRequest = RescueContractState.ResolveRequest(state, makeRequestInput({ now = -1 }))
	assertFalse(invalidRequest.accepted, "invalid request now rejected")
	assertEqual(invalidRequest.reason, "invalid_now", "invalid request now reason")

	local invalidComplete = RescueContractState.ResolveComplete(state, {
		now = -1,
		rescuerUserId = 1,
		targetUserId = 2,
	})
	assertFalse(invalidComplete.accepted, "invalid complete now rejected")
	assertEqual(invalidComplete.reason, "invalid_now", "invalid complete now reason")
end

do
	local state = RescueContractState.NewState()
	local accepted = RescueContractState.ResolveRequest(state, makeRequestInput())

	assertTrue(accepted.accepted, "valid request accepted")
	assertEqual(accepted.reason, "accepted", "accepted reason")
	assertEqual(accepted.contract.rescuerUserId, 1, "accepted contract stores rescuer")
	assertEqual(accepted.contract.targetUserId, 2, "accepted contract stores target")
	assertEqual(accepted.contract.targetRealmOwnerUserId, 9001, "accepted contract stores realm owner")
	assertEqual(accepted.contract.entryRouteId, "RescueEntryRoute_A", "accepted contract stores entry route")
	assertEqual(accepted.contract.entryRouteKind, "RescueEntry", "accepted contract stores entry route kind")

	local second = RescueContractState.ResolveRequest(accepted.state, makeRequestInput({ now = 101 }))
	assertFalse(second.accepted, "rescuer cannot hold multiple contracts")
	assertEqual(second.reason, "rescuer_contract_active", "second request rejection reason")

	local complete = RescueContractState.ResolveComplete(accepted.state, {
		now = 102,
		rescuerUserId = 1,
		targetUserId = 2,
	})
	assertTrue(complete.accepted, "complete resolves active contract")
	assertEqual(complete.reason, "rescued", "complete reason")
	assertEqual(RescueContractState.GetRescuerContract(complete.state, 1), nil, "contract removed after completion")
end

do
	local state = RescueContractState.NewState()
	local invalidRealm = RescueContractState.ResolveRequest(state, makeRequestInput({ targetRealmOwnerUserId = 0 }))
	assertFalse(invalidRealm.accepted, "invalid target realm rejects")
	assertEqual(invalidRealm.reason, "target_realm_owner_user_id_invalid", "invalid target realm rejection reason")

	local invalidRouteId = RescueContractState.ResolveRequest(state, makeRequestInput({ entryRouteId = "" }))
	assertFalse(invalidRouteId.accepted, "invalid entry route id rejects")
	assertEqual(invalidRouteId.reason, "rescue_entry_route_id_invalid", "invalid entry route id reason")

	local invalidRouteKind = RescueContractState.ResolveRequest(state, makeRequestInput({ entryRouteKind = "" }))
	assertFalse(invalidRouteKind.accepted, "invalid entry route kind rejects")
	assertEqual(invalidRouteKind.reason, "rescue_entry_route_kind_invalid", "invalid entry route kind reason")
end

do
	local state = RescueContractState.NewState()
	local accepted = RescueContractState.ResolveRequest(state, makeRequestInput({ now = 10, rescueWindowSeconds = 2 }))
	assertTrue(accepted.accepted, "short-window contract accepted")

	local afterExpiry =
		RescueContractState.ResolveRequest(accepted.state, makeRequestInput({ now = 13, targetUserId = 3 }))
	assertTrue(afterExpiry.accepted, "expired contract no longer blocks request")
	assertEqual(afterExpiry.contract.targetUserId, 3, "post-expiry request targets new user")
end

do
	local state = RescueContractState.NewState()
	local accelerated = RescueContractState.ResolveRequest(
		state,
		makeRequestInput({
			now = 20,
			rescueWindowSeconds = 12,
			accelerationActive = true,
			accelerationWindowBonusSeconds = 3,
		})
	)

	assertTrue(accelerated.accepted, "accelerated request accepted")
	assertTrue(accelerated.contract.isAccelerated == true, "accelerated contract flagged")
	assertEqual(accelerated.contract.expiresAt, 35, "accelerated request extends rescue window")
end

do
	local state = RescueContractState.NewState()
	local invalidWindow = RescueContractState.ResolveRequest(
		state,
		makeRequestInput({
			now = 40,
			rescueWindowSeconds = 0,
			accelerationActive = true,
			accelerationWindowBonusSeconds = 3,
		})
	)

	assertFalse(invalidWindow.accepted, "invalid base rescue window rejected even with acceleration")
	assertEqual(invalidWindow.reason, "rescue_window_invalid", "invalid rescue window rejection reason")
end

do
	local state = RescueContractState.NewState()
	local first = RescueContractState.ResolveRequest(state, makeRequestInput({ rescuerUserId = 1, targetUserId = 2 }))
	assertTrue(first.accepted, "first participant contract accepted")

	local rescuerAlreadyTargeted = RescueContractState.ResolveRequest(
		first.state,
		makeRequestInput({ rescuerUserId = 2, targetUserId = 3, now = 101 })
	)
	assertFalse(rescuerAlreadyTargeted.accepted, "targeted player cannot start rescue")
	assertEqual(
		rescuerAlreadyTargeted.reason,
		"participant_contract_active",
		"targeted player start-recue rejection reason"
	)

	local targetAlreadyRescuing = RescueContractState.ResolveRequest(
		first.state,
		makeRequestInput({ rescuerUserId = 3, targetUserId = 1, now = 101 })
	)
	assertFalse(targetAlreadyRescuing.accepted, "active rescuer cannot be target")
	assertEqual(targetAlreadyRescuing.reason, "participant_contract_active", "active rescuer target rejection reason")
end

print("rescue_contract_state: all checks passed")
