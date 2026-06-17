--!strict

local PlayerLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local Location = PlayerLocationState.Location
local Operations = PlayerLocationState.Operations
local TransitReason = PlayerLocationState.TransitReason

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

local hub = PlayerLocationState.NewSharedHub(0)

local function realmGuest(ownerUserId: number, updatedAt: number)
	return {
		location = Location.RealmGuest,
		realmId = RealmTransferState.FormatRealmId(ownerUserId),
		realmOwnerUserId = ownerUserId,
		transitReason = nil,
		resumeLocation = nil,
		updatedAt = updatedAt,
	}
end

do
	assertEqual(hub.location, Location.SharedHub, "default shared hub location")
	assertTrue(PlayerLocationState.IsInRealm(hub.location) == false, "hub not in realm")
end

do
	local transit = PlayerLocationState.ResolveTransition(hub, {
		operation = Operations.BeginTransit,
		now = 1,
		realmOwnerUserId = 9001,
		transitReason = TransitReason.PartyAdmission,
	})
	assertTrue(transit.accepted == true, "begin transit accepted")
	assertEqual(transit.snapshot.location, Location.Transit, "transit location")
	assertEqual(transit.snapshot.transitReason, TransitReason.PartyAdmission, "transit reason")

	local guest = PlayerLocationState.ResolveTransition(transit.snapshot, {
		operation = Operations.ConfirmRealmGuest,
		now = 2,
		realmOwnerUserId = 9001,
	})
	assertTrue(guest.accepted == true, "confirm realm guest accepted")
	assertEqual(guest.snapshot.location, Location.RealmGuest, "realm guest location")
end

do
	local guest = realmGuest(9001, 10)
	local captured = PlayerLocationState.ResolveTransition(guest, {
		operation = Operations.Capture,
		now = 11,
	})
	assertTrue(captured.accepted == true, "capture accepted")
	assertEqual(captured.snapshot.location, Location.Captured, "captured location")

	local escaping = PlayerLocationState.ResolveTransition(captured.snapshot, {
		operation = Operations.BeginEscape,
		now = 12,
	})
	assertTrue(escaping.accepted == true, "begin escape accepted")
	assertEqual(escaping.snapshot.location, Location.Escaping, "escaping location")
	assertEqual(escaping.snapshot.resumeLocation, Location.Captured, "escape resume captured")

	local returnPending = PlayerLocationState.ResolveTransition(captured.snapshot, {
		operation = Operations.SetReturnPending,
		now = 13,
	})
	assertTrue(returnPending.accepted == true, "captured to return pending accepted")
	assertEqual(returnPending.snapshot.location, Location.ReturnPending, "return pending location")
end

do
	local captured = {
		location = Location.Captured,
		realmId = RealmTransferState.FormatRealmId(9001),
		realmOwnerUserId = 9001,
		transitReason = nil,
		resumeLocation = nil,
		updatedAt = 20,
	}
	local blocked = PlayerLocationState.ResolveTransition(captured, {
		operation = Operations.ConfirmRealmGuest,
		now = 21,
		realmOwnerUserId = 9001,
	})
	assertFalse(blocked.accepted == true, "invalid transition rejected")
	assertEqual(blocked.reason, "transition_not_allowed", "invalid transition reason")
end

do
	local guest = realmGuest(9001, 30)
	local disconnected = PlayerLocationState.ResolveTransition(guest, {
		operation = Operations.MarkDisconnected,
		now = 31,
	})
	assertTrue(disconnected.accepted == true, "mark disconnected accepted")
	assertEqual(disconnected.snapshot.location, Location.DisconnectedInRealm, "disconnected location")

	local disconnectPlan = PlayerLocationState.ResolveDisconnect(disconnected.snapshot, {
		now = 32,
	})
	assertTrue(disconnectPlan.accepted == true, "disconnect plan accepted")
	assertEqual(disconnectPlan.snapshot.location, Location.ReturnPending, "disconnect resolves return pending")
	assertTrue(disconnectPlan.persistReturnPending == true, "disconnect persists return pending")

	local resolved = PlayerLocationState.ResolveTransition(disconnectPlan.snapshot, {
		operation = Operations.ResolveHub,
		now = 33,
	})
	assertTrue(resolved.accepted == true, "resolve hub accepted")
	assertEqual(resolved.snapshot.location, Location.SharedHub, "resolved to hub")
end

do
	local assignment = {
		locationCategory = RealmAssignmentProfileState.LocationCategory.TransferInFlight,
		realmId = RealmTransferState.FormatRealmId(9100),
		realmOwnerUserId = 9100,
		assignmentReason = RealmAssignmentProfileState.AssignmentReason.Capture,
		updatedAt = 5,
	}
	local derived = PlayerLocationState.DeriveFromRealmAssignment(assignment, 5)
	assertEqual(derived.location, Location.Transit, "derive transit from assignment")
	assertEqual(derived.transitReason, TransitReason.Capture, "derive capture transit reason")
end

print("player_location_state: all checks passed")
