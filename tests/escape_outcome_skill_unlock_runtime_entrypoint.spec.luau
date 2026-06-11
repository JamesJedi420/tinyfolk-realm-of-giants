--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local EscapeOutcomeResolver = require("../src/ServerScriptService/Services/EscapeOutcomeResolver")
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

local function makePlayer(userId: number): any
	return {
		UserId = userId,
	}
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
configFolder._Children["SkillCatalogSchema"] = "../../ReplicatedStorage/Shared/Config/SkillCatalogSchema"

local skillsFolder = makeNode("Skills")
skillsFolder._Children["SkillsProfileState"] = "../../ReplicatedStorage/Shared/Skills/SkillsProfileState"

local sharedFolder = makeNode("Shared")
sharedFolder._Children["Config"] = configFolder
sharedFolder._Children["Skills"] = skillsFolder

local replicatedStorage = makeNode("ReplicatedStorage")
replicatedStorage._Children["Shared"] = sharedFolder

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local progressionSkillId = "realm_adaptation"
local catalogRecord = SkillCatalogSchema.GetSkillRecord(progressionSkillId)
assertTrue(catalogRecord ~= nil, "default catalog includes progression skill")

local player = makePlayer(6702)
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(player).ok, "player profile loaded")

require("../src/ServerScriptService/Services/SkillProgressionService.server")

local progressionApi = _G._SkillProgressionService_QueryAPI
assertTrue(type(progressionApi) == "table", "skill progression query api present")

local resolver = EscapeOutcomeResolver.Create({
	now = function()
		return 42
	end,
	profileGateway = ProfilePersistenceGateway,
	scoreApi = {
		RequestScoreEvent = function(): any
			return { accepted = true, reason = "accepted" }
		end,
	},
	carriedLootApi = {
		ConsumeForEscape = function(): any
			return { accepted = true, reason = "accepted", loot = { value = 0 } }
		end,
	},
	defenseHistoryApi = {
		RecordEscapeDefenseOutcome = function(): any
			return { accepted = true, reason = "accepted" }
		end,
	},
	returnToHub = function(): boolean
		return false
	end,
})

local first = resolver.Resolve({
	operationId = "op-escape-skill-unlock-1",
	userId = 6702,
	player = player,
	sourceKind = "final_exit",
	sourceId = "EscapeRoute_A",
	routeId = "EscapeRoute_A",
	realmId = "giant_realm_9001",
	difficulty = 1,
	now = 42,
})

assertTrue(first.accepted, "escape accepted")
assertTrue(first.skillUnlockAccepted, "escape unlocks progression skill")
assertEqual(first.skillUnlockReason, "accepted", "first escape unlock reason")
assertEqual(first.skillUnlockId, progressionSkillId, "escape unlock skill id")

local unlocked = progressionApi.GetUnlockedSkillIds(player)
assertEqual(#unlocked, 1, "one unlocked skill after escape")
assertEqual(unlocked[1], progressionSkillId, "escape unlock writes realm_adaptation")

local persisted = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertTrue(persisted.ok, "profile persisted after escape unlock")
assertEqual(
	persisted.data.skillsProfileState.unlockedSkillIds[1],
	progressionSkillId,
	"profile stores escape-unlocked skill id"
)

local duplicate = resolver.Resolve({
	operationId = "op-escape-skill-unlock-1",
	userId = 6702,
	player = player,
	sourceKind = "final_exit",
	sourceId = "EscapeRoute_A",
	routeId = "EscapeRoute_A",
	now = 42,
})
assertTrue(duplicate.accepted, "duplicate escape accepted")
assertTrue(duplicate.duplicate, "duplicate escape marked")
assertEqual(#progressionApi.GetUnlockedSkillIds(player), 1, "duplicate escape does not duplicate unlock")

local second = resolver.Resolve({
	operationId = "op-escape-skill-unlock-2",
	userId = 6702,
	player = player,
	sourceKind = "final_exit",
	sourceId = "EscapeRoute_B",
	routeId = "EscapeRoute_B",
	now = 43,
})
assertTrue(second.accepted, "second escape accepted")
assertTrue(second.skillUnlockAccepted, "second escape idempotent unlock accepted")
assertEqual(second.skillUnlockReason, "skill_already_unlocked", "second escape unlock idempotent")
assertEqual(#progressionApi.GetUnlockedSkillIds(player), 1, "second escape keeps single unlock")

print("escape_outcome_skill_unlock_runtime_entrypoint.spec.luau: all checks passed")
