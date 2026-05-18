--!strict

Vector3 = Vector3 or {
	new = function(x: number, y: number, z: number)
		return { X = x, Y = y, Z = z, x = x, y = y, z = z }
	end,
}

local MockPlayer = require("../tests/mocks/MockPlayer")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
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
	}

	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end

	function node:WaitForChild(childName: string): any
		return self._Children[childName]
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

	function remote:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "GrabRequest", makeRemoteEvent("GrabRequest"))
addChild(remotesFolder, "PlaceRequest", makeRemoteEvent("PlaceRequest"))
addChild(remotesFolder, "CarriedCounterplayRequest", makeRemoteEvent("CarriedCounterplayRequest"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "GrabConfig", "../../ReplicatedStorage/Shared/Config/GrabConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
addChild(giantRealmFolder, "GrabState", "../../ReplicatedStorage/Shared/GiantRealm/GrabState")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local playersList: { any } = {}
local playerAdded = makeSignal()
local playerRemoving = makeSignal()
local playersService: any = {
	PlayerAdded = playerAdded,
	PlayerRemoving = playerRemoving,
}

function playersService:GetPlayers(): { any }
	return playersList
end

local runService: any = {
	Heartbeat = makeSignal(),
}

local workspaceService: any = {}
function workspaceService:Raycast(_origin: any, _direction: any, _params: any): any
	return nil
end
function workspaceService:GetPartBoundsInBox(_cframe: any, _size: any, _params: any): { any }
	return {}
end

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "RunService" then
		return runService
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error("unsupported service " .. serviceName)
end

game = fakeGame

local giant = MockPlayer.new(1, "GiantPlayer", { role = "Giant", positionZ = 0 })
local tinyfolk = MockPlayer.new(2, "TinyfolkPlayer", { role = "Tinyfolk", positionZ = 4 })
local farTinyfolk = MockPlayer.new(3, "FarTinyfolk", { role = "Tinyfolk", positionZ = 40 })
local safeTinyfolk = MockPlayer.new(4, "SafeTinyfolk", {
	role = "Tinyfolk",
	positionZ = 4,
	inSafeZone = true,
	safeZoneType = "SharedHub",
})
local downedTinyfolk = MockPlayer.new(5, "DownedTinyfolk", { role = "Tinyfolk", positionZ = 5 })
local missingRootTinyfolk = MockPlayer.new(6, "MissingRootTinyfolk", { role = "Tinyfolk", hasRoot = false })
local deadTinyfolk = MockPlayer.new(7, "DeadTinyfolk", { role = "Tinyfolk", health = 0 })
local otherGiant = MockPlayer.new(8, "OtherGiant", { role = "Giant", positionZ = 0 })
playersList = {
	giant,
	tinyfolk,
	farTinyfolk,
	safeTinyfolk,
	downedTinyfolk,
	missingRootTinyfolk,
	deadTinyfolk,
	otherGiant,
}

_G._RoleService_QueryAPI = {
	GetDownedSnapshot = function(userId: number): any
		if userId == downedTinyfolk.UserId then
			return {
				status = "Downed",
				isDowned = true,
				carryEligibleMarker = true,
			}
		end
		return {
			status = "Normal",
			isDowned = false,
			carryEligibleMarker = false,
		}
	end,
}

require("../src/ServerScriptService/Services/GrabService.server")

local grabApi: any = _G._GrabService_QueryAPI
assertTrue(type(grabApi) == "table", "GrabService exposes query API")

do
	local result = grabApi.RequestGrab(giant.UserId, tinyfolk.UserId, 100)
	assertTrue(result.accepted, "valid Giant grab accepted")
	assertEqual(tinyfolk:GetAttribute("CarriedState"), "Carried", "target carried attribute set")
	assertEqual(tinyfolk:GetAttribute("CarriedByUserId"), giant.UserId, "target carrier attribute set")
	assertEqual(giant:GetAttribute("CarriedTargetUserId"), tinyfolk.UserId, "giant target attribute set")
	assertTrue(grabApi.IsPlayerCarried(tinyfolk.UserId), "query marks target carried")
end

do
	local result = grabApi.RequestGrab(otherGiant.UserId, tinyfolk.UserId, 101)
	assertFalse(result.accepted, "already carried target rejected")
	assertEqual(result.reason, "target_already_carried", "already carried target reason")
end

do
	local first = grabApi.RequestCounterplay(tinyfolk.UserId, 102)
	local cooldown = grabApi.RequestCounterplay(tinyfolk.UserId, 102.1)
	local second = grabApi.RequestCounterplay(tinyfolk.UserId, 102.3)
	local third = grabApi.RequestCounterplay(tinyfolk.UserId, 102.6)
	assertTrue(first.accepted, "first counterplay accepted")
	assertFalse(cooldown.accepted, "counterplay cooldown rejected")
	assertEqual(cooldown.reason, "counterplay_cooldown", "counterplay cooldown reason")
	assertTrue(second.accepted, "second counterplay accepted")
	assertTrue(third.accepted, "third counterplay accepted")
	assertFalse(grabApi.IsPlayerCarried(tinyfolk.UserId), "counterplay releases target")
	assertEqual(tinyfolk:GetAttribute("CarriedState"), "Released", "release state attributed")
	assertEqual(tinyfolk:GetAttribute("CarriedReleaseReason"), "counterplay_completed", "release reason attributed")
end

do
	local result = grabApi.RequestGrab(tinyfolk.UserId, downedTinyfolk.UserId, 110)
	assertFalse(result.accepted, "non-Giant caller rejected")
	assertEqual(result.reason, "caller_not_giant", "non-Giant caller reason")
end

do
	local result = grabApi.RequestGrab(otherGiant.UserId, otherGiant.UserId, 111)
	assertFalse(result.accepted, "self target rejected")
	assertEqual(result.reason, "self_target", "self target reason")
end

do
	local result = grabApi.RequestGrab(otherGiant.UserId, farTinyfolk.UserId, 112)
	assertFalse(result.accepted, "out-of-range target rejected")
	assertEqual(result.reason, "target_out_of_range", "out-of-range reason")
end

do
	local result = grabApi.RequestGrab(otherGiant.UserId, safeTinyfolk.UserId, 113)
	assertFalse(result.accepted, "safe-zone target rejected")
	assertEqual(result.reason, "shared_hub_no_capture", "safe-zone policy reason")
end

do
	local result = grabApi.RequestGrab(otherGiant.UserId, missingRootTinyfolk.UserId, 114)
	assertFalse(result.accepted, "missing target root rejected")
	assertEqual(result.reason, "target_root_missing", "missing root reason")
end

do
	local result = grabApi.RequestGrab(otherGiant.UserId, deadTinyfolk.UserId, 115)
	assertFalse(result.accepted, "dead target rejected")
	assertEqual(result.reason, "target_not_alive", "dead target reason")
end

do
	local result = grabApi.RequestGrab(otherGiant.UserId, downedTinyfolk.UserId, 116)
	assertTrue(result.accepted, "downed target can be carried")
	assertEqual(downedTinyfolk:GetAttribute("CarriedState"), "Carried", "downed carried attribute set")
end

do
	playerRemoving:Fire(downedTinyfolk)
	assertFalse(grabApi.IsPlayerCarried(downedTinyfolk.UserId), "target removal clears carried query")
	assertEqual(otherGiant:GetAttribute("CarriedTargetUserId"), nil, "target removal clears carrier target")
	local nextGrab = grabApi.RequestGrab(otherGiant.UserId, tinyfolk.UserId, 120)
	assertTrue(nextGrab.accepted, "carrier can grab again after target removal cleanup")
end

print("grab_service_runtime_entrypoint: all checks passed")
