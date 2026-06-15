--!nocheck

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local ProfileTeleportHandoffService = require("../src/ServerScriptService/Services/ProfileTeleportHandoffService")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferAssignmentService = require("../src/ServerScriptService/Services/RealmTransferAssignmentService")
local RealmTransferHandoffService = require("../src/ServerScriptService/Services/RealmTransferHandoffService")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")
local TransferLockService = require("../src/ServerScriptService/Services/TransferLockService")
local globalEnv: any = getfenv()

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function makePlayer(userId: number): any
	return { UserId = userId, Name = "Player" .. tostring(userId) }
end

TransferLockService.ResetForTests()
RealmTransferHandoffService.ResetForTests()
ProfilePersistenceGateway.ResetForTests()
RealmTransferAssignmentService.ResetForTests()
ProfileTeleportHandoffService.ResetForTests()

local ownershipReadyByUserId: { [number]: boolean } = {}
globalEnv._ProfilePersistenceLifecycle_QueryAPI = {
	IsPlayerOwnershipReady = function(userId: number): boolean
		return ownershipReadyByUserId[userId] == true
	end,
}
globalEnv._ProfileTeleportAdmissionService_QueryAPI = {
	RequestTeleportHandoffAdmission = function(_payload: any): any
		return { accepted = true, reason = "accepted" }
	end,
}

local loadedProfileByUserId: { [number]: any } = {}
ProfilePersistenceGateway.UpdateLoadedPlayerProfileData = function(player: any, updater: any): any
	local userId = player.UserId
	local currentData = loadedProfileByUserId[userId] or { userId = userId }
	local ok, newData, reason = pcall(updater, currentData)
	if not ok or type(newData) ~= "table" then
		return { ok = false, reason = if type(reason) == "string" then reason else "profile_update_failed" }
	end
	loadedProfileByUserId[userId] = newData
	return { ok = true, data = newData }
end
ProfilePersistenceGateway.GetLoadedPlayerProfileData = function(player: any): any
	local data = loadedProfileByUserId[player.UserId]
	if type(data) ~= "table" then
		return { ok = false, reason = "player_profile_not_loaded" }
	end
	return { ok = true, data = data }
end
ProfilePersistenceGateway.SavePlayerProfile = function(_player: any): any
	return { ok = true }
end
ProfilePersistenceGateway.ReleasePlayerProfile = function(_player: any): any
	return { ok = true }
end

local userId = 7201
local realmOwnerUserId = 9201
local targetRealmId = RealmTransferState.FormatRealmId(realmOwnerUserId)
loadedProfileByUserId[userId] = { userId = userId, schemaVersion = 1 }
ownershipReadyByUserId[userId] = true

local handoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(userId), {
	flow = "hub_to_realm",
	targetRealmId = targetRealmId,
	realmOwnerUserId = realmOwnerUserId,
	assignmentReason = RealmAssignmentProfileState.AssignmentReason.Rescue,
})
assertTrue(handoff.ok == true, "pipeline begin accepted")
assertTrue(type(handoff.handoffToken) == "string", "pipeline begin token")

local inFlightAssignment = RealmAssignmentProfileState.GetAssignment(loadedProfileByUserId[userId])
assertEqual(inFlightAssignment.locationCategory, "transfer_in_flight", "assignment in flight after begin")
assertEqual(inFlightAssignment.assignmentReason, "rescue", "assignment rescue reason")

local sessionResult = RealmTransferHandoffService.GetSessionRecord(targetRealmId)
assertTrue(sessionResult.accepted == true, "pipeline session record")

local confirm = ProfileTeleportHandoffService.ConfirmDestinationOwnership(userId, handoff.handoffToken)
assertTrue(confirm.ok == true, "pipeline confirm accepted")

local arrivedAssignment = RealmAssignmentProfileState.GetAssignment(loadedProfileByUserId[userId])
assertEqual(arrivedAssignment.locationCategory, "giant_realm", "assignment giant realm after confirm")

print("profile_teleport_handoff_orchestration_runtime_entrypoint: all checks passed")
