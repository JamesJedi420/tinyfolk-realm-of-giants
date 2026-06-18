--!strict

local PlayerLocationAssignmentSync = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationAssignmentSync")
local PlayerLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local LocationOps = PlayerLocationState.Operations
local TransitReason = PlayerLocationState.TransitReason
local TransferOps = RealmTransferState.Operations

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

do
	assertEqual(
		PlayerLocationAssignmentSync.ResolveBeginAssignmentOperation(TransitReason.Capture),
		TransferOps.BeginCapture,
		"capture transit maps to begin_capture"
	)
	assertEqual(
		PlayerLocationAssignmentSync.ResolveBeginAssignmentOperation(TransitReason.PartyAdmission),
		TransferOps.BeginPartyAdmission,
		"party transit maps to begin_party_admission"
	)
	assertEqual(
		PlayerLocationAssignmentSync.ResolveAssignmentOperationForLocationOperation(LocationOps.Capture, nil),
		nil,
		"capture location op does not sync assignment"
	)
	assertEqual(
		PlayerLocationAssignmentSync.ResolveAssignmentOperationForLocationOperation(LocationOps.BeginTransit, {
			transitReason = TransitReason.Rescue,
		}),
		TransferOps.BeginRescue,
		"begin transit syncs rescue assignment"
	)
	assertEqual(
		PlayerLocationAssignmentSync.ResolveAssignmentOperationForLocationOperation(LocationOps.EscapeSucceeded, nil),
		TransferOps.SetSharedHub,
		"escape succeeded clears assignment"
	)
	assertEqual(
		PlayerLocationAssignmentSync.ResolveLocationOperationForAssignmentOperation(TransferOps.BeginCapture, nil).operation,
		LocationOps.BeginTransit,
		"begin capture syncs location transit"
	)
	assertEqual(
		PlayerLocationAssignmentSync.ResolveLocationOperationForAssignmentOperation(
			TransferOps.ConfirmArrival,
			{ assignmentReason = RealmAssignmentProfileState.AssignmentReason.Capture }
		).operation,
		LocationOps.ConfirmCaptured,
		"confirm arrival capture syncs confirm captured"
	)
end

do
	local locationSnapshot = {
		location = PlayerLocationState.Location.Transit,
		realmId = RealmTransferState.FormatRealmId(9001),
		realmOwnerUserId = 9001,
		transitReason = TransitReason.PartyAdmission,
	}
	local assignmentSnapshot = {
		locationCategory = RealmAssignmentProfileState.LocationCategory.TransferInFlight,
		realmId = RealmTransferState.FormatRealmId(9001),
		realmOwnerUserId = 9001,
		assignmentReason = RealmAssignmentProfileState.AssignmentReason.PartyAdmission,
	}
	assertEqual(
		PlayerLocationAssignmentSync.IsMatchingTransitPair(
			locationSnapshot,
			assignmentSnapshot,
			RealmTransferState.FormatRealmId(9001),
			TransitReason.PartyAdmission
		),
		true,
		"matching transit pair accepted"
	)
end

print("player_location_assignment_sync: all checks passed")
