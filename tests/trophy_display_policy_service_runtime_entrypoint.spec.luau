--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
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
		Parent = nil,
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

	return node
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
		_LastClientPayload = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (...any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireClient(_self: any, _player: any, payload: any)
		remote._LastClientPayload = payload
	end

	return remote
end

local profileDataByUserId: { [number]: any } = {}

local ownerLayer = {
	LoadPlayerProfile = function(_profileKey: string, userId: number): any
		local data = profileDataByUserId[userId]
		if type(data) ~= "table" then
			data = ProfilePersistenceGateway.LoadDefaultPlayerProfile(userId).data
			profileDataByUserId[userId] = cloneTable(data)
		end
		return {
			ok = true,
			operation = "LoadPlayerProfile",
			data = cloneTable(profileDataByUserId[userId]),
		}
	end,
	SavePlayerProfile = function(_profileKey: string, userId: number, data: any): any
		profileDataByUserId[userId] = cloneTable(data)
		return { ok = true, operation = "SavePlayerProfile" }
	end,
	ReleasePlayerProfile = function(): any
		return { ok = true, operation = "ReleasePlayerProfile" }
	end,
	LoadGiantRealmProfile = function(): any
		return { ok = true, operation = "LoadGiantRealmProfile", data = {} }
	end,
	SaveGiantRealmProfile = function(): any
		return { ok = true, operation = "SaveGiantRealmProfile" }
	end,
	ReleaseGiantRealmProfile = function(): any
		return { ok = true, operation = "ReleaseGiantRealmProfile" }
	end,
}

ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.ConfigureOwnerLayer(ownerLayer)

local configFolder = makeNode("Config")
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["TrophyConfig"] = "../../ReplicatedStorage/Shared/Config/TrophyConfig"

local giantRealmFolder = makeNode("GiantRealm")
giantRealmFolder._Children["TrophyDisplayPolicyProfileState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/TrophyDisplayPolicyProfileState"

local sharedFolder = makeNode("Shared")
sharedFolder._Children["Config"] = configFolder
sharedFolder._Children["GiantRealm"] = giantRealmFolder

local remotesFolder = makeNode("Remotes")
local updateRequestRemote = makeRemoteEvent("TrophyDisplayPolicyUpdateRequest")
local updateResponseRemote = makeRemoteEvent("TrophyDisplayPolicyUpdateResponse")
remotesFolder._Children["TrophyDisplayPolicyUpdateRequest"] = updateRequestRemote
remotesFolder._Children["TrophyDisplayPolicyUpdateResponse"] = updateResponseRemote

local replicatedStorage = makeNode("ReplicatedStorage")
replicatedStorage._Children["Shared"] = sharedFolder
replicatedStorage._Children["Remotes"] = remotesFolder

local function makePlayer(userId: number, role: string): any
	return {
		UserId = userId,
		_Attributes = {
			Role = role,
		},
		_RoleChangedSignal = makeSignal(),
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
		GetAttributeChangedSignal = function(self: any, attributeName: string): any
			if attributeName == "Role" then
				return self._RoleChangedSignal
			end
			return makeSignal()
		end,
	}
end

local tinyfolkPlayer = makePlayer(5101, "Tinyfolk")
local giantPlayer = makePlayer(5001, "Giant")
local playersList = { tinyfolkPlayer, giantPlayer }
local playerAddedSignal = makeSignal()

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Players" then
		return {
			GetPlayers = function()
				return playersList
			end,
			PlayerAdded = playerAddedSignal,
		}
	end
	return nil
end

game = fakeGame

local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")

assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(tinyfolkPlayer).ok, "tinyfolk profile loaded")
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(giantPlayer).ok, "giant profile loaded")

require("../src/ServerScriptService/Services/TrophyDisplayPolicyService.server")

local policyApi = _G._TrophyDisplayPolicyService_QueryAPI
assertTrue(type(policyApi) == "table", "policy query api present")

policyApi.ResetForTests()
policyApi.SyncPreferenceFromProfile(tinyfolkPlayer)
assertEqual(
	tinyfolkPlayer:GetAttribute(TrophyConfig.DisplayPolicyAttributes.OptOutOfNameDisplay),
	false,
	"default preference projects allow-reference attribute"
)

assertEqual(policyApi.GetOptOutForUserId(5101), false, "in-session default resolves to allow reference")
assertEqual(policyApi.GetOptOutForUserId(9999), true, "unknown user resolves to opt-out safe default")

local setResult = policyApi.SetOptOutForPlayer(tinyfolkPlayer, true)
assertTrue(setResult.accepted, "set opt-out accepted")
assertTrue(setResult.optOutOfNameDisplay == true, "set opt-out returns preference")
assertEqual(
	tinyfolkPlayer:GetAttribute(TrophyConfig.DisplayPolicyAttributes.OptOutOfNameDisplay),
	true,
	"set opt-out projects attribute"
)
local storedPreference = policyApi.GetPreferenceForPlayer(tinyfolkPlayer)
assertTrue(storedPreference.optOutOfNameDisplay == true, "set opt-out persists profile preference")

local giantSet = policyApi.SetOptOutForPlayer(giantPlayer, true)
assertEqual(giantSet.reason, "tinyfolk_role_required", "giant cannot set trophy display policy")

assertTrue(type(updateRequestRemote._Handler) == "function", "remote handler registered")
updateRequestRemote._Handler(tinyfolkPlayer, {
	optOutOfNameDisplay = false,
})
assertTrue(updateResponseRemote._LastClientPayload.accepted, "remote update accepted")
assertTrue(updateResponseRemote._LastClientPayload.optOutOfNameDisplay == false, "remote update clears opt-out")

print("trophy_display_policy_service_runtime_entrypoint.spec.luau: all checks passed")
