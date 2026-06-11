--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local MockPlayer = require("../tests/mocks/MockPlayer")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local SkillCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/SkillCatalogSchema")

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

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
	}

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.GetChildren(self: any): { any }
		local children = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
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

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
local sharedFolder = makeNode("Shared", "Folder")
local configFolder = makeNode("Config", "Folder")
local giantRealmFolder = makeNode("GiantRealm", "Folder")
local skillsFolder = makeNode("Skills", "Folder")

addChild(
	configFolder,
	"EmergencyReinforcementConfig",
	"../../ReplicatedStorage/Shared/Config/EmergencyReinforcementConfig"
)
addChild(configFolder, "SkillCatalogSchema", "../../ReplicatedStorage/Shared/Config/SkillCatalogSchema")
addChild(giantRealmFolder, "RealmObjectiveState", "../../ReplicatedStorage/Shared/GiantRealm/RealmObjectiveState")
addChild(skillsFolder, "SkillsProfileState", "../../ReplicatedStorage/Shared/Skills/SkillsProfileState")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(sharedFolder, "Skills", skillsFolder)
addChild(replicatedStorage, "Shared", sharedFolder)

local workspaceService = makeNode("Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder")
local objectivesFolder = makeNode("Objectives", "Folder")
addChild(objectivesFolder, "ConstructionSite_A", makeNode("ConstructionSite_A", "Part"))
addChild(objectivesFolder, "Station_A", makeNode("Station_A", "Part"))
addChild(mapFolder, "Objectives", objectivesFolder)
addChild(workspaceService, "Map", mapFolder)

local completer = MockPlayer.new(2431, "Tinyfolk_Completer", { role = "Tinyfolk", health = 100 })
local playersList: { any } = { completer }

local playersService: any = {}
function playersService:GetPlayers(): { any }
	return playersList
end
function playersService:GetPlayerByUserId(userId: number): any?
	for _, player in ipairs(playersList) do
		if player.UserId == userId then
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
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local progressionSkillId = "objective_craft"
local catalogRecord = SkillCatalogSchema.GetSkillRecord(progressionSkillId)
assertTrue(catalogRecord ~= nil, "default catalog includes objective progression skill")

assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(completer).ok, "completer profile loaded")

require("../src/ServerScriptService/Services/SkillProgressionService.server")
require("../src/ServerScriptService/Services/RealmObjectiveService.server")

local queryApi = _G._RealmObjectiveService_QueryAPI
local progressionApi = _G._SkillProgressionService_QueryAPI
assertTrue(type(queryApi) == "table", "realm objective query api present")
assertTrue(type(progressionApi) == "table", "skill progression query api present")

local firstCompletion = queryApi.RecordObjectiveCompletion("ConstructionSite_A", 2431, 10)
assertTrue(firstCompletion.accepted, "first objective completion accepted")
assertTrue(firstCompletion.skillUnlockAccepted, "first completion unlocks progression skill")
assertEqual(firstCompletion.skillUnlockReason, "accepted", "first completion unlock reason")
assertEqual(firstCompletion.skillUnlockId, progressionSkillId, "first completion unlock skill id")

local unlocked = progressionApi.GetUnlockedSkillIds(completer)
assertEqual(#unlocked, 1, "one unlocked skill after objective completion")
assertEqual(unlocked[1], progressionSkillId, "objective unlock writes objective_craft")

local persisted = ProfilePersistenceGateway.GetLoadedPlayerProfileData(completer)
assertTrue(persisted.ok, "profile persisted after objective unlock")
assertEqual(
	persisted.data.skillsProfileState.unlockedSkillIds[1],
	progressionSkillId,
	"profile stores objective-unlocked skill id"
)

local duplicateCompletion = queryApi.RecordObjectiveCompletion("ConstructionSite_A", 2431, 11)
assertFalse(duplicateCompletion.accepted, "duplicate site completion rejected")
assertEqual(duplicateCompletion.reason, "site_already_completed", "duplicate completion reason")
assertEqual(duplicateCompletion.skillUnlockReason, "skill_unlock_skipped", "duplicate completion skips unlock")
assertEqual(#progressionApi.GetUnlockedSkillIds(completer), 1, "duplicate completion does not duplicate unlock")

local secondCompletion = queryApi.RecordObjectiveCompletion("Station_A", 2431, 12)
assertTrue(secondCompletion.accepted, "second objective completion accepted")
assertTrue(secondCompletion.skillUnlockAccepted, "second completion idempotent unlock accepted")
assertEqual(secondCompletion.skillUnlockReason, "skill_already_unlocked", "second completion unlock idempotent")
assertEqual(#progressionApi.GetUnlockedSkillIds(completer), 1, "second completion keeps single unlock")

print("objective_skill_unlock_runtime_entrypoint.spec.luau: all checks passed")
