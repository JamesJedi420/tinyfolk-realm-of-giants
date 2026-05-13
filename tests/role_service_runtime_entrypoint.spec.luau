--!strict

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[key] = cloneTable(child)
	end
	return result
end

local warns: { string } = {}
local originalWarn = warn
warn = function(...: any)
	local packed = table.pack(...)
	local parts: { string } = {}
	for i = 1, packed.n :: number do
		table.insert(parts, tostring(packed[i]))
	end
	local line = table.concat(parts, " ")
	table.insert(warns, line)
	originalWarn(...)
end

local function sawWarnContaining(fragment: string): boolean
	for _, line in ipairs(warns) do
		if string.find(line, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
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

local function makeNode(name: string, className: string?, fullName: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_FullName = fullName or name,
		_Children = {},
		_Attributes = {},
		Parent = nil,
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.GetFullName(self: any): string
		return self._FullName
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string, _timeout: number?): any
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
	if type(child) == "table" then
		child.Parent = parent
	end
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
		_ClientPayload = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (Player, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireServer(self: any, player: Player, payload: any)
		if self._Handler == nil then
			error(string.format("remote %s handler not connected", self.Name))
		end
		self._Handler(player, payload)
	end

	function remote.FireClient(self: any, _player: Player, payload: any)
		self._ClientPayload = payload
	end

	return remote
end

local function makePlayer(userId: number)
	local attributes: { [string]: any } = {}
	local characterAdded = makeSignal()
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
		Character = nil,
		CharacterAdded = characterAdded,
		loadCharacterCount = 0,
		loadCharacterAsyncCount = 0,
	}

	function player.SetAttribute(self: any, attributeName: string, value: any)
		attributes[attributeName] = value
	end

	function player.GetAttribute(_self: any, attributeName: string): any
		return attributes[attributeName]
	end

	function player.LoadCharacter(self: any)
		self.loadCharacterCount += 1
	end

	function player.LoadCharacterAsync(self: any)
		self.loadCharacterAsyncCount += 1
	end

	return player
end

local roleChangeRemote = makeRemoteEvent("RoleChangeRequest")
local roleDebugRequestRemote = makeRemoteEvent("RoleDebugStateRequest")
local roleDebugResponseRemote = makeRemoteEvent("RoleDebugStateResponse")

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
addChild(remotesFolder, "RoleChangeRequest", roleChangeRemote)
addChild(remotesFolder, "RoleDebugStateRequest", roleDebugRequestRemote)
addChild(remotesFolder, "RoleDebugStateResponse", roleDebugResponseRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local spawnsFolder = makeNode("Spawns", "Folder", "Workspace.Map.Spawns")
addChild(mapFolder, "Spawns", spawnsFolder)
addChild(workspaceService, "Map", mapFolder)

local playerStoredGiant = makePlayer(1001)
local playerNoStored = makePlayer(1002)
local playerInvalidStored = makePlayer(1003)
local playerReadFailure = makePlayer(1004)
local playerUpdateOk = makePlayer(2001)
local playerUpdateFail = makePlayer(2002)

local playersList = {
	playerStoredGiant,
	playerNoStored,
	playerInvalidStored,
	playerReadFailure,
	playerUpdateOk,
	playerUpdateFail,
}

local playerAdded = makeSignal()
local playerRemoving = makeSignal()

local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerAdded = playerAdded,
	PlayerRemoving = playerRemoving,
	RespawnTime = 0,
	CharacterAutoLoads = true,
}

function playersService:GetPlayers(): { Player }
	return playersList
end

function playersService:FindFirstChild(name: string): Player?
	for _, player in ipairs(playersList) do
		if player.Name == name then
			return player
		end
	end
	return nil
end

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
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")

local profileDataByUserId: { [number]: any } = {
	[1001] = {
		schemaVersion = 1,
		userId = 1001,
		rolePreference = {
			preferredRole = RoleConfig.Roles.Giant,
		},
	},
	[1002] = {
		schemaVersion = 1,
		userId = 1002,
	},
	[1003] = {
		schemaVersion = 1,
		userId = 1003,
		rolePreference = {
			preferredRole = "NotARealRole",
		},
	},
	[2001] = {
		schemaVersion = 1,
		userId = 2001,
	},
	[2002] = {
		schemaVersion = 1,
		userId = 2002,
	},
}

local readFailureByUserId: { [number]: boolean } = {
	[1004] = true,
}

local updateFailureByUserId: { [number]: boolean } = {
	[2002] = true,
}

local updateCallCountByUserId: { [number]: number } = {}

ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.GetLoadedPlayerProfileData = function(player: any): any
	if readFailureByUserId[player.UserId] == true then
		return {
			ok = false,
			operation = "GetLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	local data = profileDataByUserId[player.UserId]
	if type(data) ~= "table" then
		return {
			ok = false,
			operation = "GetLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	return {
		ok = true,
		operation = "GetLoadedPlayerProfileData",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
		data = cloneTable(data),
	}
end

ProfilePersistenceGateway.UpdateLoadedPlayerProfileData = function(player: any, updater: any): any
	if updateFailureByUserId[player.UserId] == true then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	local activeData = profileDataByUserId[player.UserId]
	if type(activeData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	if type(updater) ~= "function" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "profile_update_updater_invalid",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	local updateOk, newData = pcall(updater, cloneTable(activeData))
	if not updateOk or type(newData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "profile_update_failed",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	profileDataByUserId[player.UserId] = cloneTable(newData)
	updateCallCountByUserId[player.UserId] = (updateCallCountByUserId[player.UserId] or 0) + 1

	return {
		ok = true,
		operation = "UpdateLoadedPlayerProfileData",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
		data = cloneTable(profileDataByUserId[player.UserId]),
	}
end

require("../src/ServerScriptService/Services/RoleService.server")

assertEqual(playersService.CharacterAutoLoads, false, "RoleService sets Players.CharacterAutoLoads false")

assertEqual(
	playerStoredGiant:GetAttribute("SelectedRole"),
	RoleConfig.Roles.Giant,
	"stored Giant preference restores SelectedRole"
)
assertEqual(playerStoredGiant:GetAttribute("RoleLocked"), false, "stored preference keeps RoleLocked false on setup")
assertEqual(playerStoredGiant:GetAttribute("Role"), nil, "stored preference does not set active role on setup")

assertEqual(playerNoStored:GetAttribute("SelectedRole"), nil, "missing preference falls back to default SelectedRole")
assertEqual(playerNoStored:GetAttribute("RoleLocked"), false, "missing preference keeps RoleLocked false")
assertEqual(playerNoStored:GetAttribute("Role"), nil, "missing preference keeps active role nil")

assertEqual(playerInvalidStored:GetAttribute("SelectedRole"), nil, "invalid stored preference ignored")
assertEqual(playerInvalidStored:GetAttribute("RoleLocked"), false, "invalid stored preference keeps RoleLocked false")
assertTrue(sawWarnContaining("reason=invalid_preferred_role"), "invalid preference warning emitted")

assertEqual(playerReadFailure:GetAttribute("SelectedRole"), nil, "read failure falls back to default SelectedRole")
assertEqual(playerReadFailure:GetAttribute("RoleLocked"), false, "read failure keeps RoleLocked false")
assertTrue(sawWarnContaining("Role preference read failed userId=1004"), "read failure warning emitted")

roleChangeRemote:FireServer(playerUpdateOk, RoleConfig.Roles.Giant)
assertEqual(playerUpdateOk:GetAttribute("SelectedRole"), RoleConfig.Roles.Giant, "accepted role sets SelectedRole")
assertEqual(playerUpdateOk:GetAttribute("RoleLocked"), true, "accepted role keeps lock behavior unchanged")
assertEqual(playerUpdateOk:GetAttribute("Role"), RoleConfig.Roles.Giant, "accepted role sets active role")
assertEqual(playerUpdateOk.loadCharacterCount, 1, "accepted role respawns player")
assertEqual(updateCallCountByUserId[2001], 1, "accepted role updates profile via gateway")
assertEqual(
	profileDataByUserId[2001].rolePreference.preferredRole,
	RoleConfig.Roles.Giant,
	"accepted role persists preferredRole"
)

roleChangeRemote:FireServer(playerUpdateFail, RoleConfig.Roles.Tinyfolk)
assertEqual(
	playerUpdateFail:GetAttribute("SelectedRole"),
	RoleConfig.Roles.Tinyfolk,
	"update failure still accepts role selection"
)
assertEqual(playerUpdateFail:GetAttribute("RoleLocked"), true, "update failure keeps lock behavior unchanged")
assertEqual(playerUpdateFail:GetAttribute("Role"), RoleConfig.Roles.Tinyfolk, "update failure still sets active role")
assertEqual(playerUpdateFail.loadCharacterCount, 1, "update failure still respawns player")
assertEqual(updateCallCountByUserId[2002], nil, "failed update does not mutate profile snapshot")
assertTrue(sawWarnContaining("Role preference update failed userId=2002"), "update failure warning emitted")

print("role_service_runtime_entrypoint: all checks passed")
