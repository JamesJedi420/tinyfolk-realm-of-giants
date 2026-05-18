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
target:SetAttribute("DownedIsDowned", true)

local playersList: { any } = { rescuer, target }
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
	setHumanoidHealth(rescuer, 100)
	setHumanoidHealth(target, 100)
	target:SetAttribute("DownedIsDowned", true)
	target:SetAttribute("InSafeZone", false)
	target:SetAttribute("SafeZoneType", nil)
	target:SetAttribute("SafeZoneProtectionEndsAt", nil)
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
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, rescuer.UserId, 500)
	assertFalse(rejected.accepted, "self rescue rejected")
	assertEqual(rejected.reason, "self_rescue_not_allowed", "self rescue rejection reason")
end

print("rescue_contract_service_runtime_entrypoint: all checks passed")
