--!nocheck

local PlayerLocationService = require("../src/ServerScriptService/Services/PlayerLocationService")
local PlayerLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local RealmSafeReturnService = require("../src/ServerScriptService/Services/RealmSafeReturnService")
local RealmSafeReturnState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmSafeReturnState")
local RealmTransferAssignmentService = require("../src/ServerScriptService/Services/RealmTransferAssignmentService")

local Location = PlayerLocationState.Location
local Operations = PlayerLocationState.Operations
local ReturnTrigger = RealmSafeReturnState.ReturnTrigger

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
RealmSafeReturnService.ResetForTests()

local loadedProfileByUserId: { [number]: any } = {}
local captivityCalls: { any } = {}

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

local escapeApiOverride = {
	ApplyCaptivitySafeReturn = function(targetUserId: number, at: number?, returnReason: string?): any
		table.insert(captivityCalls, {
			targetUserId = targetUserId,
			at = at,
			returnReason = returnReason,
		})
		return {
			accepted = true,
			reason = "safe_return_applied",
		}
	end,
}

RealmSafeReturnService.SetTestOverrides({
	profileGateway = ProfilePersistenceGateway,
})

if type(_G) == "table" then
	rawset(_G, "_EscapeService_QueryAPI", escapeApiOverride)
end

local userId = 9201
local ownerUserId = 9301

PlayerLocationService.ApplyTransition(userId, {
	operation = Operations.BeginTransit,
	now = 10,
	realmOwnerUserId = ownerUserId,
	transitReason = PlayerLocationState.TransitReason.PartyAdmission,
})
PlayerLocationService.ApplyTransition(userId, {
	operation = Operations.ConfirmRealmGuest,
	now = 11,
	realmOwnerUserId = ownerUserId,
})

loadedProfileByUserId[userId] = { userId = userId }

local logoutResult = RealmSafeReturnService.ApplyReturnRequest(userId, {
	trigger = ReturnTrigger.Logout,
	isOnline = false,
	now = 12,
})
assertTrue(logoutResult.accepted == true, "logout return accepted")
assertTrue(logoutResult.persistedSafeLocation == true, "logout persisted safe location")

local snapshotAfterLogout = PlayerLocationService.GetLocationSnapshot(userId)
assertEqual(snapshotAfterLogout.snapshot.location, Location.ReturnPending, "logout leaves return pending")

local profileAfterLogout = loadedProfileByUserId[userId]
assertEqual(profileAfterLogout.safeLocation.returnReason, "logout", "logout safe location reason")

local joinResult = RealmSafeReturnService.ResolvePendingReturnOnJoin(userId, {
	hasSafeLocation = true,
	now = 13,
})
assertTrue(joinResult.accepted == true, "join resolution accepted")
assertTrue(joinResult.requiresSafeLocationSpawn == true, "join requires safe location spawn")

local snapshotAfterJoin = PlayerLocationService.GetLocationSnapshot(userId)
assertEqual(snapshotAfterJoin.snapshot.location, Location.SharedHub, "join resolves hub")

local visitorUserId = 9202
PlayerLocationService.ApplyTransition(visitorUserId, {
	operation = Operations.BeginTransit,
	now = 20,
	realmOwnerUserId = ownerUserId,
	transitReason = PlayerLocationState.TransitReason.Raid,
})
PlayerLocationService.ApplyTransition(visitorUserId, {
	operation = Operations.ConfirmRealmInvader,
	now = 21,
	realmOwnerUserId = ownerUserId,
})

loadedProfileByUserId[visitorUserId] = { userId = visitorUserId }

local giantDisconnectResult = RealmSafeReturnService.HandleGiantDisconnect(ownerUserId, {
	candidateUserIds = { visitorUserId, userId },
	isOnline = true,
	now = 22,
})
assertEqual(#giantDisconnectResult.returnedUserIds, 1, "giant disconnect returns one visitor")
assertEqual(giantDisconnectResult.returnedUserIds[1], visitorUserId, "giant disconnect visitor id")

local timeoutUserId = 9203
PlayerLocationService.ApplyTransition(timeoutUserId, {
	operation = Operations.BeginTransit,
	now = 30,
	realmOwnerUserId = ownerUserId,
	transitReason = PlayerLocationState.TransitReason.Capture,
})
PlayerLocationService.ApplyTransition(timeoutUserId, {
	operation = Operations.ConfirmCaptured,
	now = 31,
	realmOwnerUserId = ownerUserId,
})

local timeoutResult = RealmSafeReturnService.ApplyReturnRequest(timeoutUserId, {
	trigger = ReturnTrigger.Timeout,
	isOnline = true,
	now = 32,
})
assertTrue(timeoutResult.accepted == true, "timeout return accepted")
assertEqual(#captivityCalls, 1, "timeout captivity safe return called")
assertEqual(captivityCalls[1].targetUserId, timeoutUserId, "timeout captivity target")

print("realm_safe_return_service_runtime_entrypoint: all checks passed")
