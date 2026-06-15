--!strict

local PendingRecoveryProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/PendingRecoveryProfileState")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

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

local sharedHub = RealmTransferState.NewSharedHubAssignment(0)

local function giantRealm(ownerUserId: number, updatedAt: number)
	return {
		locationCategory = RealmAssignmentProfileState.LocationCategory.GiantRealm,
		realmId = RealmTransferState.FormatRealmId(ownerUserId),
		realmOwnerUserId = ownerUserId,
		assignmentReason = nil,
		updatedAt = updatedAt,
	}
end

do
	assertEqual(RealmTransferState.FormatRealmId(9001), "giant_realm_9001", "format realm id")
	assertEqual(RealmTransferState.ParseRealmOwnerUserId("giant_realm_9001"), 9001, "parse realm owner")
	assertTrue(RealmTransferState.ParseRealmOwnerUserId("realm-main-01") == nil, "reject non canonical realm id")
end

do
	local captureBegin = RealmTransferState.ResolveTransition(sharedHub, {
		operation = RealmTransferState.Operations.BeginCapture,
		now = 10,
		realmOwnerUserId = 9001,
	})
	assertTrue(captureBegin.accepted == true, "begin capture accepted")
	assertEqual(
		captureBegin.assignment.locationCategory,
		RealmAssignmentProfileState.LocationCategory.TransferInFlight,
		"capture in flight"
	)
	assertEqual(
		captureBegin.assignment.assignmentReason,
		RealmAssignmentProfileState.AssignmentReason.Capture,
		"capture reason"
	)

	local captureConfirm = RealmTransferState.ResolveTransition(captureBegin.assignment, {
		operation = RealmTransferState.Operations.ConfirmArrival,
		now = 11,
		realmOwnerUserId = 9001,
	})
	assertTrue(captureConfirm.accepted == true, "confirm capture arrival accepted")
	assertEqual(
		captureConfirm.assignment.locationCategory,
		RealmAssignmentProfileState.LocationCategory.GiantRealm,
		"capture arrived giant realm"
	)
end

do
	local realm = giantRealm(9001, 20)
	local escapeBegin = RealmTransferState.ResolveTransition(realm, {
		operation = RealmTransferState.Operations.BeginEscapeReturn,
		now = 21,
		realmOwnerUserId = 9001,
	})
	assertTrue(escapeBegin.accepted == true, "begin escape accepted")

	local escapeConfirm = RealmTransferState.ResolveTransition(escapeBegin.assignment, {
		operation = RealmTransferState.Operations.ConfirmHubReturn,
		now = 22,
	})
	assertTrue(escapeConfirm.accepted == true, "confirm hub return accepted")
	assertEqual(
		escapeConfirm.assignment.locationCategory,
		RealmAssignmentProfileState.LocationCategory.SharedHub,
		"escape returned to hub"
	)
end

do
	local sourceRealm = giantRealm(9001, 30)
	local tradeBegin = RealmTransferState.ResolveTransition(sourceRealm, {
		operation = RealmTransferState.Operations.BeginTrade,
		now = 31,
		realmOwnerUserId = 9002,
	})
	assertTrue(tradeBegin.accepted == true, "begin trade accepted")
	assertEqual(
		tradeBegin.assignment.assignmentReason,
		RealmAssignmentProfileState.AssignmentReason.Trade,
		"trade reason"
	)

	local tradeConfirm = RealmTransferState.ResolveTransition(tradeBegin.assignment, {
		operation = RealmTransferState.Operations.ConfirmArrival,
		now = 32,
		realmOwnerUserId = 9002,
	})
	assertTrue(tradeConfirm.accepted == true, "confirm trade arrival accepted")
	assertEqual(tradeConfirm.assignment.realmOwnerUserId, 9002, "trade destination owner")
end

do
	local duplicate = RealmTransferState.ResolveTransition(sharedHub, {
		operation = RealmTransferState.Operations.BeginCapture,
		now = 10,
		realmOwnerUserId = 9001,
	})
	local blocked = RealmTransferState.ResolveTransition(duplicate.assignment, {
		operation = RealmTransferState.Operations.BeginRescue,
		now = 10.5,
		realmOwnerUserId = 9002,
	})
	assertFalse(blocked.accepted == true, "duplicate in flight rejected")
	assertEqual(blocked.reason, "transfer_already_in_flight", "duplicate in flight reason")
end

do
	local sameRealmTrade = RealmTransferState.ResolveTransition(giantRealm(9001, 40), {
		operation = RealmTransferState.Operations.BeginTrade,
		now = 41,
		realmOwnerUserId = 9001,
	})
	assertFalse(sameRealmTrade.accepted == true, "trade to same realm rejected")
	assertEqual(sameRealmTrade.reason, "begin_trade_target_must_differ", "same realm trade reason")
end

do
	local profileData = {
		realmAssignment = {
			locationCategory = RealmAssignmentProfileState.LocationCategory.GiantRealm,
			realmId = "giant_realm_9100",
			realmOwnerUserId = 9100,
			updatedAt = 1,
		},
	}
	assertEqual(
		RealmTransferState.DeriveEffectiveLocationCategory({
			profileData = profileData,
		}),
		RealmAssignmentProfileState.LocationCategory.GiantRealm,
		"derive from persisted assignment"
	)
end

do
	local legacyProfile = {
		pendingRecovery = {
			handoffToken = "handoff:1:1",
			targetRealmId = "giant_realm_9200",
			startedAt = 5,
			status = PendingRecoveryProfileState.Status.AwaitingDestination,
		},
	}
	assertEqual(
		RealmTransferState.DeriveEffectiveLocationCategory({
			profileData = legacyProfile,
		}),
		RealmAssignmentProfileState.LocationCategory.TransferInFlight,
		"derive legacy pending recovery"
	)
end

print("realm_transfer_state: all checks passed")
