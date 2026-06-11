--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local ContainmentRewardResolver = require("../src/ServerScriptService/Services/ContainmentRewardResolver")
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

local progressionSkillId = "custody_stewardship"
local catalogRecord = SkillCatalogSchema.GetSkillRecord(progressionSkillId)
assertTrue(catalogRecord ~= nil, "default catalog includes containment progression skill")

local custodian = makePlayer(2421)
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(custodian).ok, "custodian profile loaded")

require("../src/ServerScriptService/Services/SkillProgressionService.server")

local progressionApi = _G._SkillProgressionService_QueryAPI
assertTrue(type(progressionApi) == "table", "skill progression query api present")

local resolver = ContainmentRewardResolver.Create({
	now = function()
		return 100
	end,
	scoreApi = {
		RequestScoreEvent = function(): any
			return { accepted = true, reason = "accepted", awardedPoints = 50 }
		end,
	},
	trophyApi = {
		RecordContainmentEnd = function(): any
			return { accepted = true, reason = "accepted" }
		end,
	},
	giantLevelApi = {
		RecordContainmentEnd = function(): any
			return { accepted = true, reason = "accepted" }
		end,
		GetModifierSnapshot = function(): any
			return { containmentRewardMultiplier = 1 }
		end,
	},
	profileGateway = ProfilePersistenceGateway,
})

local first = resolver.Resolve({
	operationId = "op-containment-skill-unlock-1",
	custodianUserId = 2421,
	custodianPlayer = custodian,
	targetUserId = 2422,
	captureStartedAt = 1,
	captureExpiresAt = 9,
	endedAt = 5,
	endReason = "released",
	custodyWindowSeconds = 8,
})

assertTrue(first.accepted, "containment reward accepted")
assertTrue(first.skillUnlockAccepted, "containment unlocks progression skill")
assertEqual(first.skillUnlockReason, "accepted", "first containment unlock reason")
assertEqual(first.skillUnlockId, progressionSkillId, "containment unlock skill id")

local unlocked = progressionApi.GetUnlockedSkillIds(custodian)
assertEqual(#unlocked, 1, "one unlocked skill after containment reward")
assertEqual(unlocked[1], progressionSkillId, "containment unlock writes custody_stewardship")

local persisted = ProfilePersistenceGateway.GetLoadedPlayerProfileData(custodian)
assertTrue(persisted.ok, "profile persisted after containment unlock")
assertEqual(
	persisted.data.skillsProfileState.unlockedSkillIds[1],
	progressionSkillId,
	"profile stores containment-unlocked skill id"
)

local duplicate = resolver.Resolve({
	operationId = "op-containment-skill-unlock-1",
	custodianUserId = 2421,
	custodianPlayer = custodian,
	targetUserId = 2422,
	captureStartedAt = 1,
	endedAt = 5,
	endReason = "released",
	custodyWindowSeconds = 8,
})
assertTrue(duplicate.accepted, "duplicate containment accepted")
assertTrue(duplicate.duplicate, "duplicate containment marked")
assertEqual(#progressionApi.GetUnlockedSkillIds(custodian), 1, "duplicate containment does not duplicate unlock")

local second = resolver.Resolve({
	operationId = "op-containment-skill-unlock-2",
	custodianUserId = 2421,
	custodianPlayer = custodian,
	targetUserId = 2423,
	captureStartedAt = 10,
	endedAt = 15,
	endReason = "released",
	custodyWindowSeconds = 8,
})
assertTrue(second.accepted, "second containment accepted")
assertTrue(second.skillUnlockAccepted, "second containment idempotent unlock accepted")
assertEqual(second.skillUnlockReason, "skill_already_unlocked", "second containment unlock idempotent")
assertEqual(#progressionApi.GetUnlockedSkillIds(custodian), 1, "second containment keeps single unlock")

print("containment_reward_skill_unlock_runtime_entrypoint.spec.luau: all checks passed")
