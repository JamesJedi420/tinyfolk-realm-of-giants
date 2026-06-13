--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local MockPlayer = require("../tests/mocks/MockPlayer")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeSignal()
	local callbacks: { (Player) -> () } = {}
	return {
		Connect = function(_self: any, callback: (Player) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, player: Player)
			for _, callback in ipairs(callbacks) do
				callback(player)
			end
		end,
	}
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
addChild(configFolder, "PenRationingConfig", "../../ReplicatedStorage/Shared/Config/PenRationingConfig")
addChild(configFolder, "StationConfig", "../../ReplicatedStorage/Shared/Config/StationConfig")
addChild(
	configFolder,
	"VillageWorksiteUpgradeConfig",
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"
)

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "CaptureState", "../../ReplicatedStorage/Shared/GiantRealm/CaptureState")
addChild(giantRealmFolder, "CaptivityDurationState", "../../ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState")
addChild(
	giantRealmFolder,
	"CapturePersistenceRules",
	"../../ReplicatedStorage/Shared/GiantRealm/CapturePersistenceRules"
)
addChild(
	giantRealmFolder,
	"PostRescueProtectionState",
	"../../ReplicatedStorage/Shared/GiantRealm/PostRescueProtectionState"
)
addChild(giantRealmFolder, "PenRationingState", "../../ReplicatedStorage/Shared/GiantRealm/PenRationingState")
addChild(
	giantRealmFolder,
	"VillageWorksiteUpgradeState",
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local playersList: { any } = {}
local playersService: any = {
	PlayerRemoving = makeSignal(),
}

function playersService:GetPlayers(): { any }
	return playersList
end

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local scoreEvents: { any } = {}
local safeReturnCalls: { any } = {}
_G._ScoreService_QueryAPI = {
	RequestScoreEvent = function(userId: number, eventId: string, at: number, metadata: any): any
		table.insert(scoreEvents, {
			userId = userId,
			eventId = eventId,
			at = at,
			metadata = metadata,
		})
		return {
			accepted = true,
			reason = "accepted",
			awardedPoints = 50,
		}
	end,
}

_G._EscapeService_QueryAPI = {
	ApplyCaptivitySafeReturn = function(targetUserId: number, at: number?, returnReason: string?): any
		table.insert(safeReturnCalls, {
			targetUserId = targetUserId,
			at = at,
			returnReason = returnReason,
		})
		return {
			accepted = true,
			reason = "safe_return_applied",
			returnReason = returnReason,
		}
	end,
}

require("../src/ServerScriptService/Services/CaptureService.server")

local captureApi: any = _G._CaptureService_QueryAPI
assertTrue(type(captureApi) == "table", "service exposes query api")

local giant = MockPlayer.new(2101, "Giant", {
	role = "Giant",
	positionZ = 0,
	health = 100,
})
local giantB = MockPlayer.new(2105, "GiantB", {
	role = "Giant",
	positionZ = 1,
	health = 100,
})
local targetA = MockPlayer.new(2102, "TargetA", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
local targetB = MockPlayer.new(2103, "TargetB", {
	role = "Tinyfolk",
	positionZ = 2,
	health = 100,
})
local tinyfolk = MockPlayer.new(2104, "Tinyfolk", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})

playersList = { giant, giantB, targetA, targetB, tinyfolk }

local function setDowned(player: any, value: boolean)
	player:SetAttribute("DownedIsDowned", value)
end

local function setRole(player: any, role: string)
	player:SetAttribute("Role", role)
end

local function setAlive(player: any, health: number)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Health = health
	end
end

local function resetState()
	captureApi.ResetForTests()
	scoreEvents = {}
	safeReturnCalls = {}
	setRole(giant, "Giant")
	setRole(giantB, "Giant")
	setRole(tinyfolk, "Tinyfolk")
	setRole(targetA, "Tinyfolk")
	setRole(targetB, "Tinyfolk")
	setDowned(targetA, true)
	setDowned(targetB, true)
	setDowned(giant, false)
	setDowned(tinyfolk, false)
	setAlive(giant, 100)
	setAlive(tinyfolk, 100)
end

resetState()

local accepted = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(accepted.accepted == true, "valid request accepted")
assertEqual(accepted.reason, "accepted", "accepted reason")
assertEqual(#scoreEvents, 1, "accepted capture emits capture success score")
assertEqual(scoreEvents[1].eventId, "capture_success", "accepted capture score event")

resetState()
setRole(giant, "Tinyfolk")
local nonGiant = captureApi.RequestCapture(2101, 2102, 1.0)
assertFalse(nonGiant.accepted, "non giant rejected")
assertEqual(nonGiant.reason, "custodian_not_giant", "non giant reason")

resetState()
setDowned(targetA, false)
local notDowned = captureApi.RequestCapture(2101, 2102, 1.0)
assertFalse(notDowned.accepted, "target not downed rejected")
assertEqual(notDowned.reason, "target_not_downed", "target not downed reason")

resetState()
setAlive(giant, 0)
local deadCustodian = captureApi.RequestCapture(2101, 2102, 1.0)
assertFalse(deadCustodian.accepted, "dead custodian rejected")
assertEqual(deadCustodian.reason, "custodian_not_alive", "dead custodian reason")

resetState()
local missingTarget = captureApi.RequestCapture(2101, 999999, 1.0)
assertFalse(missingTarget.accepted, "missing target rejected")
assertEqual(missingTarget.reason, "target_not_found", "missing target reason")
assertEqual(
	giant:GetAttribute("CaptureLastReason"),
	"target_not_found",
	"missing target projects custodian last reason"
)

resetState()
local invalidTarget = captureApi.RequestCapture(2101, "bad", 1.0)
assertFalse(invalidTarget.accepted, "invalid target id rejected")
assertEqual(invalidTarget.reason, "target_user_id_invalid", "invalid target id reason")
assertEqual(
	giant:GetAttribute("CaptureLastReason"),
	"target_user_id_invalid",
	"invalid target id projects custodian last reason"
)

local throttledInvalid = captureApi.RequestCapture(2101, "bad", 1.01)
assertFalse(throttledInvalid.accepted, "rapid repeated invalid capture request is throttled")
assertEqual(throttledInvalid.reason, "request_cooldown", "rapid repeated invalid capture request cooldown reason")
assertEqual(
	giant:GetAttribute("CaptureLastReason"),
	"request_cooldown",
	"reject cooldown projects custodian last reason"
)

local validAfterRejectCooldown = captureApi.RequestCapture(2101, 2102, 1.06)
assertTrue(validAfterRejectCooldown.accepted == true, "invalid request does not consume accepted capture cooldown")
assertEqual(validAfterRejectCooldown.reason, "accepted", "valid follow-up accepted after reject cooldown window")

resetState()
local first = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(first.accepted == true, "first accepted before duplicate")
local duplicate = captureApi.RequestCapture(2105, 2102, 2.0)
assertFalse(duplicate.accepted, "duplicate target rejected")
assertEqual(duplicate.reason, "target_already_captured", "duplicate target reason")

resetState()
local holdingFirst = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(holdingFirst.accepted == true, "first accepted before holding check")
local holdingSecond = captureApi.RequestCapture(2101, 2103, 2.0)
assertFalse(holdingSecond.accepted, "custodian already holding rejected")
assertEqual(holdingSecond.reason, "custodian_already_holding", "custodian already holding reason")

_G._VillageWorksiteUpgradeService_QueryAPI = {
	GetHeldCapacityMultiplier = function(penId: string): number
		if penId == "Pen_A" then
			return 2
		end
		return 1
	end,
}

resetState()
setDowned(tinyfolk, true)
local penFirst = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(penFirst.accepted == true, "pen capacity first capture accepted")
local penSecond = captureApi.RequestCapture(2101, 2103, 2.0)
assertTrue(penSecond.accepted == true, "pen upgrade allows second concurrent capture")
local penThird = captureApi.RequestCapture(2101, 2104, 3.0)
assertFalse(penThird.accepted, "pen capacity rejects third concurrent capture")
assertEqual(penThird.reason, "custodian_capacity_reached", "pen capacity reached reason")

resetState()
local cooldownFirst = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(cooldownFirst.accepted == true, "cooldown baseline accepted")
local cooldownSecond = captureApi.RequestCapture(2101, 2103, 1.05)
assertFalse(cooldownSecond.accepted, "request cooldown rejected")
assertEqual(cooldownSecond.reason, "request_cooldown", "request cooldown reason")

resetState()
local windowCapture = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(windowCapture.accepted == true, "window capture accepted")
local activeAtSeven = captureApi.GetTargetCapture(2102, 7.0)
assertTrue(activeAtSeven ~= nil, "capture remains active before expiry")
local prunedAtNine = captureApi.GetTargetCapture(2102, 9.0)
assertTrue(prunedAtNine == nil, "capture pruned after expiry")
assertEqual(#scoreEvents, 2, "timeout emits terminal containment score")
assertEqual(scoreEvents[2].eventId, "containment_reward", "timeout containment score event")
assertEqual(scoreEvents[2].metadata.endReason, "timeout", "timeout containment metadata reason")
assertEqual(
	scoreEvents[2].metadata.operationId,
	"containment-timeout-2101-2102-1000",
	"timeout containment operation id uses capture start"
)

local duplicateTimeoutCheck = captureApi.GetTargetCapture(2102, 10.0)
assertTrue(duplicateTimeoutCheck == nil, "duplicate timeout prune remains cleared")
assertEqual(#scoreEvents, 2, "duplicate timeout prune does not duplicate containment score")

resetState()
local releaseCaptureBaseline = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(releaseCaptureBaseline.accepted == true, "accepted before release")
local wrongRelease = captureApi.ReleaseCapture(2105, 2102, 4.0)
assertFalse(wrongRelease.accepted, "wrong custodian release rejected")
assertEqual(wrongRelease.reason, "custodian_mismatch", "wrong custodian release reason")
local releaseResult = captureApi.ReleaseCapture(2101, 2102, 4.0)
assertTrue(releaseResult.accepted, "release capture accepted")
assertEqual(releaseResult.reason, "released", "release capture reason")
assertTrue(captureApi.GetTargetCapture(2102, 4.1) == nil, "release clears active capture")
assertEqual(#scoreEvents, 2, "release emits terminal containment score")
assertEqual(scoreEvents[2].metadata.endReason, "released", "release containment metadata reason")
local missingRelease = captureApi.ReleaseCapture(2101, 2102, 4.2)
assertFalse(missingRelease.accepted, "missing release rejected")
assertEqual(missingRelease.reason, "capture_missing", "missing release reason")

resetState()
local toClear = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(toClear.accepted == true, "accepted before player removing")
playersService.PlayerRemoving:Fire(giant)
local afterRemove = captureApi.GetTargetCapture(2102, 1.1)
assertTrue(afterRemove == nil, "player removing clears active capture")
assertEqual(#scoreEvents, 2, "player removing emits terminal containment score")
assertEqual(scoreEvents[2].metadata.endReason, "logout", "player removing containment metadata reason")

resetState()
setDowned(targetA, false)
targetA:SetAttribute("PostRescueProtected", true)
targetA:SetAttribute("PostRescueProtectionExpiresAt", 20)
local protectedReject = captureApi.RequestCapture(2101, 2102, 2.0)
assertFalse(protectedReject.accepted, "capture rejected while target has post-rescue protection")
assertEqual(protectedReject.reason, "target_post_rescue_protected", "post-rescue protection rejection reason")

resetState()
targetA:SetAttribute("PostRescueProtected", true)
targetA:SetAttribute("PostRescueProtectionExpiresAt", 1.5)
local afterExpiry = captureApi.RequestCapture(2101, 2102, 2.0)
assertTrue(afterExpiry.accepted == true, "capture accepted after post-rescue protection expiry")
assertTrue(targetA:GetAttribute("PostRescueProtected") == false, "expired post-rescue protection cleared")
assertTrue(targetA:GetAttribute("PostRescueProtectionExpiresAt") == nil, "expired protection expiry attribute cleared")

resetState()
targetA:SetAttribute("PostRescueProtected", true)
targetA:SetAttribute("PostRescueProtectionExpiresAt", 20)
local downedCancellation = captureApi.RequestCapture(2101, 2102, 2.0)
assertTrue(downedCancellation.accepted == true, "capture accepted when downed state cancels post-rescue protection")
assertTrue(targetA:GetAttribute("PostRescueProtected") == false, "downed cancellation clears post-rescue protection")
assertTrue(
	targetA:GetAttribute("PostRescueProtectionExpiresAt") == nil,
	"downed cancellation clears protection expiry attribute"
)

resetState()
local antiGuardingFirst = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(antiGuardingFirst.accepted == true, "anti-guarding baseline first capture accepted")
local antiGuardingSecond = captureApi.RequestCapture(2101, 2102, 10.0)
assertFalse(antiGuardingSecond.accepted, "anti-guarding rejects repeated same pair within cooldown")
assertEqual(
	antiGuardingSecond.reason,
	"anti_guarding_repeat_target_cooldown",
	"anti-guarding repeat target rejection reason"
)

resetState()
local antiGuardingExpiredFirst = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(antiGuardingExpiredFirst.accepted == true, "anti-guarding expiry baseline accepted")
local antiGuardingAfterExpiry = captureApi.RequestCapture(2101, 2102, 13.0)
assertTrue(antiGuardingAfterExpiry.accepted == true, "anti-guarding allows repeat target after cooldown")

resetState()
local pairOne = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(pairOne.accepted == true, "pair diminishing first capture accepted")
captureApi.ReleaseCapture(2101, 2102, 9.0)
local pairTwo = captureApi.RequestCapture(2101, 2102, 14.0)
assertTrue(pairTwo.accepted == true, "pair diminishing second capture accepted")
captureApi.ReleaseCapture(2101, 2102, 22.0)
local pairThree = captureApi.RequestCapture(2101, 2102, 27.0)
assertTrue(pairThree.accepted == true, "pair diminishing third capture accepted")
captureApi.ReleaseCapture(2101, 2102, 35.0)
local pairFour = captureApi.RequestCapture(2101, 2102, 40.0)
assertTrue(pairFour.accepted == true, "pair diminishing fourth capture accepted")
local pairFourthRelease = captureApi.ReleaseCapture(2101, 2102, 47.9)
assertTrue(pairFourthRelease.accepted, "pair diminishing fourth release accepted")
assertEqual(scoreEvents[2].metadata.contributionRatio, 1, "pair first terminal reward full ratio")
assertEqual(scoreEvents[4].metadata.contributionRatio, 0.5, "pair second terminal reward half ratio")
assertEqual(scoreEvents[6].metadata.contributionRatio, 0.25, "pair third terminal reward quarter ratio")
assertEqual(pairFourthRelease.reward.reason, "pair_reward_cap_reached", "pair fourth terminal reward capped")
assertEqual(#scoreEvents, 7, "pair fourth terminal reward does not emit containment score")
assertTrue(captureApi.GetTargetCapture(2102, 48.1) == nil, "pair fourth capped reward still clears capture")

local moraleByCustodian: { [number]: number } = {}
_G._PenRationingService_QueryAPI = {
	GetCustodianMorale = function(custodianUserId: number): number
		return moraleByCustodian[custodianUserId] or 100
	end,
}

resetState()
moraleByCustodian[2101] = 0
local depletedMorale = captureApi.RequestCapture(2101, 2102, 60.0)
assertFalse(depletedMorale.accepted, "depleted morale blocks capture")
assertEqual(depletedMorale.reason, "custodian_morale_depleted", "depleted morale reason")

resetState()
moraleByCustodian[2101] = 48
local shakenMorale = captureApi.RequestCapture(2101, 2102, 60.0)
assertFalse(shakenMorale.accepted, "shaken morale blocks capture roll")
assertEqual(shakenMorale.reason, "custodian_morale_shaken", "shaken morale reason")

resetState()
moraleByCustodian[2101] = 50
local sureMorale = captureApi.RequestCapture(2101, 2102, 60.0)
assertTrue(sureMorale.accepted == true, "sure threshold morale captures")
assertEqual(sureMorale.reason, "accepted", "sure threshold morale accepted reason")

local prohibitedEnd = captureApi.ValidateCustodyEndReason("sold")
assertFalse(prohibitedEnd.accepted == true, "prohibited custody end rejected")
assertEqual(prohibitedEnd.reason, "end_reason_prohibited", "prohibited custody end reason")

local validEnd = captureApi.ValidateCustodyEndReason("escaped")
assertTrue(validEnd.accepted == true, "valid custody end accepted")

assertTrue(captureApi.CanTargetPerformEscapeAction("escape_route"), "escape route action allowed")
assertFalse(captureApi.CanTargetPerformEscapeAction("account_lock"), "account lock action blocked")

local reconnect = captureApi.ResolveReconnectCaptureRestore(nil)
assertFalse(reconnect.restoreCapture == true, "reconnect does not restore capture")

local hydration = captureApi.ResolveProfileCaptureHydration({ profileCaptureState = { targetUserId = 2102 } })
assertEqual(hydration.action, "clear_capture_runtime", "profile capture hydration clears")

resetState()
local timeoutCapture = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(timeoutCapture.accepted == true, "timeout capture accepted")
captureApi.GetTargetCapture(2102, 9.0)
assertEqual(#safeReturnCalls, 1, "timeout triggers safe return fallback")
assertEqual(safeReturnCalls[1].targetUserId, 2102, "safe return targets captured tinyfolk")
assertEqual(safeReturnCalls[1].returnReason, "safe_return", "safe return reason")

resetState()
local transferBaseline = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(transferBaseline.accepted == true, "transfer baseline accepted")
local transferred = captureApi.TransferTargetCustody(2102, 2105, 2.0)
assertTrue(transferred.accepted == true, "custody transfer accepted")
assertEqual(transferred.record.custodianUserId, 2105, "transfer updates custodian")
assertEqual(transferred.record.startedAt, 1.0, "transfer preserves capture start")
assertEqual(transferred.record.captivityAnchorAt, 1.0, "transfer preserves captivity anchor")
local stillActive = captureApi.GetTargetCapture(2102, 7.0)
assertTrue(stillActive ~= nil, "transfer does not clear active capture before expiry")
assertEqual(stillActive.custodianUserId, 2105, "active capture reflects transferred custodian")

resetState()
local containedBaseline = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(containedBaseline.accepted == true, "contained baseline accepted")
local promoted = captureApi.PromoteTargetToContained(2102, 2.0)
assertTrue(promoted.accepted == true, "promote to contained accepted")
assertEqual(promoted.record.containmentPhase, "contained", "promoted record phase")
assertEqual(promoted.record.containedAt, 2.0, "promoted containedAt set")
assertEqual(promoted.record.captivityAnchorAt, 1.0, "promote preserves captivity anchor")

print("capture_service_runtime_entrypoint: all checks passed")
