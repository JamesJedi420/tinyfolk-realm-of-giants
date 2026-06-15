--!nocheck

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local ProfileTeleportHandoffService = require("../src/ServerScriptService/Services/ProfileTeleportHandoffService")
local RealmTransferHandoffService = require("../src/ServerScriptService/Services/RealmTransferHandoffService")
local TransferLockService = require("../src/ServerScriptService/Services/TransferLockService")
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

local function makePlayer(userId: number): any
	return {
		UserId = userId,
		Name = "Player" .. tostring(userId),
	}
end

local ownershipReadyByUserId: { [number]: boolean } = {}
globalEnv._ProfilePersistenceLifecycle_QueryAPI = {
	IsPlayerOwnershipReady = function(userId: number): boolean
		return ownershipReadyByUserId[userId] == true
	end,
}

local enqueueFailureReasonByUserId: { [number]: string? } = {
	[4003] = "admission_queue_unavailable",
}
local admissionQueuePayloads: { any } = {}
local function makeProfileTeleportAdmissionQueryApi(): any
	return {
		RequestTeleportHandoffAdmission = function(payload: any): any
			table.insert(admissionQueuePayloads, payload)
			local userId = payload.userId
			if type(userId) == "number" then
				local failureReason = enqueueFailureReasonByUserId[userId]
				if type(failureReason) == "string" then
					return {
						accepted = false,
						reason = failureReason,
					}
				end
			end

			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					depth = #admissionQueuePayloads,
				},
			}
		end,
	}
end

local function makePartyMatchmakingAdmissionQueryApi(): any
	return {
		RequestPartyMatchAdmission = function(payload: any): any
			table.insert(admissionQueuePayloads, payload)
			local memberUserIds = payload.partyMemberUserIds
			local userId = if type(memberUserIds) == "table" then memberUserIds[1] else nil
			if type(userId) == "number" then
				local failureReason = enqueueFailureReasonByUserId[userId]
				if type(failureReason) == "string" then
					return {
						accepted = false,
						reason = failureReason,
					}
				end
			end

			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					depth = #admissionQueuePayloads,
				},
			}
		end,
	}
end

globalEnv._ProfileTeleportAdmissionService_QueryAPI = makeProfileTeleportAdmissionQueryApi()
globalEnv._PartyMatchmakingAdmissionService_QueryAPI = makePartyMatchmakingAdmissionQueryApi()

ProfilePersistenceGateway.ResetForTests()
TransferLockService.ResetForTests()
RealmTransferHandoffService.ResetForTests()
ProfileTeleportHandoffService.ResetForTests()

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

local releaseAttemptCountByUserId: { [number]: number } = {}
local releaseFailureByUserId: { [number]: boolean } = {
	[4002] = true,
}

ProfilePersistenceGateway.ReleasePlayerProfile = function(player: any): any
	releaseAttemptCountByUserId[player.UserId] = (releaseAttemptCountByUserId[player.UserId] or 0) + 1
	if releaseFailureByUserId[player.UserId] == true then
		return {
			ok = false,
			operation = "ReleasePlayerProfile",
			reason = "release_failed_for_test",
			retryable = true,
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	loadedProfileByUserId[player.UserId] = nil
	return {
		ok = true,
		operation = "ReleasePlayerProfile",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
	}
end

local callbackResult: any = nil
local callbackRegistered = ProfileTeleportHandoffService.RegisterReleaseReadyCallback(4001, function(result: any)
	callbackResult = result
end)
assertEqual(callbackRegistered, true, "register callback")

local failedHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4002), {
	flow = "realm_entry",
	targetRealmId = "realm-main-01",
})
assertEqual(failedHandoff.ok, false, "failed handoff returns failure")
assertEqual(failedHandoff.reason, "release_before_transfer_failed", "failed handoff reason")
assertEqual(failedHandoff.fallbackRoute, "safe_fallback", "failed handoff fallback route")
assertEqual(releaseAttemptCountByUserId[4002], 1, "failed handoff attempted one release")

local invalidTargetRealmHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4004), {
	flow = "hub_to_realm",
})
assertEqual(invalidTargetRealmHandoff.ok, false, "invalid target realm handoff returns failure")
assertEqual(invalidTargetRealmHandoff.reason, "target_realm_id_invalid", "invalid target realm reason")
assertEqual(invalidTargetRealmHandoff.retryable, false, "invalid target realm not retryable")
assertEqual(invalidTargetRealmHandoff.handoffToken, nil, "invalid target realm has no token")
assertEqual(invalidTargetRealmHandoff.fallbackRoute, "safe_fallback", "invalid target realm fallback route")
assertEqual(releaseAttemptCountByUserId[4004], nil, "invalid target realm avoids release attempt")

local queueUnavailableCallbackResult: any = nil
local queueUnavailableCallbackRegistered = ProfileTeleportHandoffService.RegisterReleaseReadyCallback(
	4005,
	function(result: any)
		queueUnavailableCallbackResult = result
	end
)
assertEqual(queueUnavailableCallbackRegistered, true, "register queue-unavailable callback")

ownershipReadyByUserId[4005] = true
globalEnv._ProfileTeleportAdmissionService_QueryAPI = nil
globalEnv._PartyMatchmakingAdmissionService_QueryAPI = nil
local queueUnavailableHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4005), {
	flow = "hub_to_realm",
	targetRealmId = "realm-main-01",
})
assertEqual(queueUnavailableHandoff.ok, false, "queue-unavailable handoff returns failure")
assertEqual(queueUnavailableHandoff.reason, "admission_queue_unavailable", "queue-unavailable handoff reason")
assertEqual(queueUnavailableHandoff.retryable, true, "queue-unavailable handoff retryable")
assertEqual(queueUnavailableHandoff.handoffToken, nil, "queue-unavailable handoff has no token")
assertEqual(queueUnavailableHandoff.fallbackRoute, "safe_fallback", "queue-unavailable handoff fallback route")
assertEqual(releaseAttemptCountByUserId[4005], nil, "queue-unavailable handoff skips release attempt")
assertEqual(saveAttemptCountByUserId[4005], nil, "queue-unavailable handoff skips profile save")
assertEqual(queueUnavailableCallbackResult, nil, "queue-unavailable handoff does not trigger callback")
assertEqual(
	ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4005),
	true,
	"queue-unavailable handoff leaves no pending spawn block"
)
globalEnv._ProfileTeleportAdmissionService_QueryAPI = makeProfileTeleportAdmissionQueryApi()
globalEnv._PartyMatchmakingAdmissionService_QueryAPI = makePartyMatchmakingAdmissionQueryApi()

local firstHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4001), {
	flow = "hub_to_realm",
	targetRealmId = "realm-main-01",
})
assertEqual(firstHandoff.ok, true, "first handoff succeeds")
assertTrue(type(firstHandoff.handoffToken) == "string", "first handoff token assigned")
assertEqual(saveAttemptCountByUserId[4001], 1, "first handoff save attempted")
assertEqual(releaseAttemptCountByUserId[4001], 1, "first handoff release attempted")
assertEqual(callbackResult.handoffToken, firstHandoff.handoffToken, "release-ready callback receives token")

local firstPayload = admissionQueuePayloads[#admissionQueuePayloads]
assertTrue(type(firstPayload) == "table", "first handoff enqueue payload captured")
assertEqual(firstPayload.handoffToken, firstHandoff.handoffToken, "first handoff token maps to payload")
assertEqual(firstPayload.userId, 4001, "first handoff user id maps to payload")
assertEqual(firstPayload.targetRealmId, "realm-main-01", "first handoff target realm mapped")
local firstIngressDiagnostics = ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
assertEqual(
	firstIngressDiagnostics.totalAttempts >= 2,
	true,
	"first diagnostics total attempts include queue-unavailable"
)
assertEqual(firstIngressDiagnostics.primaryAttempts >= 2, true, "first diagnostics primary attempts")
assertEqual(firstIngressDiagnostics.primarySucceeded >= 1, true, "first diagnostics primary success count")
assertEqual(firstIngressDiagnostics.lastPath, "primary_profile_teleport", "first diagnostics last path")
assertEqual(firstIngressDiagnostics.lastReason, "accepted", "first diagnostics last reason")

local enqueueFailureCallbackResult: any = nil
local enqueueFailureCallbackRegistered = ProfileTeleportHandoffService.RegisterReleaseReadyCallback(
	4003,
	function(result: any)
		enqueueFailureCallbackResult = result
	end
)
assertEqual(enqueueFailureCallbackRegistered, true, "register enqueue-failure callback")

ownershipReadyByUserId[4003] = true
local enqueueFailedHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4003), {
	flow = "hub_to_realm",
	targetRealmId = "realm-main-01",
})
assertEqual(enqueueFailedHandoff.ok, false, "enqueue-failed handoff returns failure")
assertEqual(enqueueFailedHandoff.reason, "admission_queue_unavailable", "enqueue-failed handoff reason")
assertEqual(enqueueFailedHandoff.retryable, true, "enqueue-failed handoff retryable")
assertEqual(enqueueFailedHandoff.handoffToken, nil, "enqueue-failed handoff has no token")
assertEqual(enqueueFailedHandoff.fallbackRoute, "safe_fallback", "enqueue-failed handoff fallback route")
assertEqual(releaseAttemptCountByUserId[4003], nil, "enqueue-failed handoff skips release attempt")
assertEqual(saveAttemptCountByUserId[4003], nil, "enqueue-failed handoff skips profile save")
assertEqual(enqueueFailureCallbackResult, nil, "enqueue-failed handoff does not trigger callback")
assertEqual(
	ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4003),
	true,
	"enqueue-failed handoff leaves no pending spawn block"
)
local enqueueFailedDiagnostics = ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
assertEqual(enqueueFailedDiagnostics.lastPath, "fallback_party_matchmaking", "enqueue-failed diagnostics fallback path")
assertEqual(
	enqueueFailedDiagnostics.lastReason,
	"admission_queue_unavailable",
	"enqueue-failed diagnostics last reason"
)
assertEqual(
	enqueueFailedDiagnostics.lastFallbackReason,
	"admission_queue_unavailable",
	"enqueue-failed diagnostics fallback reason"
)

local replayedCallbackToken: string? = nil
local replayRegistered = ProfileTeleportHandoffService.RegisterReleaseReadyCallback(4001, function(result: any)
	replayedCallbackToken = result.handoffToken
end)
assertEqual(replayRegistered, true, "register callback after handoff")
assertEqual(replayedCallbackToken, firstHandoff.handoffToken, "late callback receives current handoff token")

assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4001), false, "pending handoff blocks spawn")

local confirmNotReady = ProfileTeleportHandoffService.ConfirmDestinationOwnership(4001, firstHandoff.handoffToken)
assertEqual(confirmNotReady.ok, false, "confirm not ready fails")
assertEqual(confirmNotReady.reason, "ownership_not_ready", "confirm not ready reason")
assertEqual(confirmNotReady.retryable, true, "confirm not ready retryable")

ownershipReadyByUserId[4001] = true
local confirmReady = ProfileTeleportHandoffService.ConfirmDestinationOwnership(4001, firstHandoff.handoffToken)
assertEqual(confirmReady.ok, true, "confirm ready succeeds")
assertEqual(confirmReady.handoffToken, firstHandoff.handoffToken, "confirm ready token")
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4001), true, "confirmed handoff allows spawn")
assertTrue(type(loadedProfileByUserId[4001].discoveredRealms) == "table", "confirm records discovered realms")
assertEqual(loadedProfileByUserId[4001].discoveredRealms[1].realmId, "realm-main-01", "confirm records target realm id")
assertTrue(
	type(loadedProfileByUserId[4001].discoveredRealms[1].firstDiscoveredAt) == "number",
	"confirm records first discovered timestamp"
)

loadedProfileByUserId[4001] = {
	userId = 4001,
	pendingRecovery = {
		handoffToken = "handoff:4001:restored",
		targetRealmId = "realm-main-01",
		startedAt = 10,
		status = "awaiting_destination",
	},
}
ownershipReadyByUserId[4001] = false
assertEqual(
	ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4001),
	false,
	"restored pending recovery blocks spawn"
)
assertEqual(
	ProfileTeleportHandoffService.RestorePendingHandoffFromProfile(makePlayer(4001)),
	true,
	"restore pending handoff from profile"
)
ownershipReadyByUserId[4001] = true
assertEqual(
	ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4001),
	true,
	"restored pending recovery clears on ready"
)
assertTrue(loadedProfileByUserId[4001].pendingRecovery == nil, "restored pending recovery cleared from profile")
assertEqual(
	loadedProfileByUserId[4001].discoveredRealms[1].realmId,
	"realm-main-01",
	"restored pending recovery records discovered realm"
)

ownershipReadyByUserId[4001] = false
local secondHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4001), {
	flow = "realm_to_hub",
	targetRealmId = "realm-main-01",
})
assertEqual(secondHandoff.ok, true, "second chain handoff succeeds")
assertTrue(secondHandoff.handoffToken ~= firstHandoff.handoffToken, "second handoff token differs")
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4001), false, "second pending handoff blocks spawn")

ownershipReadyByUserId[4001] = true
local secondConfirm = ProfileTeleportHandoffService.ConfirmDestinationOwnership(4001, secondHandoff.handoffToken)
assertEqual(secondConfirm.ok, true, "second confirm succeeds")
assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4001), true, "hub-realm-hub chain ends spawn-ready")

ownershipReadyByUserId[4010] = false
local destinationNotReady = ProfileTeleportHandoffService.ConfirmDestinationOwnership(4010, "token-destination")
assertEqual(destinationNotReady.ok, false, "destination-only confirm waits when ownership not ready")
assertEqual(destinationNotReady.reason, "ownership_not_ready", "destination-only confirm not-ready reason")

ownershipReadyByUserId[4010] = true
local destinationReady = ProfileTeleportHandoffService.ConfirmDestinationOwnership(4010, "token-destination")
assertEqual(destinationReady.ok, true, "destination-only confirm succeeds once ownership is ready")
assertEqual(destinationReady.handoffToken, "token-destination", "destination-only confirm preserves token")

loadedProfileByUserId[4020] = {
	userId = 4020,
	pendingRecovery = {
		handoffToken = "handoff:4020:expired",
		targetRealmId = "realm-main-01",
		startedAt = 10,
		status = "awaiting_destination",
	},
}
ownershipReadyByUserId[4020] = true
RealmTransferHandoffService.BeginHandoff({
	userId = 4020,
	targetRealmId = "realm-main-01",
	operationId = "handoff:4020:expired",
	now = 100,
})
local expiredWithRecovery = ProfileTeleportHandoffService.ConfirmDestinationOwnership(4020, "handoff:4020:expired")
assertEqual(expiredWithRecovery.ok, true, "expired token confirms via pending recovery authority")
assertEqual(
	ProfileTeleportHandoffService.CanSpawnGameplayForUserId(4020),
	true,
	"expired recovery confirm allows spawn"
)

loadedProfileByUserId[4021] = {
	userId = 4021,
	pendingRecovery = {
		handoffToken = "handoff:4021:pending",
		targetRealmId = "realm-main-01",
		startedAt = 11,
		status = "awaiting_destination",
	},
}
ownershipReadyByUserId[4021] = true
local invalidTokenConfirm = ProfileTeleportHandoffService.ConfirmDestinationOwnership(4021, "handoff:4021:invalid")
assertEqual(invalidTokenConfirm.ok, false, "invalid token confirm fails")
assertEqual(invalidTokenConfirm.reason, "handoff_token_mismatch", "invalid token mismatch reason")
assertEqual(invalidTokenConfirm.fallbackRoute, "safe_fallback", "invalid token routes to safe fallback")

assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(0), false, "invalid user cannot spawn")
assertEqual(
	ProfileTeleportHandoffService.RegisterReleaseReadyCallback(0, function() end),
	false,
	"invalid callback user"
)

print("profile_teleport_handoff_service_runtime_entrypoint: all checks passed")
