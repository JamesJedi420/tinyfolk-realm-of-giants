--!nocheck

local MockPlayer = require("../tests/mocks/MockPlayer")
local GiantRealmLoadService = require("../src/ServerScriptService/Services/GiantRealmLoadService")
local GiantRealmLoadState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmLoadState")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function makeSignal()
	local callbacks: { (any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, player: any)
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

	function node.FindFirstChild(_self: any, childName: string): any
		return _self._Children[childName]
	end

	function node.WaitForChild(_self: any, childName: string): any
		return _self._Children[childName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local playersList: { any } = {}
local playerRemoving = makeSignal()
local bindToCloseCallbacks: { () -> () } = {}

local playersService: any = {
	PlayerRemoving = playerRemoving,
	GetPlayers = function(_self: any): { any }
		return playersList
	end,
}

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

function fakeGame:BindToClose(callback: () -> ())
	table.insert(bindToCloseCallbacks, callback)
end

game = fakeGame

local saveCalls = 0
local releaseCalls = 0

GiantRealmLoadService.ResetForTests()
ProfilePersistenceGateway.ResetForTests()

ProfilePersistenceGateway.LoadGiantRealmProfile = function(ownerUserId: number): any
	return {
		ok = true,
		operation = "LoadGiantRealmProfile",
		profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
		data = GiantRealmLoadState.BuildDefaultStarterSaveRoot(ownerUserId),
		meta = {
			loadOutcome = GiantRealmLoadState.LoadOutcome.CreatedDefault,
		},
	}
end

ProfilePersistenceGateway.SaveGiantRealmProfile = function(_ownerUserId: number): any
	saveCalls += 1
	return {
		ok = true,
		operation = "SaveGiantRealmProfile",
	}
end

ProfilePersistenceGateway.ReleaseGiantRealmProfile = function(_ownerUserId: number): any
	releaseCalls += 1
	return {
		ok = true,
		operation = "ReleaseGiantRealmProfile",
	}
end

require("../src/ServerScriptService/Services/GiantRealmLoadService.server")

local ownerUserId = 9601
local loadResult = GiantRealmLoadService.LoadAndInitialize(ownerUserId)
assertTrue(loadResult.accepted == true, "server bootstrap load accepted")

local giant = MockPlayer.new(ownerUserId, "GiantOwner", {
	role = RoleConfig.Roles.Giant,
})
playersList = { giant }

playerRemoving:Fire(giant)
assertEqual(saveCalls, 1, "player removing saves loaded realm")
assertEqual(releaseCalls, 1, "player removing releases loaded realm")
assertTrue(GiantRealmLoadService.IsRealmLoaded(ownerUserId) == false, "player removing clears loaded registry")

local secondOwnerUserId = 9602
local secondLoad = GiantRealmLoadService.LoadAndInitialize(secondOwnerUserId)
assertTrue(secondLoad.accepted == true, "second realm load accepted")
saveCalls = 0
releaseCalls = 0

assertEqual(#bindToCloseCallbacks, 1, "load service server binds shutdown cleanup")
bindToCloseCallbacks[1]()
assertEqual(saveCalls, 1, "bind to close saves remaining loaded realm")
assertEqual(releaseCalls, 1, "bind to close releases remaining loaded realm")
assertTrue(GiantRealmLoadService.IsRealmLoaded(secondOwnerUserId) == false, "bind to close clears loaded registry")

print("giant_realm_load_service_server_runtime_entrypoint: all checks passed")
