--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
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
	}

	function player.SetAttribute(_self: any, attributeName: string, value: any)
		attributes[attributeName] = value
	end

	function player.GetAttribute(_self: any, attributeName: string): any
		return attributes[attributeName]
	end

	function player.LoadCharacter(_self: any)
		return
	end

	function player.LoadCharacterAsync(_self: any)
		return
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

local playerTinyfolk = makePlayer(7001)
playerTinyfolk:SetAttribute("Role", "Tinyfolk")

local playersList = {
	playerTinyfolk,
}

local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerAdded = makeSignal(),
	PlayerRemoving = makeSignal(),
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
	if serviceName == "RunService" then
		return {
			IsStudio = function()
				return true
			end,
		}
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

function fakeGame:BindToClose(_callback: () -> ())
	return
end

game = fakeGame

_G._GrabService_QueryAPI = {
	IsPlayerCarried = function(_userId: number): boolean
		return false
	end,
}

_G._ProfilePersistenceLifecycle_QueryAPI = {
	IsPlayerOwnershipReady = function(_userId: number): boolean
		return true
	end,
	RegisterOwnershipReadyCallback = function(_userId: number, _callback: any): boolean
		return true
	end,
}

_G._ProfileTeleportHandoffService_QueryAPI = {
	CanSpawnGameplayForUserId = function(_userId: number): boolean
		return true
	end,
	RegisterReleaseReadyCallback = function(_userId: number, _callback: any): boolean
		return true
	end,
}

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
ProfilePersistenceGateway.ResetForTests()

ProfilePersistenceGateway.GetLoadedPlayerProfileData = function(_player: any): any
	return {
		ok = true,
		operation = "GetLoadedPlayerProfileData",
		data = {
			schemaVersion = 1,
			userId = 7001,
		},
	}
end

ProfilePersistenceGateway.UpdateLoadedPlayerProfileData = function(_player: any, updater: any): any
	local newData = updater({ schemaVersion = 1, userId = 7001 })
	return {
		ok = type(newData) == "table",
		operation = "UpdateLoadedPlayerProfileData",
		data = newData,
	}
end

ProfilePersistenceGateway.LoadGiantRealmProfile = function(_ownerUserId: number): any
	return { ok = true, operation = "LoadGiantRealmProfile", data = { schemaVersion = 1, placedStructures = {} } }
end

ProfilePersistenceGateway.SaveGiantRealmProfile = function(_ownerUserId: number): any
	return { ok = true, operation = "SaveGiantRealmProfile" }
end

ProfilePersistenceGateway.ReleaseGiantRealmProfile = function(_ownerUserId: number): any
	return { ok = true, operation = "ReleaseGiantRealmProfile" }
end

local capturedOutcomeInputs: { any } = {}
local capturedReconnectInputs: { any } = {}
local allowSessionRuntimeByOutcome: { [string]: boolean } = {
	capture = false,
	escape = true,
	defense = true,
	["return"] = true,
}
local reconnectAction = "reapply_session_runtime"

ProfilePersistenceGateway.ResolveEventOutcomeWriteBack = function(input: any): any
	table.insert(capturedOutcomeInputs, input)
	local outcome = if type(input) == "table" then input.outcome else nil
	local allowSessionRuntime = allowSessionRuntimeByOutcome[tostring(outcome)] == true
	return {
		accepted = true,
		reason = "accepted",
		scopes = {
			playerProfile = false,
			realmProfile = false,
			sessionRuntime = allowSessionRuntime,
		},
		sessionAction = "test_action",
	}
end

ProfilePersistenceGateway.ResolveReconnectRestoreAction = function(input: any): any
	table.insert(capturedReconnectInputs, input)
	if reconnectAction == "clear_session_runtime" then
		return {
			accepted = true,
			reason = "from_test_clear",
			action = "clear_session_runtime",
			reapplySessionRuntime = false,
			clearSessionRuntime = true,
		}
	end

	return {
		accepted = true,
		reason = "from_test_reapply",
		action = "reapply_session_runtime",
		reapplySessionRuntime = true,
		clearSessionRuntime = false,
	}
end

require("../src/ServerScriptService/Services/RoleService.server")
local roleServiceQueryApi: any = _G._RoleService_QueryAPI
assertTrue(type(roleServiceQueryApi) == "table", "RoleService query API exists")

local rejectedCapture = roleServiceQueryApi.SetDowned(playerTinyfolk.UserId, 30, "capture_test")
assertEqual(rejectedCapture, false, "setDowned rejected when outcome scope blocks session runtime")
assertEqual(#capturedOutcomeInputs, 1, "outcome routing called for rejected capture")
assertEqual(capturedOutcomeInputs[1].outcome, "capture", "capture reason maps to capture outcome")

allowSessionRuntimeByOutcome.capture = true
local acceptedCapture = roleServiceQueryApi.SetDowned(playerTinyfolk.UserId, 30, "capture_test")
assertEqual(acceptedCapture, true, "setDowned accepted when outcome scope allows session runtime")
local downedSnapshot = roleServiceQueryApi.GetDownedSnapshot(playerTinyfolk.UserId)
assertEqual(downedSnapshot.isDowned, true, "accepted routing enters downed session runtime")

reconnectAction = "reapply_session_runtime"
local reapplyResult = roleServiceQueryApi.ResolveDownedReconnectRouting(playerTinyfolk.UserId, {
	phase = "active",
	expectedSessionId = "s1",
	activeSessionId = "s1",
	hasSessionRuntime = true,
})
assertEqual(reapplyResult.action, "reapply_session_runtime", "reconnect routing returns reapply action")
assertEqual(
	roleServiceQueryApi.GetDownedSnapshot(playerTinyfolk.UserId).isDowned,
	true,
	"reapply action keeps downed state"
)

reconnectAction = "clear_session_runtime"
local clearResult = roleServiceQueryApi.ResolveDownedReconnectRouting(playerTinyfolk.UserId, {
	phase = "active",
	expectedSessionId = "s1",
	activeSessionId = "s2",
	hasSessionRuntime = true,
})
assertEqual(clearResult.action, "clear_session_runtime", "reconnect routing returns clear action")
assertEqual(
	roleServiceQueryApi.GetDownedSnapshot(playerTinyfolk.UserId).isDowned,
	false,
	"clear action resets downed state"
)
assertTrue(#capturedReconnectInputs >= 2, "reconnect resolver input captured")

print("role_service_event_routing_runtime_entrypoint: all checks passed")
