--!nocheck

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

ProfilePersistenceGateway.ResetForTests()
RealmTransferAssignmentService.ResetForTests()

local loadedProfileByUserId: { [number]: any } = {}
local saveAttemptCountByUserId: { [number]: number } = {}

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
	local userId = player.UserId
	local currentData = loadedProfileByUserId[userId] or {
		userId = userId,
	}
	local ok, newData, reason = pcall(updater, cloneTable(currentData))
	if not ok or type(newData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = if type(reason) == "string" then reason else "profile_update_failed",
		}
	end
	loadedProfileByUserId[userId] = cloneTable(newData)
	return {
		ok = true,
		operation = "UpdateLoadedPlayerProfileData",
		data = cloneTable(newData),
	}
end

ProfilePersistenceGateway.GetLoadedPlayerProfileData = function(player: any): any
	local userId = player.UserId
	local data = loadedProfileByUserId[userId]
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

ProfilePersistenceGateway.SavePlayerProfile = function(player: any): any
	saveAttemptCountByUserId[player.UserId] = (saveAttemptCountByUserId[player.UserId] or 0) + 1
	return {
		ok = true,
		operation = "SavePlayerProfile",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
	}
end

local userId = 8801
loadedProfileByUserId[userId] = {
	schemaVersion = 1,
	userId = userId,
}

local hydrateResult = RealmTransferAssignmentService.HydrateFromProfile(userId)
assertTrue(hydrateResult.accepted == true, "hydrate accepted")
assertEqual(
	hydrateResult.assignment.locationCategory,
	RealmAssignmentProfileState.LocationCategory.SharedHub,
	"hydrate defaults shared hub"
)

local captureResult = RealmTransferAssignmentService.ApplyTransition(userId, {
	operation = RealmTransferState.Operations.BeginCapture,
	now = 100,
	realmOwnerUserId = 9001,
})
assertTrue(captureResult.accepted == true, "runtime begin capture accepted")
assertEqual(
	captureResult.assignment.locationCategory,
	RealmAssignmentProfileState.LocationCategory.TransferInFlight,
	"runtime capture in flight"
)
assertTrue(RealmAssignmentProfileState.HasPersistedState(loadedProfileByUserId[userId]), "capture persisted")

local confirmResult = RealmTransferAssignmentService.ApplyTransition(userId, {
	operation = RealmTransferState.Operations.ConfirmArrival,
	now = 101,
	realmOwnerUserId = 9001,
})
assertTrue(confirmResult.accepted == true, "runtime confirm arrival accepted")
assertEqual(confirmResult.assignment.realmOwnerUserId, 9001, "runtime arrived owner")

local snapshotResult = RealmTransferAssignmentService.GetAssignmentSnapshot(userId)
assertTrue(snapshotResult.accepted == true, "snapshot accepted")
assertEqual(snapshotResult.assignment.realmId, "giant_realm_9001", "snapshot realm id")

local diagnostics = RealmTransferAssignmentService.GetDiagnostics()
assertTrue(diagnostics.totalTransitions >= 2, "diagnostics track transitions")
assertEqual(diagnostics.lastOperation, RealmTransferState.Operations.ConfirmArrival, "diagnostics last operation")
assertEqual(diagnostics.lastUserId, userId, "diagnostics last user id")
assertTrue(saveAttemptCountByUserId[userId] >= 2, "profile saves on transitions")

print("realm_transfer_assignment_service_runtime_entrypoint: all checks passed")
