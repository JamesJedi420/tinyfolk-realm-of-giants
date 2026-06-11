--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

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
assertEqual(catalogRecord.unlockSource, "progression", "default progression skill source")

local player = makePlayer(6701)
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(player).ok, "player profile loaded")

require("../src/ServerScriptService/Services/SkillProgressionService.server")

local progressionApi = _G._SkillProgressionService_QueryAPI
assertTrue(type(progressionApi) == "table", "skill progression query api present")

local initialUnlocked = progressionApi.GetUnlockedSkillIds(player)
assertEqual(next(initialUnlocked), nil, "initial unlocked skill ids empty")

local unlockResult = progressionApi.UnlockSkill(player, progressionSkillId)
assertTrue(unlockResult.accepted, "unlock accepted")
assertEqual(unlockResult.skillId, progressionSkillId, "unlock returns skill id")
assertEqual(#unlockResult.unlockedSkillIds, 1, "unlock returns unlocked ids")
assertEqual(unlockResult.unlockedSkillIds[1], progressionSkillId, "unlock writes progression skill id")

local duplicateUnlock = progressionApi.UnlockSkill(player, progressionSkillId)
assertFalse(duplicateUnlock.accepted, "duplicate unlock rejected")
assertEqual(duplicateUnlock.reason, "skill_already_unlocked", "duplicate unlock reason")

local persisted = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertTrue(persisted.ok, "profile persisted after unlock")
assertEqual(
	persisted.data.skillsProfileState.unlockedSkillIds[1],
	progressionSkillId,
	"profile stores unlocked skill id"
)

local missingUnlock = progressionApi.UnlockSkill(player, "missing_skill")
assertFalse(missingUnlock.accepted, "missing skill unlock rejected")
assertEqual(missingUnlock.reason, "skill_missing", "missing skill unlock reason")

assertTrue(type(unlockResult.progress) == "table", "unlock returns seeded progress")
assertEqual(unlockResult.progress.level, 1, "unlock progress level one")
assertEqual(unlockResult.progress.xp, 0, "unlock progress zero xp")

local progressById = progressionApi.GetSkillProgressById(player)
assertTrue(type(progressById[progressionSkillId]) == "table", "get progress by id returns unlocked skill")
assertEqual(progressById[progressionSkillId].level, 1, "get progress by id level one")

local progress = progressionApi.GetSkillProgress(player, progressionSkillId)
assertTrue(type(progress) == "table", "get single progress returns record")
assertEqual(progress.xp, 0, "get single progress zero xp")

local awardResult = progressionApi.AwardSkillXp(player, progressionSkillId, 150)
assertTrue(awardResult.accepted, "award xp accepted")
assertEqual(awardResult.progress.level, 2, "award xp level two")
assertEqual(awardResult.progress.xp, 150, "award xp total")

local lockedAward = progressionApi.AwardSkillXp(player, "custody_stewardship", 10)
assertFalse(lockedAward.accepted, "award xp rejected when locked")
assertEqual(lockedAward.reason, "skill_not_unlocked", "locked award reason")

local cooldownResult = progressionApi.SetSkillCooldownEndsAt(player, progressionSkillId, 250.25)
assertTrue(cooldownResult.accepted, "set cooldown accepted")
assertEqual(cooldownResult.progress.cooldownEndsAt, 250.25, "set cooldown ends at")

local persistedProgress = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertTrue(persistedProgress.ok, "progress persisted after award and cooldown")
assertEqual(
	persistedProgress.data.skillsProfileState.skillProgressById[progressionSkillId].xp,
	150,
	"profile stores awarded xp"
)
assertEqual(
	persistedProgress.data.skillsProfileState.skillProgressById[progressionSkillId].cooldownEndsAt,
	250.25,
	"profile stores cooldown ends at"
)

print("skill_progression_service_runtime_entrypoint.spec.luau: all checks passed")
