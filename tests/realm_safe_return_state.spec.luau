--!strict

local PlayerLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
local RealmSafeReturnState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmSafeReturnState")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local Location = PlayerLocationState.Location
local Operations = PlayerLocationState.Operations
local ReturnTrigger = RealmSafeReturnState.ReturnTrigger
local ReturnPath = RealmSafeReturnState.ReturnPath

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

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
	local plan = RealmSafeReturnState.ResolveReturnPlan({
		trigger = ReturnTrigger.Logout,
		locationSnapshot = realmGuest(9001, 1),
		isOnline = false,
	})
	assertTrue(plan.accepted == true, "logout plan accepted")
	assertEqual(plan.returnPath, ReturnPath.ResolveDisconnect, "logout uses resolve disconnect")
	assertTrue(plan.persistSafeLocation == true, "logout persists safe location")
	assertEqual(plan.profileReturnReason, "logout", "logout profile reason")
end

do
	local escaping = {
		location = Location.Escaping,
		realmId = RealmTransferState.FormatRealmId(9001),
		realmOwnerUserId = 9001,
		transitReason = nil,
		resumeLocation = Location.Captured,
		updatedAt = 2,
	}
	local plan = RealmSafeReturnState.ResolveReturnPlan({
		trigger = ReturnTrigger.Escape,
		locationSnapshot = escaping,
		isOnline = true,
	})
	assertTrue(plan.accepted == true, "escape plan accepted")
	assertEqual(plan.returnPath, ReturnPath.OnlineHub, "escape online hub path")
	assertEqual(plan.locationOperations[1].operation, Operations.EscapeSucceeded, "escape succeeded op")
end

do
	local captured = {
		location = Location.Captured,
		realmId = RealmTransferState.FormatRealmId(9001),
		realmOwnerUserId = 9001,
		transitReason = nil,
		resumeLocation = nil,
		updatedAt = 3,
	}
	local onlinePlan = RealmSafeReturnState.ResolveReturnPlan({
		trigger = ReturnTrigger.Timeout,
		locationSnapshot = captured,
		isOnline = true,
	})
	assertTrue(onlinePlan.accepted == true, "timeout online plan accepted")
	assertEqual(onlinePlan.returnPath, ReturnPath.OnlineCaptivitySafeReturn, "timeout captivity path")
	assertTrue(onlinePlan.applyOnlineCaptivitySafeReturn == true, "timeout applies captivity safe return")

	local offlinePlan = RealmSafeReturnState.ResolveReturnPlan({
		trigger = ReturnTrigger.Timeout,
		locationSnapshot = captured,
		isOnline = false,
	})
	assertTrue(offlinePlan.persistSafeLocation == true, "timeout offline persists")
end

do
	local plan = RealmSafeReturnState.ResolveReturnPlan({
		trigger = ReturnTrigger.ServerShutdown,
		locationSnapshot = realmGuest(9001, 4),
		isOnline = false,
	})
	assertTrue(plan.accepted == true, "server shutdown plan accepted")
	assertEqual(plan.returnPath, ReturnPath.PersistPending, "server shutdown persist pending")
	assertTrue(plan.persistSafeLocation == true, "server shutdown persists profile")
end

do
	local joinPlan = RealmSafeReturnState.ResolveJoinPlan({
		locationSnapshot = {
			location = Location.ReturnPending,
			realmId = RealmTransferState.FormatRealmId(9001),
			realmOwnerUserId = 9001,
			transitReason = nil,
			resumeLocation = nil,
			updatedAt = 5,
		},
	})
	assertTrue(joinPlan.accepted == true, "join return pending accepted")
	assertEqual(joinPlan.locationOperations[1].operation, Operations.ResolveHub, "join resolves hub")
	assertTrue(joinPlan.abortAssignment == true, "join aborts assignment")
end

do
	local joinPlan = RealmSafeReturnState.ResolveJoinPlan({
		hasSafeLocation = true,
		locationSnapshot = PlayerLocationState.NewSharedHub(6),
	})
	assertTrue(joinPlan.requiresSafeLocationSpawn == true, "join safe location spawn required")
	assertEqual(#joinPlan.locationOperations, 0, "join hub safe location skips resolve hub")
end

do
	assertTrue(
		RealmSafeReturnState.ShouldReturnVisitorsForGiantDisconnect(realmGuest(9001, 7), 9001),
		"giant disconnect returns guest visitor"
	)
	assertTrue(
		RealmSafeReturnState.ShouldReturnVisitorsForGiantDisconnect(realmGuest(9002, 8), 9001) == false,
		"giant disconnect ignores other realm"
	)
end

print("realm_safe_return_state: all checks passed")
