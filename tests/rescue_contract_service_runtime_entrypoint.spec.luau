--!strict

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
	local callbacks: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, ...: any)
			for _, callback in ipairs(callbacks) do
				callback(...)
			end
		end,
	}
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireClient(_self: any, _player: any, _payload: any)
		return
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "RescueContractRequest", makeRemoteEvent("RescueContractRequest"))
addChild(remotesFolder, "RescueContractResponse", makeRemoteEvent("RescueContractResponse"))
addChild(remotesFolder, "RescueContractCompleteRequest", makeRemoteEvent("RescueContractCompleteRequest"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(configFolder, "RescueContractConfig", "../../ReplicatedStorage/Shared/Config/RescueContractConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
addChild(giantRealmFolder, "RescueContractState", "../../ReplicatedStorage/Shared/GiantRealm/RescueContractState")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local rescuer = MockPlayer.new(2101, "RescuerTinyfolk", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
local target = MockPlayer.new(2102, "TargetTinyfolk", {
	role = "Tinyfolk",
	positionZ = 4,
	health = 100,
})
local targetTwo = MockPlayer.new(2103, "TargetTinyfolkTwo", {
	role = "Tinyfolk",
	positionZ = 6,
	health = 100,
})
local rescuerTwo = MockPlayer.new(2104, "RescuerTinyfolkTwo", {
	role = "Tinyfolk",
	positionZ = 2,
	health = 100,
})
local targetThree = MockPlayer.new(2105, "TargetTinyfolkThree", {
	role = "Tinyfolk",
	positionZ = 8,
	health = 100,
})
target:SetAttribute("DownedIsDowned", true)
targetTwo:SetAttribute("DownedIsDowned", true)
targetThree:SetAttribute("DownedIsDowned", true)

local playersList: { any } = { rescuer, target, targetTwo, rescuerTwo, targetThree }
local playersService: any = {
	PlayerRemoving = makeSignal(),
}

function playersService:GetPlayers(): { any }
	return playersList
end

local workspaceService = makeNode("Workspace", "Workspace")

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

_G._GrabService_QueryAPI = {
	IsPlayerCarried = function(_userId: number): boolean
		return false
	end,
}

local restrictedRescuerUserId: number? = nil
_G._RoleService_QueryAPI = {
	IsPlayerDowned = function(userId: number): boolean
		for _, player in ipairs(playersList) do
			if player.UserId == userId then
				if restrictedRescuerUserId == userId then
					return true
				end
				return player:GetAttribute("DownedIsDowned") == true
			end
		end
		return false
	end,
	CanPlayerPerformInteraction = function(userId: number, interactionName: string): boolean
		if interactionName ~= "rescueContractRequest" then
			return true
		end
		return restrictedRescuerUserId ~= userId
	end,
}

require("../src/ServerScriptService/Services/RescueContractService.server")

local rescueApi: any = _G._RescueContractService_QueryAPI
assertTrue(type(rescueApi) == "table", "service exposes query API")

local function setRole(player: any, role: string)
	player:SetAttribute("Role", role)
end

local function setHumanoidHealth(player: any, health: number)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Health = health
	end
end

local function resetState()
	rescueApi.ResetForTests()
	setRole(rescuer, "Tinyfolk")
	setRole(target, "Tinyfolk")
	setRole(targetTwo, "Tinyfolk")
	setRole(rescuerTwo, "Tinyfolk")
	setRole(targetThree, "Tinyfolk")
	setHumanoidHealth(rescuer, 100)
	setHumanoidHealth(target, 100)
	setHumanoidHealth(targetTwo, 100)
	setHumanoidHealth(rescuerTwo, 100)
	setHumanoidHealth(targetThree, 100)
	rescuer:SetAttribute("DownedIsDowned", false)
	rescuerTwo:SetAttribute("DownedIsDowned", false)
	target:SetAttribute("DownedIsDowned", true)
	targetTwo:SetAttribute("DownedIsDowned", true)
	targetThree:SetAttribute("DownedIsDowned", true)
	target:SetAttribute("InSafeZone", false)
	target:SetAttribute("SafeZoneType", nil)
	target:SetAttribute("SafeZoneProtectionEndsAt", nil)
	targetTwo:SetAttribute("InSafeZone", false)
	targetTwo:SetAttribute("SafeZoneType", nil)
	targetTwo:SetAttribute("SafeZoneProtectionEndsAt", nil)
	targetThree:SetAttribute("InSafeZone", false)
	targetThree:SetAttribute("SafeZoneType", nil)
	targetThree:SetAttribute("SafeZoneProtectionEndsAt", nil)
	restrictedRescuerUserId = nil
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 100)

	assertTrue(accepted.accepted, "request accepted in valid baseline")
	assertEqual(accepted.reason, "accepted", "request accepted reason")
	assertEqual(accepted.contract.rescuerUserId, rescuer.UserId, "accepted contract stores rescuer")
	assertEqual(accepted.contract.targetUserId, target.UserId, "accepted contract stores target")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 200)
	assertTrue(accepted.accepted, "baseline acceptance before cooldown test")

	local throttled = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 200.1)
	assertFalse(throttled.accepted, "rapid repeat request throttled")
	assertEqual(throttled.reason, "request_cooldown", "repeat request cooldown reason")
end

do
	resetState()
	local invalidTargetId = rescueApi.RequestRescueContract(rescuer.UserId, "bad", 250)
	assertFalse(invalidTargetId.accepted, "invalid target id rejects")
	assertEqual(invalidTargetId.reason, "target_user_id_invalid", "invalid target id reason")

	local missingTarget = rescueApi.RequestRescueContract(rescuer.UserId, 999999, 250)
	assertFalse(missingTarget.accepted, "missing target rejects")
	assertEqual(missingTarget.reason, "target_not_found", "missing target reason")
end

do
	resetState()
	target:SetAttribute("DownedIsDowned", false)
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 300)

	assertFalse(rejected.accepted, "target must be downed")
	assertEqual(rejected.reason, "target_not_downed", "target not downed reason")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 400)
	assertTrue(accepted.accepted, "request accepted before completion")

	local completed = rescueApi.CompleteRescueContract(rescuer.UserId, target.UserId, 401)
	assertTrue(completed.accepted, "completion accepted for active contract")
	assertEqual(completed.reason, "rescued", "completion reason")
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId), nil, "contract cleared after completion")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 450)
	assertTrue(accepted.accepted, "baseline accepted before rejected completion")

	local rejectedComplete = rescueApi.CompleteRescueContract(rescuer.UserId, targetTwo.UserId, 451)
	assertFalse(rejectedComplete.accepted, "completion rejects wrong target")
	assertEqual(rejectedComplete.reason, "target_mismatch", "wrong target completion reason")

	local activeContract = rescueApi.GetRescuerContract(rescuer.UserId, 451)
	assertTrue(activeContract ~= nil, "rejected completion preserves active contract")
	assertEqual(
		rescuer:GetAttribute("RescueContractTargetUserId"),
		target.UserId,
		"rejected completion preserves rescuer attribute target"
	)
end

do
	resetState()
	restrictedRescuerUserId = rescuer.UserId
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 470)
	assertFalse(rejected.accepted, "restricted rescuer cannot request")
	assertEqual(rejected.reason, "rescuer_interaction_restricted", "restricted rescuer rejection reason")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 500)
	assertTrue(accepted.accepted, "baseline accepted before rejected follow-up request")

	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, targetTwo.UserId, 500.1)
	assertFalse(rejected.accepted, "rapid follow-up request rejected")
	assertEqual(rejected.reason, "request_cooldown", "follow-up cooldown reason")
	assertEqual(
		rescuer:GetAttribute("RescueContractTargetUserId"),
		target.UserId,
		"rejected follow-up request preserves active attribute target"
	)
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 600)
	assertTrue(accepted.accepted, "contract accepted before expiry test")

	local postExpiry = rescueApi.RequestRescueContract(rescuer.UserId, targetTwo.UserId, 612.1)
	assertTrue(postExpiry.accepted, "expired contract is pruned before next request")
	assertEqual(postExpiry.contract.targetUserId, targetTwo.UserId, "post-expiry request targets second target")
end

do
	resetState()
	local first = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 650)
	assertTrue(first.accepted, "accepted before participant overlap checks")
	target:SetAttribute("DownedIsDowned", false)

	local targetStartsAnother = rescueApi.RequestRescueContract(target.UserId, targetTwo.UserId, 651)
	assertFalse(targetStartsAnother.accepted, "targeted participant cannot start another contract")
	assertEqual(
		targetStartsAnother.reason,
		"participant_contract_active",
		"targeted participant start rejection reason"
	)

	rescuer:SetAttribute("DownedIsDowned", true)
	local rescuerBecomesTarget = rescueApi.RequestRescueContract(rescuerTwo.UserId, rescuer.UserId, 651)
	assertFalse(rescuerBecomesTarget.accepted, "active rescuer cannot become target")
	assertEqual(rescuerBecomesTarget.reason, "participant_contract_active", "active rescuer target rejection reason")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 700)
	assertTrue(accepted.accepted, "accepted before rescuer leave cleanup")

	playersService.PlayerRemoving:Fire(rescuer)
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 700.1), nil, "rescuer leave clears active contract")
	assertEqual(rescuer:GetAttribute("RescueContractActive"), false, "rescuer leave clears active attribute")
	assertEqual(target:GetAttribute("RescueContractActive"), false, "rescuer leave clears target active attribute")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 800)
	assertTrue(accepted.accepted, "accepted before target leave cleanup")

	playersService.PlayerRemoving:Fire(target)
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 800.1), nil, "target leave clears active contract")
	assertEqual(rescuer:GetAttribute("RescueContractActive"), false, "target leave clears rescuer active attribute")
	assertEqual(target:GetAttribute("RescueContractActive"), false, "target leave clears target active attribute")
end

do
	resetState()
	local first = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 900)
	assertTrue(first.accepted, "first parallel contract accepted")

	local second = rescueApi.RequestRescueContract(rescuerTwo.UserId, targetThree.UserId, 900)
	assertTrue(second.accepted, "second parallel contract accepted")

	assertEqual(rescuer:GetAttribute("RescueContractActive"), true, "first rescuer active attribute set")
	assertEqual(target:GetAttribute("RescueContractActive"), true, "first target active attribute set")
	assertEqual(rescuerTwo:GetAttribute("RescueContractActive"), true, "second rescuer active attribute set")
	assertEqual(targetThree:GetAttribute("RescueContractActive"), true, "second target active attribute set")
end

do
	resetState()
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, rescuer.UserId, 500)
	assertFalse(rejected.accepted, "self rescue rejected")
	assertEqual(rejected.reason, "self_rescue_not_allowed", "self rescue rejection reason")
end

do
	resetState()
	local missingRescuerRequest = rescueApi.RequestRescueContract(999999, target.UserId, 950)
	assertFalse(missingRescuerRequest.accepted, "query request rejects missing rescuer")
	assertEqual(missingRescuerRequest.reason, "rescuer_not_found", "query request missing rescuer reason")

	local missingRescuerComplete = rescueApi.CompleteRescueContract(999999, target.UserId, 950)
	assertFalse(missingRescuerComplete.accepted, "query complete rejects missing rescuer")
	assertEqual(missingRescuerComplete.reason, "rescuer_not_found", "query complete missing rescuer reason")
end

print("rescue_contract_service_runtime_entrypoint: all checks passed")
