--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local ContainmentRewardResolver = require("../src/ServerScriptService/Services/ContainmentRewardResolver")
local EscapeOutcomeResolver = require("../src/ServerScriptService/Services/EscapeOutcomeResolver")
local MockPlayer = require("../tests/mocks/MockPlayer")
local OutcomeSkillXpProducer = require("../src/ServerScriptService/Services/OutcomeSkillXpProducer")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local SkillCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/SkillCatalogSchema")
local SkillProgressionConfig = require("../src/ReplicatedStorage/Shared/Config/SkillProgressionConfig")

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
addChild(configFolder, "SkillProgressionConfig", "../../ReplicatedStorage/Shared/Config/SkillProgressionConfig")
addChild(giantRealmFolder, "RealmObjectiveState", "../../ReplicatedStorage/Shared/GiantRealm/RealmObjectiveState")
addChild(skillsFolder, "SkillsProfileState", "../../ReplicatedStorage/Shared/Skills/SkillsProfileState")
addChild(skillsFolder, "SkillXpAwardPolicy", "../../ReplicatedStorage/Shared/Skills/SkillXpAwardPolicy")
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

local playersService: any = nil

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" and playersService ~= nil then
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

require("../src/ServerScriptService/Services/SkillProgressionService.server")

local progressionApi = _G._SkillProgressionService_QueryAPI
assertTrue(type(progressionApi) == "table", "skill progression query api present")

local escapeAward = SkillProgressionConfig.XpAwardsByOutcomeKind.escape_success
local containmentAward = SkillProgressionConfig.XpAwardsByOutcomeKind.containment_reward
local objectiveAward = SkillProgressionConfig.XpAwardsByOutcomeKind.objective_completion

assertTrue(SkillCatalogSchema.GetSkillRecord(escapeAward.skillId) ~= nil, "escape skill in catalog")
assertTrue(SkillCatalogSchema.GetSkillRecord(containmentAward.skillId) ~= nil, "containment skill in catalog")
assertTrue(SkillCatalogSchema.GetSkillRecord(objectiveAward.skillId) ~= nil, "objective skill in catalog")

local escapePlayer = MockPlayer.new(2461, "Tinyfolk_Escape_Xp", { role = "Tinyfolk", health = 100 })
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(escapePlayer).ok, "escape player profile loaded")
assertTrue(progressionApi.UnlockSkill(escapePlayer, escapeAward.skillId).accepted, "escape skill unlocked")

local escapeXpAccepted, escapeXpReason = OutcomeSkillXpProducer.RecordEscapeSuccessXp(escapePlayer)
assertTrue(escapeXpAccepted, "escape producer awards xp")
assertEqual(escapeXpReason, "accepted", "escape producer reason")
assertEqual(
	progressionApi.GetSkillProgress(escapePlayer, escapeAward.skillId).xp,
	escapeAward.xpAmount,
	"escape producer writes configured xp"
)

local escapeResolver = EscapeOutcomeResolver.Create({
	now = function()
		return 20
	end,
	carriedLootApi = {
		ConsumeForEscape = function(): any
			return { accepted = true, reason = "accepted", loot = { items = {}, wood = 0, stone = 0, value = 0 } }
		end,
	},
	scoreApi = {
		RequestScoreEvent = function(): any
			return { accepted = true, reason = "accepted" }
		end,
	},
	profileGateway = ProfilePersistenceGateway,
	defenseHistoryApi = {
		RecordEscapeDefenseOutcome = function(): any
			return { accepted = true, reason = "accepted" }
		end,
	},
	returnToHub = function(): boolean
		return false
	end,
})

local integrationEscapePlayer = MockPlayer.new(2462, "Tinyfolk_Escape_Integration", { role = "Tinyfolk", health = 100 })
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(integrationEscapePlayer).ok, "integration escape profile loaded")

local escapeOutcome = escapeResolver.Resolve({
	operationId = "op-escape-xp-1",
	userId = 2462,
	player = integrationEscapePlayer,
	sourceKind = "final_exit",
	sourceId = "EscapeRoute_A",
	routeId = "EscapeRoute_A",
	now = 21,
})
assertTrue(escapeOutcome.accepted, "escape outcome accepted")
assertTrue(escapeOutcome.skillUnlockAccepted, "escape outcome unlocks skill")
assertTrue(escapeOutcome.skillXpAccepted, "escape outcome awards skill xp")
assertEqual(escapeOutcome.skillXpId, escapeAward.skillId, "escape outcome xp skill id")
assertEqual(
	progressionApi.GetSkillProgress(integrationEscapePlayer, escapeAward.skillId).xp,
	escapeAward.xpAmount,
	"escape outcome writes configured xp after unlock"
)

local duplicateEscape = escapeResolver.Resolve({
	operationId = "op-escape-xp-1",
	userId = 2462,
	player = integrationEscapePlayer,
	sourceKind = "final_exit",
	sourceId = "EscapeRoute_A",
	routeId = "EscapeRoute_A",
	now = 22,
})
assertTrue(duplicateEscape.duplicate, "duplicate escape detected")
assertFalse(duplicateEscape.skillXpAccepted == true, "duplicate escape skips xp award")

local custodian = { UserId = 2463 }
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(custodian).ok, "custodian profile loaded")

local containmentResolver = ContainmentRewardResolver.Create({
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

local containmentOutcome = containmentResolver.Resolve({
	operationId = "op-containment-xp-1",
	custodianUserId = 2463,
	custodianPlayer = custodian,
	targetUserId = 2464,
	captureStartedAt = 1,
	captureExpiresAt = 9,
	endedAt = 5,
	endReason = "released",
	custodyWindowSeconds = 8,
})
assertTrue(containmentOutcome.accepted, "containment outcome accepted")
assertTrue(containmentOutcome.skillUnlockAccepted, "containment outcome unlocks skill")
assertTrue(containmentOutcome.skillXpAccepted, "containment outcome awards skill xp")
assertEqual(containmentOutcome.skillXpId, containmentAward.skillId, "containment outcome xp skill id")
assertEqual(
	progressionApi.GetSkillProgress(custodian, containmentAward.skillId).xp,
	containmentAward.xpAmount,
	"containment outcome writes configured xp after unlock"
)

local completer = MockPlayer.new(2465, "Tinyfolk_Objective_Xp", { role = "Tinyfolk", health = 100 })
local playersList: { any } = { completer }

playersService = {
	GetPlayers = function(): { any }
		return playersList
	end,
	GetPlayerByUserId = function(_self: any, userId: number): any?
		for _, player in ipairs(playersList) do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end,
}

assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(completer).ok, "completer profile loaded")
require("../src/ServerScriptService/Services/RealmObjectiveService.server")

local objectiveQueryApi = _G._RealmObjectiveService_QueryAPI
assertTrue(type(objectiveQueryApi) == "table", "realm objective query api present")

local objectiveCompletion = objectiveQueryApi.RecordObjectiveCompletion("ConstructionSite_A", 2465, 30)
assertTrue(objectiveCompletion.accepted, "objective completion accepted")
assertTrue(objectiveCompletion.skillUnlockAccepted, "objective completion unlocks skill")
assertTrue(objectiveCompletion.skillXpAccepted, "objective completion awards skill xp")
assertEqual(objectiveCompletion.skillXpId, objectiveAward.skillId, "objective completion xp skill id")
assertEqual(
	progressionApi.GetSkillProgress(completer, objectiveAward.skillId).xp,
	objectiveAward.xpAmount,
	"objective completion writes configured xp after unlock"
)

local persistedObjective = ProfilePersistenceGateway.GetLoadedPlayerProfileData(completer)
assertEqual(
	persistedObjective.data.skillsProfileState.skillProgressById[objectiveAward.skillId].xp,
	objectiveAward.xpAmount,
	"objective completion persists awarded xp"
)

print("outcome_skill_xp_producer_runtime_entrypoint.spec.luau: all checks passed")
