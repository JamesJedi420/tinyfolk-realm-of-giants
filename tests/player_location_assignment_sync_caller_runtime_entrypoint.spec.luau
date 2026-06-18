--!nocheck

local PlayerLocationService = require("../src/ServerScriptService/Services/PlayerLocationService")
local PlayerLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
local PlayerLocationAssignmentSyncCaller =
	require("../src/ServerScriptService/Services/PlayerLocationAssignmentSyncCaller")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferAssignmentService = require("../src/ServerScriptService/Services/RealmTransferAssignmentService")
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

PlayerLocationService.ResetForTests()
RealmTransferAssignmentService.ResetForTests()
ProfilePersistenceGateway.ResetForTests()
PlayerLocationAssignmentSyncCaller.ResetForTests()

local loadedProfileByUserId: { [number]: any } = {}

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copied = {}
	for key, child in pairs(value) do
		copied[key] = cloneTable(child)
	end
	return copied
end

ProfilePersistenceGateway.UpdateLoadedPlayerProfileData = function(player: any, updater: any): any
	local profileUserId = player.UserId
	local currentData = loadedProfileByUserId[profileUserId] or {
		userId = profileUserId,
	}
	local ok, newData, reason = pcall(updater, cloneTable(currentData))
	if not ok or type(newData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = if type(reason) == "string" then reason else "profile_update_failed",
		}
	end
	loadedProfileByUserId[profileUserId] = cloneTable(newData)
	return {
		ok = true,
		operation = "UpdateLoadedPlayerProfileData",
		data = cloneTable(newData),
	}
end

ProfilePersistenceGateway.GetLoadedPlayerProfileData = function(player: any): any
	local profileUserId = player.UserId
	local data = loadedProfileByUserId[profileUserId]
	if type(data) ~= "table" then
		return {
			ok = false,
			operation = "GetLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
		}
	end
	return {
		ok = true,
		operation = "GetLoadedPlayerProfileData",
		data = cloneTable(data),
	}
end

ProfilePersistenceGateway.SavePlayerProfile = function(_player: any): any
	return {
		ok = true,
		operation = "SavePlayerProfile",
	}
end

local userId = 8810
loadedProfileByUserId[userId] = {
	schemaVersion = 1,
	userId = userId,
}

local realmOwnerUserId = 9100
local realmId = RealmTransferState.FormatRealmId(realmOwnerUserId)

local beginResult = PlayerLocationAssignmentSyncCaller.ApplyLocationWithAssignmentSync(userId, {
	operation = PlayerLocationState.Operations.BeginTransit,
	now = 10,
	realmOwnerUserId = realmOwnerUserId,
	realmId = realmId,
	transitReason = PlayerLocationState.TransitReason.PartyAdmission,
})
assertTrue(beginResult.accepted == true, "coupled begin transit accepted")
assertEqual(beginResult.snapshot.location, PlayerLocationState.Location.Transit, "location in transit")

local assignmentSnapshot = RealmTransferAssignmentService.GetAssignmentSnapshot(userId)
assertTrue(assignmentSnapshot.accepted == true, "assignment snapshot accepted")
assertEqual(
	assignmentSnapshot.assignment.locationCategory,
	RealmAssignmentProfileState.LocationCategory.TransferInFlight,
	"assignment transfer in flight"
)

local confirmResult = PlayerLocationAssignmentSyncCaller.ApplyCoupledConfirmForArrival(userId, {
	targetRealmId = realmId,
	realmOwnerUserId = realmOwnerUserId,
	assignmentReason = RealmAssignmentProfileState.AssignmentReason.PartyAdmission,
	confirmOperation = PlayerLocationState.Operations.ConfirmRealmGuest,
	now = 11,
})
assertTrue(confirmResult.accepted == true, "coupled confirm accepted")
assertEqual(confirmResult.snapshot.location, PlayerLocationState.Location.RealmGuest, "location realm guest")

assignmentSnapshot = RealmTransferAssignmentService.GetAssignmentSnapshot(userId)
assertEqual(
	assignmentSnapshot.assignment.locationCategory,
	RealmAssignmentProfileState.LocationCategory.GiantRealm,
	"assignment giant realm after confirm"
)

local captureResult = PlayerLocationAssignmentSyncCaller.ApplyLocationWithAssignmentSync(userId, {
	operation = PlayerLocationState.Operations.Capture,
	now = 12,
})
assertTrue(captureResult.accepted == true, "capture without assignment mutation accepted")
assignmentSnapshot = RealmTransferAssignmentService.GetAssignmentSnapshot(userId)
assertEqual(
	assignmentSnapshot.assignment.locationCategory,
	RealmAssignmentProfileState.LocationCategory.GiantRealm,
	"assignment unchanged after capture"
)

print("player_location_assignment_sync_caller_runtime_entrypoint: all checks passed")
