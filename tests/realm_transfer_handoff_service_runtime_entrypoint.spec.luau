--!nocheck

local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local RealmTransferHandoffService = require("../src/ServerScriptService/Services/RealmTransferHandoffService")
local RealmTransferAssignmentService = require("../src/ServerScriptService/Services/RealmTransferAssignmentService")
local RealmTransferState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTransferState")
local TransferLockService = require("../src/ServerScriptService/Services/TransferLockService")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local ProfileTeleportHandoffService = require("../src/ServerScriptService/Services/ProfileTeleportHandoffService")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

TransferLockService.ResetForTests()
TransferLockService.ConfigureForTests({
	now = function(): number
		return 200
	end,
})
RealmTransferHandoffService.ResetForTests()
RealmTransferHandoffService.ConfigureForTests({
	now = function(): number
		return 200
	end,
})
ProfilePersistenceGateway.ResetForTests()
RealmTransferAssignmentService.ResetForTests()
ProfileTeleportHandoffService.ResetForTests()

local loadedProfileByUserId: { [number]: any } = {}
ProfilePersistenceGateway.UpdateLoadedPlayerProfileData = function(player: any, updater: any): any
	local userId = player.UserId
	local currentData = loadedProfileByUserId[userId] or { userId = userId }
	local ok, newData, reason = pcall(updater, currentData)
	if not ok or type(newData) ~= "table" then
		return {
			ok = false,
			reason = if type(reason) == "string" then reason else "profile_update_failed",
		}
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
ProfilePersistenceGateway.ReleasePlayerProfile = function(player: any): any
	loadedProfileByUserId[player.UserId] = nil
	return { ok = true }
end

local targetRealmId = RealmTransferState.FormatRealmId(9101)
loadedProfileByUserId[7101] = { userId = 7101, schemaVersion = 1 }

local beginResult = RealmTransferHandoffService.BeginHandoff({
	userId = 7101,
	targetRealmId = targetRealmId,
	operationId = "handoff:7101:pipeline",
	assignmentReason = RealmAssignmentProfileState.AssignmentReason.PartyAdmission,
	realmOwnerUserId = 9101,
	now = 200,
})
assertTrue(beginResult.accepted == true, "service begin accepted")
assertEqual(beginResult.handoffToken, "handoff:7101:pipeline", "service begin token")

local sessionResult = RealmTransferHandoffService.GetSessionRecord(targetRealmId)
assertTrue(sessionResult.accepted == true, "session record present")
assertTrue(sessionResult.sessionRecord.handoffsByToken["handoff:7101:pipeline"] ~= nil, "session record stores token")

local duplicateLock = RealmTransferHandoffService.BeginHandoff({
	userId = 7102,
	targetRealmId = targetRealmId,
	operationId = "handoff:7101:pipeline",
	now = 200,
})
assertEqual(duplicateLock.reason, "transfer_lock_active", "duplicate lock rejected")

local consumeResult = RealmTransferHandoffService.ConsumeHandoffOnArrival({
	userId = 7101,
	handoffToken = "handoff:7101:pipeline",
	targetRealmId = targetRealmId,
	now = 210,
})
assertTrue(consumeResult.accepted == true, "service consume accepted")
assertEqual(TransferLockService.TryAcquire("handoff:7101:pipeline", 220), true, "lock released after consume")

local captureTransition = RealmTransferAssignmentService.ApplyTransition(7101, {
	operation = RealmTransferState.Operations.BeginCapture,
	now = 200,
	realmOwnerUserId = 9101,
})
assertTrue(captureTransition.accepted == true, "capture transition accepted")
assertEqual(
	captureTransition.assignment.locationCategory,
	RealmAssignmentProfileState.LocationCategory.TransferInFlight,
	"capture in flight"
)

local confirmTransition = RealmTransferAssignmentService.ApplyTransition(7101, {
	operation = RealmTransferState.Operations.ConfirmArrival,
	now = 220,
	realmOwnerUserId = 9101,
})
assertTrue(confirmTransition.accepted == true, "confirm transition accepted")
assertEqual(
	confirmTransition.assignment.locationCategory,
	RealmAssignmentProfileState.LocationCategory.GiantRealm,
	"confirm giant realm"
)

local abortInvalidate = RealmTransferHandoffService.InvalidateHandoffOnAbort({
	handoffToken = "handoff:7101:abort",
	targetRealmId = targetRealmId,
	now = 220,
})
assertTrue(abortInvalidate.accepted == true, "missing abort invalidate accepted")

local expiredBegin = RealmTransferHandoffService.BeginHandoff({
	userId = 7105,
	targetRealmId = targetRealmId,
	operationId = "handoff:7105:expired",
	now = 200,
})
assertTrue(expiredBegin.accepted == true, "expired begin accepted")
local expiredResolution = RealmTransferHandoffService.ResolveExpiredSession({
	handoffToken = "handoff:7105:expired",
	targetRealmId = targetRealmId,
	now = 291,
})
assertEqual(expiredResolution.resolution, "pending_recovery_authority", "expired session resolves to pending recovery")

print("realm_transfer_handoff_service_runtime_entrypoint: all checks passed")
