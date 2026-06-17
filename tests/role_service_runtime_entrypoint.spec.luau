--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
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

local cloneTable: (any) -> any
cloneTable = function(value: any): any
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
	for i = 1, select("#", ...) do
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
		local childAny = child :: any
		childAny.Parent = parent
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

	function player.SetAttribute(_self: any, attributeName: string, value: any)
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
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(configFolder, "TinyfolkHubConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkHubConfig")

local tinyfolkHubFolder = makeNode("TinyfolkHub", "Folder", "ReplicatedStorage.Shared.TinyfolkHub")
addChild(tinyfolkHubFolder, "TinyfolkHubState", "../../ReplicatedStorage/Shared/TinyfolkHub/TinyfolkHubState")

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "TinyfolkHub", tinyfolkHubFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local spawnsFolder = makeNode("Spawns", "Folder", "Workspace.Map.Spawns")
local tinyfolkWorldFolder = makeNode("TinyfolkWorld", "Folder", "Workspace.Map.TinyfolkWorld")
local tinyfolkReturnPoint: any = {
	Name = "TinyfolkReturnPoint",
	ClassName = "Part",
	CFrame = {
		Position = {
			X = 42,
			Y = 5,
			Z = 17,
		},
	},
}
function tinyfolkReturnPoint:IsA(expectedClass: string): boolean
	return expectedClass == "BasePart" or expectedClass == "Part"
end
addChild(mapFolder, "Spawns", spawnsFolder)
addChild(mapFolder, "TinyfolkWorld", tinyfolkWorldFolder)
addChild(tinyfolkWorldFolder, "TinyfolkReturnPoint", tinyfolkReturnPoint)
addChild(workspaceService, "Map", mapFolder)

local playerStoredGiant = makePlayer(1001)
local playerNoStored = makePlayer(1002)
local playerInvalidStored = makePlayer(1003)
local playerReadFailure = makePlayer(1004)
local playerUpdateOk = makePlayer(2001)
local playerUpdateFail = makePlayer(2002)
local playerRealmLoadFail = makePlayer(2003)
local playerRealmSaveFail = makePlayer(2004)
local playerOwnershipBlocked = makePlayer(2005)
local playerLoadFailureFallback = makePlayer(2006)
local playerReconnectSafe = makePlayer(3001)

local playersList = {
	playerStoredGiant,
	playerNoStored,
	playerInvalidStored,
	playerReadFailure,
	playerUpdateOk,
	playerUpdateFail,
	playerRealmLoadFail,
	playerRealmSaveFail,
	playerOwnershipBlocked,
	playerLoadFailureFallback,
	playerReconnectSafe,
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
local bindToCloseCallbacks: { () -> () } = {}
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

function fakeGame:BindToClose(callback: () -> ())
	table.insert(bindToCloseCallbacks, callback)
end

game = fakeGame
local carriedByUserId: { [number]: boolean } = {}
_G._GrabService_QueryAPI = {
	IsPlayerCarried = function(userId: number): boolean
		return carriedByUserId[userId] == true
	end,
}

local ownershipReadyByUserId: { [number]: boolean } = {
	[1001] = true,
	[1002] = true,
	[1003] = true,
	[1004] = true,
	[2001] = true,
	[2002] = true,
	[2003] = true,
	[2004] = true,
	[2005] = true,
	[3001] = true,
}
local loadFailureRouteByUserId: { [number]: string? } = {}
local ownershipCallbacksByUserId: { [number]: { (boolean, string?) -> () } } = {}
_G._ProfilePersistenceLifecycle_QueryAPI = {
	IsPlayerOwnershipReady = function(userId: number): boolean
		return ownershipReadyByUserId[userId] == true
	end,
	GetLoadFailureRoute = function(userId: number): string?
		return loadFailureRouteByUserId[userId]
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
		return true
	end,
}

local teleportSpawnReadyByUserId: { [number]: boolean } = {
	[2005] = false,
}
local teleportReleaseReadyCallbacksByUserId: { [number]: { (any) -> () } } = {}
_G._ProfileTeleportHandoffService_QueryAPI = {
	CanSpawnGameplayForUserId = function(userId: number): boolean
		local ready = teleportSpawnReadyByUserId[userId]
		if ready == nil then
			return true
		end
		return ready == true
	end,
	RegisterReleaseReadyCallback = function(userId: number, callback: any): boolean
		if type(callback) ~= "function" then
			return false
		end

		local callbacks = teleportReleaseReadyCallbacksByUserId[userId]
		if callbacks == nil then
			callbacks = {}
			teleportReleaseReadyCallbacksByUserId[userId] = callbacks
		end

		table.insert(callbacks, callback)
		return true
	end,
}

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
	[2003] = {
		schemaVersion = 1,
		userId = 2003,
	},
	[2004] = {
		schemaVersion = 1,
		userId = 2004,
	},
	[2005] = {
		schemaVersion = 1,
		userId = 2005,
	},
	[3001] = {
		schemaVersion = 1,
		userId = 3001,
		safeLocation = {
			returnPointName = "TinyfolkReturnPoint",
			returnedAt = 5,
			returnReason = "logout",
		},
	},
}

local readFailureByUserId: { [number]: boolean } = {
	[1004] = true,
}

local updateFailureByUserId: { [number]: boolean } = {
	[2002] = true,
}

local updateCallCountByUserId: { [number]: number } = {}
local realmLoadFailureByUserId: { [number]: boolean } = {
	[2003] = true,
}
local realmSaveFailureByUserId: { [number]: boolean } = {
	[2004] = true,
}
local realmLoadCallCountByUserId: { [number]: number } = {}
local realmSaveCallCountByUserId: { [number]: number } = {}
local realmReleaseCallCountByUserId: { [number]: number } = {}

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

ProfilePersistenceGateway.LoadGiantRealmProfile = function(ownerUserId: number): any
	realmLoadCallCountByUserId[ownerUserId] = (realmLoadCallCountByUserId[ownerUserId] or 0) + 1
	if realmLoadFailureByUserId[ownerUserId] == true then
		return {
			ok = false,
			operation = "LoadGiantRealmProfile",
			reason = "realm_load_failed_for_test",
			profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
		}
	end

	return {
		ok = true,
		operation = "LoadGiantRealmProfile",
		profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
		data = {
			schemaVersion = 1,
			ownerUserId = ownerUserId,
			placedStructures = {},
		},
	}
end

ProfilePersistenceGateway.SaveGiantRealmProfile = function(ownerUserId: number): any
	realmSaveCallCountByUserId[ownerUserId] = (realmSaveCallCountByUserId[ownerUserId] or 0) + 1
	if realmSaveFailureByUserId[ownerUserId] == true then
		return {
			ok = false,
			operation = "SaveGiantRealmProfile",
			reason = "realm_save_failed_for_test",
			profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
		}
	end

	return {
		ok = true,
		operation = "SaveGiantRealmProfile",
		profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
	}
end

ProfilePersistenceGateway.ReleaseGiantRealmProfile = function(ownerUserId: number): any
	realmReleaseCallCountByUserId[ownerUserId] = (realmReleaseCallCountByUserId[ownerUserId] or 0) + 1
	return {
		ok = true,
		operation = "ReleaseGiantRealmProfile",
		profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
	}
end

require("../src/ServerScriptService/Services/RoleService.server")

local roleServiceQueryApi: any = _G._RoleService_QueryAPI
assertTrue(type(roleServiceQueryApi) == "table", "RoleService exposes query API")

assertEqual(playersService.CharacterAutoLoads, false, "RoleService sets Players.CharacterAutoLoads false")
assertEqual(#bindToCloseCallbacks, 1, "RoleService binds shutdown cleanup")

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
assertEqual(realmLoadCallCountByUserId[2001], 1, "accepted Giant role loads realm profile")
assertEqual(
	roleServiceQueryApi.GetActiveGiantRealmOwnerUserId(),
	2001,
	"accepted Giant role projects active realm owner query"
)
assertEqual(playerNoStored:GetAttribute("GiantRealmOwnerUserId"), 2001, "active realm owner projects to Tinyfolk")
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
assertEqual(realmLoadCallCountByUserId[2002], nil, "accepted Tinyfolk role does not load realm profile")
assertEqual(
	playerUpdateFail:GetAttribute("GiantRealmOwnerUserId"),
	2001,
	"Tinyfolk role keeps projected active realm owner"
)
assertTrue(sawWarnContaining("Role preference update failed userId=2002"), "update failure warning emitted")

roleChangeRemote:FireServer(playerRealmLoadFail, RoleConfig.Roles.Giant)
assertEqual(
	playerRealmLoadFail:GetAttribute("Role"),
	RoleConfig.Roles.Giant,
	"realm load failure still sets Giant role"
)
assertEqual(playerRealmLoadFail.loadCharacterCount, 1, "realm load failure still respawns player")
assertEqual(realmLoadCallCountByUserId[2003], 1, "realm load failure attempted once")
assertEqual(
	roleServiceQueryApi.GetActiveGiantRealmOwnerUserId(),
	2001,
	"failed realm load does not replace active realm owner"
)
assertTrue(sawWarnContaining("Giant realm load failed userId=2003"), "realm load failure warning emitted")

roleChangeRemote:FireServer(playerRealmSaveFail, RoleConfig.Roles.Giant)
assertEqual(
	playerRealmSaveFail:GetAttribute("Role"),
	RoleConfig.Roles.Giant,
	"realm save failure setup sets Giant role"
)
assertEqual(realmLoadCallCountByUserId[2004], 1, "realm save failure setup loads realm")
assertEqual(
	roleServiceQueryApi.GetActiveGiantRealmOwnerUserId(),
	2004,
	"second loaded Giant becomes active realm owner"
)

roleChangeRemote:FireServer(playerOwnershipBlocked, RoleConfig.Roles.Tinyfolk)
assertEqual(
	playerOwnershipBlocked:GetAttribute("Role"),
	RoleConfig.Roles.Tinyfolk,
	"ownership-blocked role selection still sets active role"
)
assertEqual(playerOwnershipBlocked.loadCharacterCount, 0, "ownership-blocked player spawn is deferred")
assertTrue(sawWarnContaining("Role select spawn deferred userId=2005"), "ownership deferral warning emitted")

ownershipReadyByUserId[2005] = true
local ownershipCallbacks = ownershipCallbacksByUserId[2005]
assertTrue(type(ownershipCallbacks) == "table" and #ownershipCallbacks > 0, "ownership callback registered")
for _, callback in ipairs(ownershipCallbacks :: { (boolean, string?) -> () }) do
	callback(true, nil)
end
assertEqual(
	playerOwnershipBlocked.loadCharacterCount,
	0,
	"teleport-blocked player stays deferred after ownership callback"
)

teleportSpawnReadyByUserId[2005] = true
local teleportCallbacks = teleportReleaseReadyCallbacksByUserId[2005]
assertTrue(type(teleportCallbacks) == "table" and #teleportCallbacks > 0, "teleport release-ready callback registered")
for _, callback in ipairs(teleportCallbacks :: { (any) -> () }) do
	callback({ ok = true, handoffToken = "test-token" })
end
assertEqual(playerOwnershipBlocked.loadCharacterCount, 1, "teleport callback resumes blocked spawn")

loadFailureRouteByUserId[2006] = "safe_fallback"
roleChangeRemote:FireServer(playerLoadFailureFallback, RoleConfig.Roles.Tinyfolk)
assertEqual(
	playerLoadFailureFallback:GetAttribute("Role"),
	RoleConfig.Roles.Tinyfolk,
	"load-failure fallback still sets active role"
)
assertEqual(playerLoadFailureFallback.loadCharacterCount, 1, "load-failure fallback spawns without profile ownership")
assertTrue(
	sawWarnContaining("Spawn routed to safe fallback userId=2006 trigger=role_select"),
	"load-failure fallback spawn warning emitted"
)

playerRemoving:Fire(playerRealmSaveFail)
assertEqual(realmSaveCallCountByUserId[2004], 1, "save failure Giant still attempts save")
assertEqual(realmReleaseCallCountByUserId[2004], 1, "save failure Giant still releases realm")
assertEqual(
	roleServiceQueryApi.GetActiveGiantRealmOwnerUserId(),
	2001,
	"removing active Giant falls back to remaining loaded realm owner"
)
assertEqual(playerUpdateFail:GetAttribute("GiantRealmOwnerUserId"), 2001, "active realm owner projection falls back")
assertTrue(sawWarnContaining("Giant realm save failed userId=2004"), "realm save failure warning emitted")

playerRemoving:Fire(playerRealmLoadFail)
assertEqual(realmSaveCallCountByUserId[2003], nil, "removing failed-load Giant does not save realm")
assertEqual(realmReleaseCallCountByUserId[2003], nil, "removing failed-load Giant does not release realm")

playerRemoving:Fire(playerUpdateOk)
assertEqual(realmSaveCallCountByUserId[2001], 1, "removing loaded Giant saves realm")
assertEqual(realmReleaseCallCountByUserId[2001], 1, "removing loaded Giant releases realm")
assertEqual(
	roleServiceQueryApi.GetActiveGiantRealmOwnerUserId(),
	nil,
	"removing active Giant clears active realm owner"
)
assertEqual(playerUpdateFail:GetAttribute("GiantRealmOwnerUserId"), nil, "active realm owner projection clears")

bindToCloseCallbacks[1]()
assertEqual(realmSaveCallCountByUserId[2001], 1, "shutdown does not resave removed Giant")
assertEqual(realmReleaseCallCountByUserId[2001], 1, "shutdown does not rerelease removed Giant")
assertEqual(realmSaveCallCountByUserId[2004], 1, "shutdown does not resave save-failure removed Giant")
assertEqual(realmReleaseCallCountByUserId[2004], 1, "shutdown does not rerelease save-failure removed Giant")

playerNoStored:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
local downAccepted = roleServiceQueryApi.SetDowned(playerNoStored.UserId, 30, "runtime_test_downed")
assertEqual(downAccepted, true, "Tinyfolk can enter downed state via query API")
assertEqual(playerNoStored:GetAttribute("DownedState"), "Downed", "downed attribute set")
assertEqual(playerNoStored:GetAttribute("DownedIsDowned"), true, "downed marker set")
assertEqual(
	roleServiceQueryApi.CanPlayerPerformInteraction(playerNoStored.UserId, "escapeAttempt"),
	false,
	"escape interaction restricted while downed"
)

carriedByUserId[playerNoStored.UserId] = true
local carriedSelfRecoverRejected = roleServiceQueryApi.SelfRecoverDowned(playerNoStored.UserId, 0.2)
assertEqual(carriedSelfRecoverRejected, false, "self recovery while carried rejected")
assertEqual(playerNoStored:GetAttribute("DownedSelfRecoveryProgress"), 0, "carried self recovery does not progress")
carriedByUserId[playerNoStored.UserId] = nil

local selfRecoverAccepted = roleServiceQueryApi.SelfRecoverDowned(playerNoStored.UserId, 0.7)
assertEqual(selfRecoverAccepted, true, "self recovery request accepted")
assertEqual(playerNoStored:GetAttribute("DownedState"), "SelfRecoveryCapped", "self recovery clamps at cap")

local downedSnapshot = roleServiceQueryApi.GetDownedSnapshot(playerNoStored.UserId)
roleServiceQueryApi.TickDownedStates((downedSnapshot.expiresAt or 0) + 1)
assertEqual(playerNoStored:GetAttribute("DownedState"), "SafeResolved", "downed state expires safely")
assertEqual(playerNoStored:GetAttribute("DownedIsDowned"), false, "expired downed marker clears")

playerStoredGiant:SetAttribute("Role", RoleConfig.Roles.Giant)
local giantDownRejected = roleServiceQueryApi.SetDowned(playerStoredGiant.UserId, 30, "runtime_test_invalid_role")
assertEqual(giantDownRejected, false, "non-Tinyfolk cannot enter downed state")

local reconnectPivot: any = nil
local reconnectRoot: any = {
	Name = "HumanoidRootPart",
	ClassName = "Part",
}
function reconnectRoot:IsA(expectedClass: string): boolean
	return expectedClass == "BasePart" or expectedClass == "Part"
end
local reconnectCharacter: any = {
	Name = "ReconnectCharacter",
	ClassName = "Model",
}
function reconnectCharacter:FindFirstChildOfClass(className: string): any
	if className == "Humanoid" then
		return {
			Health = 100,
			Died = {
				Connect = function(_self: any, _callback: () -> ())
					return {}
				end,
			},
		}
	end
	return nil
end
function reconnectCharacter:FindFirstChild(childName: string): any
	if childName == "HumanoidRootPart" then
		return reconnectRoot
	end
	return nil
end
function reconnectCharacter:WaitForChild(childName: string, _timeout: number?): any
	return self:FindFirstChild(childName)
end
function reconnectCharacter:ScaleTo(_scale: number) end
function reconnectCharacter:PivotTo(targetPivot: any)
	reconnectPivot = targetPivot
end
playerReconnectSafe:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
playerReconnectSafe.Character = reconnectCharacter
playerReconnectSafe.CharacterAdded:Fire(reconnectCharacter)
assertTrue(reconnectPivot ~= nil, "reconnect safe location pivots character")
assertEqual(reconnectPivot, tinyfolkReturnPoint.CFrame, "reconnect safe location uses return point pivot")
assertTrue(profileDataByUserId[3001].safeLocation == nil, "reconnect safe location clears persisted snapshot")

print("role_service_runtime_entrypoint: all checks passed")

local MatchSimulation: any = require("../tests/harness/MatchSimulation")

do
	local sim = MatchSimulation.new({ clock = os.clock })
	sim:addPlayer(1, "PlayerOne", { role = "Tinyfolk" })

	sim:queueAction(1, "assignRole", {
		userId = 1,
		role = "Giant",
	})

	sim:advanceTick()

	local log = sim:getLog()
	assertEqual(log[2], "[Tick 1] Assigned role Giant to player PlayerOne", "Role assignment succeeds")
end
