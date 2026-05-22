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

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "CaptureState", "../../ReplicatedStorage/Shared/GiantRealm/CaptureState")

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

resetState()
local toClear = captureApi.RequestCapture(2101, 2102, 1.0)
assertTrue(toClear.accepted == true, "accepted before player removing")
playersService.PlayerRemoving:Fire(giant)
local afterRemove = captureApi.GetTargetCapture(2102, 1.1)
assertTrue(afterRemove == nil, "player removing clears active capture")

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

print("capture_service_runtime_entrypoint: all checks passed")
