--!nocheck

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local ProfileTeleportHandoffService = require("../src/ServerScriptService/Services/ProfileTeleportHandoffService")
local globalEnv: any = getfenv()

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function makePlayer(userId: number, teleportData: any?): any
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
	}
	if teleportData ~= nil then
		function player:GetJoinData(): any
			return {
				TeleportData = teleportData,
			}
		end
	end
	return player
end

local ownershipReadyByUserId: { [number]: boolean } = {}
local ownershipCallbacksByUserId: { [number]: { (boolean, string?) -> () } } = {}
globalEnv._ProfilePersistenceLifecycle_QueryAPI = {
	IsPlayerOwnershipReady = function(userId: number): boolean
		return ownershipReadyByUserId[userId] == true
	end,
	RegisterOwnershipReadyCallback = function(userId: number, callback: any): boolean
		if type(callback) ~= "function" then
			return false
		end

		local callbacks = ownershipCallbacksByUserId[userId]
		if callbacks == nil then
			callbacks = {}
			ownershipCallbacksByUserId[userId] = callbacks
		end
		table.insert(callbacks, callback)

		if ownershipReadyByUserId[userId] == true then
			pcall(callback, true, nil)
		end

		return true
	end,
}

local capacityCommitCalls: { any } = {}
globalEnv._ActiveRealmCapacity_QueryAPI = {
	CommitTinyfolkArrival = function(realmId: string, count: number, now: number): any
		table.insert(capacityCommitCalls, {
			realmId = realmId,
			count = count,
			now = now,
		})
		return {
			accepted = true,
			reason = "accepted",
		}
	end,
}

globalEnv._ProfileTeleportAdmissionService_QueryAPI = {
	RequestTeleportHandoffAdmission = function(_payload: any): any
		return {
			accepted = true,
			reason = "accepted",
		}
	end,
}

ProfilePersistenceGateway.ResetForTests()
ProfileTeleportHandoffService.ResetForTests()

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

ProfilePersistenceGateway.SavePlayerProfile = function(_player: any): any
	return {
		ok = true,
		operation = "SavePlayerProfile",
	}
end

ProfilePersistenceGateway.ReleasePlayerProfile = function(player: any): any
	loadedProfileByUserId[player.UserId] = nil
	return {
		ok = true,
		operation = "ReleasePlayerProfile",
	}
end

local noTransfer = ProfileTeleportHandoffService.OrchestrateDestinationArrival(makePlayer(5001))
assertEqual(noTransfer.ok, true, "no transfer context succeeds")
assertEqual(noTransfer.reason, "no_transfer_context", "no transfer reason")
local noTransferDiagnostics = ProfileTeleportHandoffService.GetDestinationOrchestrationDiagnostics()
assertEqual(noTransferDiagnostics.noTransferSkipped, 1, "no transfer skipped count")

ownershipReadyByUserId[5002] = false
loadedProfileByUserId[5002] = {
	userId = 5002,
	pendingRecovery = {
		handoffToken = "handoff:5002:restored",
		targetRealmId = "realm-dest-01",
		startedAt = 10,
		status = "awaiting_destination",
	},
}
local awaitingOwnership = ProfileTeleportHandoffService.OrchestrateDestinationArrival(makePlayer(5002))
assertEqual(awaitingOwnership.ok, false, "awaiting ownership fails until ready")
assertEqual(awaitingOwnership.reason, "ownership_not_ready", "awaiting ownership reason")
assertEqual(awaitingOwnership.retryable, true, "awaiting ownership retryable")
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(5002), false, "pending handoff blocks spawn")

ownershipReadyByUserId[5002] = true
local confirmed = ProfileTeleportHandoffService.OrchestrateDestinationArrival(makePlayer(5002))
assertEqual(confirmed.ok, true, "confirmed destination succeeds")
assertEqual(confirmed.handoffToken, "handoff:5002:restored", "confirmed token from profile")
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(5002), true, "confirmed handoff allows spawn")
assertTrue(loadedProfileByUserId[5002].pendingRecovery == nil, "pending recovery cleared")
assertTrue(type(loadedProfileByUserId[5002].discoveredRealms) == "table", "discovered realm recorded")
assertEqual(loadedProfileByUserId[5002].discoveredRealms[1].realmId, "realm-dest-01", "discovered realm id")
assertEqual(#capacityCommitCalls, 1, "capacity commit called once")
assertEqual(capacityCommitCalls[1].realmId, "realm-dest-01", "capacity commit realm id")

loadedProfileByUserId[5003] = {
	userId = 5003,
	pendingRecovery = {
		handoffToken = "handoff:5003:teleport",
		targetRealmId = "realm-teleport-01",
		startedAt = 11,
		status = "awaiting_destination",
	},
}
ownershipReadyByUserId[5003] = false
local teleportPlayer = makePlayer(5003, {
	operationId = "op-5003",
	partyId = "party-5003",
	targetRealmId = "realm-teleport-01",
	handoffTokensByUserId = {
		[5003] = "handoff:5003:teleport",
	},
})
local teleportAwaiting = ProfileTeleportHandoffService.OrchestrateDestinationArrival(teleportPlayer)
assertEqual(teleportAwaiting.ok, false, "teleport arrival waits for ownership")
assertEqual(teleportAwaiting.reason, "ownership_not_ready", "teleport arrival wait reason")

ownershipReadyByUserId[5003] = true
local teleportConfirmed = ProfileTeleportHandoffService.OrchestrateDestinationArrival(teleportPlayer)
assertEqual(teleportConfirmed.ok, true, "teleport arrival confirms")
assertEqual(teleportConfirmed.handoffToken, "handoff:5003:teleport", "teleport token used for confirm")
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(5003), true, "teleport arrival allows spawn")
assertEqual(capacityCommitCalls[#capacityCommitCalls].realmId, "realm-teleport-01", "teleport capacity realm")

ProfileTeleportHandoffService.ResetForTests()
ownershipReadyByUserId = {}
ownershipCallbacksByUserId = {}
capacityCommitCalls = {}
loadedProfileByUserId = {}

local playerAddedCallbacks: { (any) -> () } = {}
local fakePlayers = {
	PlayerAdded = {
		Connect = function(_self: any, callback: any)
			table.insert(playerAddedCallbacks, callback)
		end,
	},
	PlayerRemoving = {
		Connect = function(_self: any, _callback: any)
			return
		end,
	},
	GetPlayers = function(_self: any): { any }
		return {}
	end,
}

local startResult = ProfileTeleportHandoffService.StartDestinationOrchestration({
	players = fakePlayers,
	teleportContextResolver = function(player: any): any
		if player.UserId == 5010 then
			return {
				targetRealmId = "realm-start-01",
				handoffTokensByUserId = {
					[5010] = "handoff:5010:start",
				},
			}
		end
		return nil
	end,
})
assertEqual(startResult.ok, true, "destination orchestration starts")

loadedProfileByUserId[5010] = {
	userId = 5010,
	pendingRecovery = {
		handoffToken = "handoff:5010:start",
		targetRealmId = "realm-start-01",
		startedAt = 20,
		status = "awaiting_destination",
	},
}
ownershipReadyByUserId[5010] = false

local startedPlayer = makePlayer(5010)
assertEqual(#playerAddedCallbacks, 1, "player added callback registered")
playerAddedCallbacks[1](startedPlayer)
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(5010), false, "started orchestration blocks spawn")

ownershipReadyByUserId[5010] = true
for _, callback in ipairs(ownershipCallbacksByUserId[5010] or {}) do
	callback(true, nil)
end
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(5010), true, "ownership callback confirms arrival")
local startedDiagnostics = ProfileTeleportHandoffService.GetDestinationOrchestrationDiagnostics()
assertEqual(startedDiagnostics.confirmed >= 1, true, "started diagnostics confirm count")

print("profile_teleport_destination_orchestration_runtime_entrypoint: all checks passed")
