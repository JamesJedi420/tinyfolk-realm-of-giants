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

ProfilePersistenceGateway.ResetForTests()
ProfileTeleportHandoffService.ResetForTests()

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
})
assertEqual(failedHandoff.ok, false, "failed handoff returns failure")
assertEqual(failedHandoff.reason, "release_before_transfer_failed", "failed handoff reason")
assertEqual(failedHandoff.fallbackRoute, "safe_fallback", "failed handoff fallback route")
assertEqual(releaseAttemptCountByUserId[4002], 1, "failed handoff attempted one release")

local firstHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4001), {
	flow = "hub_to_realm",
})
assertEqual(firstHandoff.ok, true, "first handoff succeeds")
assertTrue(type(firstHandoff.handoffToken) == "string", "first handoff token assigned")
assertEqual(releaseAttemptCountByUserId[4001], 1, "first handoff release attempted")
assertEqual(callbackResult.handoffToken, firstHandoff.handoffToken, "release-ready callback receives token")

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

ownershipReadyByUserId[4001] = false
local secondHandoff = ProfileTeleportHandoffService.BeginCrossServerHandoff(makePlayer(4001), {
	flow = "realm_to_hub",
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

assertEqual(ProfileTeleportHandoffService.CanSpawnGameplayForUserId(0), false, "invalid user cannot spawn")
assertEqual(
	ProfileTeleportHandoffService.RegisterReleaseReadyCallback(0, function() end),
	false,
	"invalid callback user"
)

print("profile_teleport_handoff_service_runtime_entrypoint: all checks passed")
