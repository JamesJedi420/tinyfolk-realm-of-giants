--!nocheck

local PlayerLocationService = require("../src/ServerScriptService/Services/PlayerLocationService")
local PlayerLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
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

local userId = 8901

local initial = PlayerLocationService.GetLocationSnapshot(userId)
assertTrue(initial.accepted == true, "initial snapshot accepted")
assertEqual(initial.snapshot.location, PlayerLocationState.Location.SharedHub, "initial shared hub")

local transit = PlayerLocationService.ApplyTransition(userId, {
	operation = PlayerLocationState.Operations.BeginTransit,
	now = 10,
	realmOwnerUserId = 9001,
	transitReason = PlayerLocationState.TransitReason.PartyAdmission,
})
assertTrue(transit.accepted == true, "runtime begin transit accepted")
assertEqual(transit.snapshot.location, PlayerLocationState.Location.Transit, "runtime transit location")

local guest = PlayerLocationService.ApplyTransition(userId, {
	operation = PlayerLocationState.Operations.ConfirmRealmGuest,
	now = 11,
	realmOwnerUserId = 9001,
})
assertTrue(guest.accepted == true, "runtime confirm guest accepted")
assertEqual(guest.snapshot.location, PlayerLocationState.Location.RealmGuest, "runtime guest location")

local captured = PlayerLocationService.ApplyTransition(userId, {
	operation = PlayerLocationState.Operations.Capture,
	now = 12,
})
assertTrue(captured.accepted == true, "runtime capture accepted")

local disconnect = PlayerLocationService.ResolveDisconnect(userId, { now = 13 })
assertTrue(disconnect.accepted == true, "runtime disconnect accepted")
assertEqual(disconnect.snapshot.location, PlayerLocationState.Location.ReturnPending, "runtime return pending")
assertTrue(disconnect.persistReturnPending == true, "runtime persist return pending")

local diagnostics = PlayerLocationService.GetDiagnostics()
assertTrue(diagnostics.totalTransitions >= 3, "diagnostics track transitions")
assertTrue(diagnostics.totalDisconnectResolutions >= 1, "diagnostics track disconnect")

local assignmentHydrateUserId = 8902
loadedProfileByUserId[assignmentHydrateUserId] = {
	schemaVersion = 1,
	userId = assignmentHydrateUserId,
}
RealmTransferAssignmentService.ApplyTransition(assignmentHydrateUserId, {
	operation = RealmTransferState.Operations.BeginCapture,
	now = 20,
	realmOwnerUserId = 9100,
})
RealmTransferAssignmentService.ApplyTransition(assignmentHydrateUserId, {
	operation = RealmTransferState.Operations.ConfirmArrival,
	now = 21,
	realmOwnerUserId = 9100,
})

local hydrated = PlayerLocationService.HydrateFromRealmAssignment(assignmentHydrateUserId)
assertTrue(hydrated.accepted == true, "hydrate from realm assignment accepted")
assertEqual(hydrated.snapshot.location, PlayerLocationState.Location.RealmGuest, "hydrated realm guest")
assertEqual(hydrated.snapshot.realmId, RealmTransferState.FormatRealmId(9100), "hydrated realm id")

print("player_location_service_runtime_entrypoint: all checks passed")
