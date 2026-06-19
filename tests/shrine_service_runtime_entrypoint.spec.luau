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

local warns: { string } = {}
local globalEnv: any = getfenv()
local originalWarn = warn
warn = function(...: any)
	local packed: any = table.pack(...)
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

if Vector3 == nil then
	local vector3Mt: any = {}
	vector3Mt.__index = function(self: any, key: string)
		if key == "Magnitude" then
			return math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
		end
		return nil
	end
	vector3Mt.__sub = function(a: any, b: any)
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector3Mt)
	end

	Vector3 = {
		new = function(x: number, y: number, z: number)
			return setmetatable({ X = x, Y = y, Z = z }, vector3Mt)
		end,
	} :: any
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

	function node.GetDescendants(self: any): { any }
		local descendants: { any } = {}
		local walk: (current: any) -> ()
		walk = function(current: any)
			for _, child in pairs(current._Children) do
				table.insert(descendants, child)
				if type(child._Children) == "table" then
					walk(child)
				end
			end
		end
		walk(self)
		return descendants
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
		(child :: any).Parent = parent
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
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireServer(self: any, player: any, payload: any)
		if self._Handler == nil then
			error(string.format("remote %s handler not connected", self.Name))
		end
		self._Handler(player, payload)
	end

	function remote.FireClient(self: any, _player: any, payload: any)
		self._ClientPayload = payload
	end

	return remote
end

local function makeBasePart(name: string, x: number, y: number, z: number)
	local part = makeNode(name, "BasePart", "Workspace.Map.Stations." .. name)
	part.Position = Vector3.new(x, y, z)
	return part
end

local function makeAlivePlayer(userId: number, position: any)
	local root = makeBasePart("HumanoidRootPart", position.X, position.Y, position.Z)
	local humanoid = {
		Health = 100,
	}
	local character = {
		FindFirstChild = function(_self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return root
			end
			return nil
		end,
		FindFirstChildOfClass = function(_self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}

	return {
		UserId = userId,
		Character = character,
		_Attributes = {},
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
	}
end

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
local activateRemote = makeRemoteEvent("ShrineActivateRequest")
local debugRequestRemote = makeRemoteEvent("ShrineDebugStateRequest")
local debugResponseRemote = makeRemoteEvent("ShrineDebugStateResponse")
addChild(remotesFolder, "ShrineActivateRequest", activateRemote)
addChild(remotesFolder, "ShrineDebugStateRequest", debugRequestRemote)
addChild(remotesFolder, "ShrineDebugStateResponse", debugResponseRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
configFolder._Children["ShrineConfig"] = "../../ReplicatedStorage/Shared/Config/ShrineConfig"
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["SpecialistConfig"] = "../../ReplicatedStorage/Shared/Config/SpecialistConfig"
configFolder._Children["LaborActionConfig"] = "../../ReplicatedStorage/Shared/Config/LaborActionConfig"

local sharedConstructionFolder = makeNode("Construction", "Folder", "ReplicatedStorage.Shared.Construction")
sharedConstructionFolder._Children["ContextualTaskProgressLogic"] =
	"../../ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic"
sharedConstructionFolder._Children["TaskQteTimingLogic"] =
	"../../ReplicatedStorage/Shared/Construction/TaskQteTimingLogic"

local giantRealmFolder = makeNode("GiantRealm", "Folder", "ReplicatedStorage.Shared.GiantRealm")
giantRealmFolder._Children["GiantRealmResourceState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState"
giantRealmFolder._Children["LaborActionState"] = "../../ReplicatedStorage/Shared/GiantRealm/LaborActionState"
giantRealmFolder._Children["LaborComplianceState"] = "../../ReplicatedStorage/Shared/GiantRealm/LaborComplianceState"
giantRealmFolder._Children["VillageWorksiteUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"
giantRealmFolder._Children["RealmObjectiveSiteIdResolver"] =
	"../../ReplicatedStorage/Shared/GiantRealm/RealmObjectiveSiteIdResolver"
giantRealmFolder._Children["PostRescueProtectionState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/PostRescueProtectionState"
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"
configFolder._Children["SkillProgressionConfig"] = "../../ReplicatedStorage/Shared/Config/SkillProgressionConfig"
configFolder._Children["SkillCatalogSchema"] = "../../ReplicatedStorage/Shared/Config/SkillCatalogSchema"

local skillsFolder = makeNode("Skills", "Folder", "ReplicatedStorage.Shared.Skills")
skillsFolder._Children["SkillXpAwardPolicy"] = "../../ReplicatedStorage/Shared/Skills/SkillXpAwardPolicy"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "Skills", skillsFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(sharedFolder, "Construction", sharedConstructionFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local stationsFolder = makeNode("Stations", "Folder", "Workspace.Map.Stations")
addChild(stationsFolder, "Shrine_A", makeBasePart("Shrine_A", -8, 0, 10))
addChild(stationsFolder, "Shrine_B", makeBasePart("Shrine_B", -6, 0, 10))
addChild(stationsFolder, "Shrine_C", makeBasePart("Shrine_C", -10, 0, 10))
addChild(stationsFolder, "Shrine_D", makeBasePart("Shrine_D", -12, 0, 10))
addChild(mapFolder, "Stations", stationsFolder)
addChild(workspaceService, "Map", mapFolder)

local runServiceHeartbeat = makeSignal()
local runService: any = {
	Heartbeat = runServiceHeartbeat,
}

local playersList: { any } = {}
local playerRemoving = makeSignal()
local playersService: any = {
	PlayerRemoving = playerRemoving,
	GetPlayers = function(_self: any)
		return playersList
	end,
	GetPlayerByUserId = function(_self: any, userId: number)
		for _, player in ipairs(playersList) do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end,
}

local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	if serviceName == "RunService" then
		return runService
	end
	if serviceName == "Players" then
		return playersService
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local objectiveCompletionCalls: { any } = {}
_G._RealmObjectiveService_QueryAPI = {
	RecordObjectiveCompletion = function(siteId: string, completedByUserId: number?, at: number?): any
		table.insert(objectiveCompletionCalls, {
			siteId = siteId,
			completedByUserId = completedByUserId,
			at = at,
		})
		return { accepted = true, reason = "accepted" }
	end,
}

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
scriptParent._Children["GiantEssenceSession"] = "../../ServerScriptService/Services/GiantEssenceSession"
scriptParent._Children["ObjectiveSkillXpProducer"] = "../../ServerScriptService/Services/ObjectiveSkillXpProducer"
scriptParent._Children["RealmObjectiveCompletionCaller"] =
	"../../ServerScriptService/Services/RealmObjectiveCompletionCaller"
scriptParent._Children["PostRescueProtectionCancellationCaller"] =
	"../../ServerScriptService/Services/PostRescueProtectionCancellationCaller"
script = {
	Parent = scriptParent,
} :: any

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local ShrineConfig = require("../src/ReplicatedStorage/Shared/Config/ShrineConfig")
local LaborActionConfig = require("../src/ReplicatedStorage/Shared/Config/LaborActionConfig")
local VillageWorksiteUpgradeState = require("../src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState")

local legacyPlayer = makeAlivePlayer(7201, Vector3.new(-8, 0, 10))
legacyPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
legacyPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Worshipper)

local taskPlayer = makeAlivePlayer(7202, Vector3.new(-8, 0, 10))
taskPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
taskPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Worshipper)

local interactionAssignPlayer = makeAlivePlayer(7204, Vector3.new(-12, 0, 10))
interactionAssignPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
interactionAssignPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Miner)
interactionAssignPlayer:SetAttribute("SpecialistAssignedStationId", "MiningStation_A")

local targetReassignPlayer = makeAlivePlayer(7205, Vector3.new(-8, 0, 10))
targetReassignPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
targetReassignPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)
targetReassignPlayer:SetAttribute("SpecialistAssignedStationId", nil)

table.insert(playersList, legacyPlayer)
table.insert(playersList, taskPlayer)
table.insert(playersList, interactionAssignPlayer)
table.insert(playersList, targetReassignPlayer)

local interactionAssignCalls: { any } = {}
_G._SpecialistAssignmentService_QueryAPI = {
	AssignForInteraction = function(player: any, specialistRole: string, assignedStationId: string): (boolean, string)
		table.insert(interactionAssignCalls, {
			userId = player.UserId,
			specialistRole = specialistRole,
			assignedStationId = assignedStationId,
		})
		player:SetAttribute("SpecialistRole", specialistRole)
		player:SetAttribute("SpecialistAssignedStationId", assignedStationId)
		return true, "reassigned"
	end,
}

local loaded, loadError = pcall(function()
	require("../src/ServerScriptService/Services/ShrineService.server")
end)
if not loaded then
	error(string.format("FAIL [shrine service loads]: %s", tostring(loadError)))
end

assertTrue(activateRemote._Handler ~= nil, "shrine service binds ShrineActivateRequest handler")

local shrineStateById = globalEnv._ShrineService_ShrineState
assertTrue(type(shrineStateById) == "table", "shrine state export present")

local shrineQueryApi = globalEnv._ShrineService_QueryAPI
assertTrue(type(shrineQueryApi) == "table", "shrine query API export present")
assertTrue(type(shrineQueryApi.BuildPersistenceState) == "function", "shrine query API exposes build persistence")
assertTrue(type(shrineQueryApi.ApplyPersistenceState) == "function", "shrine query API exposes apply persistence")

ShrineConfig.RequestCooldownSeconds = 0
activateRemote:FireServer(interactionAssignPlayer, "Shrine_D")
assertEqual(
	interactionAssignPlayer:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.Worshipper,
	"shrine activation assigns Worshipper"
)
assertEqual(
	interactionAssignPlayer:GetAttribute("SpecialistAssignedStationId"),
	"Shrine_D",
	"shrine activation assigns shrine id"
)
assertEqual(#interactionAssignCalls, 1, "shrine activation called interaction assignment API")
assertEqual(shrineStateById["Shrine_D"].isActive, false, "assignment alone does not start passive production")

activateRemote:FireServer(interactionAssignPlayer, {
	shrineId = "Shrine_D",
	mode = "begin",
	now = 190,
})
activateRemote:FireServer(interactionAssignPlayer, {
	shrineId = "Shrine_D",
	mode = "complete",
	now = 192,
})
assertTrue(shrineStateById["Shrine_D"].essenceTotal > 0, "completed sermon work action generates essence")
assertEqual(shrineStateById["Shrine_D"].isActive, false, "work action production does not leave shrine active")
assertEqual(
	interactionAssignPlayer:GetAttribute(LaborActionConfig.LaborActionAttribute),
	LaborActionConfig.Actions.Sermon,
	"sermon labor action exposed on player debug attributes"
)

_G._VillageWorksiteUpgradeService_QueryAPI = {
	GetShrineProductionModifiers = function(shrineId: string)
		if shrineId == "Shrine_B" then
			return VillageWorksiteUpgradeState.ResolveShrineProductionModifiers(2)
		end
		return VillageWorksiteUpgradeState.ResolveShrineProductionModifiers(0)
	end,
}

local upgradePlayer = makeAlivePlayer(7206, Vector3.new(-6, 0, 10))
upgradePlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
upgradePlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Worshipper)
table.insert(playersList, upgradePlayer)

activateRemote:FireServer(upgradePlayer, {
	shrineId = "Shrine_B",
	mode = "begin",
	now = 170,
})
activateRemote:FireServer(upgradePlayer, {
	shrineId = "Shrine_B",
	mode = "complete",
	now = 172,
})
assertTrue(
	shrineStateById["Shrine_B"].essenceTotal >= 5,
	"shrine upgrade level 2 scales essence per work action to at least 5"
)
assertEqual(
	shrineStateById["Shrine_B"].part:GetAttribute(ShrineConfig.WorksiteUpgradeLevelAttribute),
	2,
	"shrine upgrade level exposed on part debug attributes"
)
assertEqual(
	shrineStateById["Shrine_B"].part:GetAttribute(ShrineConfig.WorksiteUpgradeEffectivePerTickAttribute),
	5,
	"shrine effective per-tick exposed on part debug attributes"
)
assertEqual(
	shrineStateById["Shrine_B"].part:GetAttribute(ShrineConfig.WorksiteUpgradeEffectiveMaxTotalAttribute),
	270,
	"shrine effective max total exposed on part debug attributes"
)

activateRemote:FireServer(targetReassignPlayer, "Shrine_A")
activateRemote:FireServer(targetReassignPlayer, {
	shrineId = "Shrine_A",
	mode = "begin",
	now = 180,
})
activateRemote:FireServer(targetReassignPlayer, {
	shrineId = "Shrine_A",
	mode = "complete",
	now = 182,
})
local shrineATickCountBeforeReassign = shrineStateById["Shrine_A"].tickCount
assertTrue(shrineATickCountBeforeReassign > 0, "Shrine_A generates before target reassignment")

_G._SpecialistAssignmentService_QueryAPI.AssignForInteraction(
	targetReassignPlayer,
	SpecialistConfig.SpecialistRoles.Worshipper,
	"Shrine_B"
)
runServiceHeartbeat:Fire(ShrineConfig.GenerationIntervalSeconds)
assertEqual(shrineStateById["Shrine_A"].isActive, false, "Shrine_A stops after assignment target changes")
assertEqual(
	shrineStateById["Shrine_A"].tickCount,
	shrineATickCountBeforeReassign,
	"Shrine_A does not tick after target reassignment"
)

activateRemote:FireServer(legacyPlayer, "Shrine_B")
assertEqual(
	shrineStateById["Shrine_B"].isActive,
	false,
	"legacy string payload assigns only without passive activation"
)

local objectiveCompletionCallsBeforeTask = #objectiveCompletionCalls
globalEnv._ShrineService_TaskState["Shrine_A"] =
	require("../src/ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic").New()
activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "begin",
	now = 200,
})
assertEqual(taskPlayer:GetAttribute("ShrineTaskActiveShrineId"), "Shrine_A", "task begin sets active shrine id")
assertEqual(taskPlayer:GetAttribute("ShrineTaskLastReason"), "began", "task begin sets began reason")
assertEqual(taskPlayer:GetAttribute("ShrineTaskObjectiveState"), "progressing", "task begin sets progressing state")

local warnsBeforeNotReady = #warns
activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "complete",
	now = 200.5,
})
local sawNotReady = false
for i = warnsBeforeNotReady + 1, #warns do
	if string.find(warns[i], "task_not_ready", 1, true) ~= nil then
		sawNotReady = true
		break
	end
end
assertTrue(sawNotReady, "task complete before duration is rejected")
assertEqual(shrineStateById["Shrine_A"].isActive, false, "not_ready rejection keeps shrine inactive")

activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "cancel",
	now = 200,
})
assertTrue(taskPlayer:GetAttribute("ShrineTaskActiveShrineId") == nil, "task cancel clears active shrine id")
assertEqual(taskPlayer:GetAttribute("ShrineTaskLastReason"), "canceled", "task cancel sets canceled reason")
assertEqual(taskPlayer:GetAttribute("ShrineTaskObjectiveState"), "idle", "task cancel sets idle state")

activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "begin",
	now = 202,
})
activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "complete",
	now = 204,
})
assertEqual(shrineStateById["Shrine_A"].isActive, false, "task complete generates without passive activation")
assertTrue(shrineStateById["Shrine_A"].essenceTotal > 0, "task complete generates bounded essence output")
assertEqual(taskPlayer:GetAttribute("ShrineTaskLastReason"), "completed", "task complete sets completed reason")
assertEqual(taskPlayer:GetAttribute("ShrineTaskObjectiveState"), "completed", "task complete sets completed state")
assertEqual(
	#objectiveCompletionCalls,
	objectiveCompletionCallsBeforeTask + 1,
	"contextual task completion records realm objective once"
)
assertEqual(
	objectiveCompletionCalls[#objectiveCompletionCalls].siteId,
	"ObjectiveSite_Shrine",
	"shrine contextual task maps to registered objective site"
)
assertEqual(
	objectiveCompletionCalls[#objectiveCompletionCalls].completedByUserId,
	7202,
	"shrine contextual task completion forwards completer user id"
)
assertEqual(objectiveCompletionCalls[#objectiveCompletionCalls].at, 204, "shrine completion forwards timestamp")

activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "begin",
	now = 206,
})
activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "disrupt",
	now = 206.35,
})
assertEqual(taskPlayer:GetAttribute("ShrineTaskObjectiveState"), "regressing", "task disrupt sets regressing state")
assertEqual(taskPlayer:GetAttribute("ShrineTaskLastReason"), "disrupted", "task disrupt sets disrupted reason")

activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "disrupt",
	now = 206.7,
})
activateRemote:FireServer(taskPlayer, {
	shrineId = "Shrine_A",
	mode = "disrupt",
	now = 207.0,
})
assertTrue(sawWarnContaining("task_regression_cap_reached"), "task regression cap rejection is surfaced")

-- TIN-154 QTE slice: optional complete-time window can award early completion or apply disruption penalty.
ShrineConfig.TaskQteEnabled = true
ShrineConfig.TaskQteWindowSeconds = 0.2
ShrineConfig.TaskQteBonusSeconds = 0.35
ShrineConfig.TaskQteFailureDisrupts = true

local qtePlayer = makeAlivePlayer(7203, Vector3.new(-10, 0, 10))
qtePlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
qtePlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Worshipper)
table.insert(playersList, qtePlayer)

activateRemote:FireServer(qtePlayer, {
	shrineId = "Shrine_C",
	mode = "begin",
	now = 220,
})
activateRemote:FireServer(qtePlayer, {
	shrineId = "Shrine_C",
	mode = "complete",
	now = 221.35,
	qteTapAt = 221.35,
})
assertEqual(qtePlayer:GetAttribute("ShrineTaskQteResult"), "success", "QTE success marks shrine task qte attribute")
assertEqual(qtePlayer:GetAttribute("ShrineTaskLastReason"), "completed", "QTE success allows completed reason")

activateRemote:FireServer(qtePlayer, {
	shrineId = "Shrine_C",
	mode = "begin",
	now = 230,
})
local warnsBeforeQteFail = #warns
activateRemote:FireServer(qtePlayer, {
	shrineId = "Shrine_C",
	mode = "complete",
	now = 233.0,
	qteTapAt = 233.0,
})

local sawQteFailed = false
for i = warnsBeforeQteFail + 1, #warns do
	if string.find(warns[i], "task_qte_failed", 1, true) ~= nil then
		sawQteFailed = true
		break
	end
end
assertTrue(sawQteFailed, "QTE miss rejects completion with task_qte_failed")
assertEqual(qtePlayer:GetAttribute("ShrineTaskQteResult"), "failed", "QTE failure marks shrine task qte attribute")
assertEqual(
	qtePlayer:GetAttribute("ShrineTaskObjectiveState"),
	"regressing",
	"QTE failure applies disruption regression penalty"
)

local persistenceSnapshot = shrineQueryApi.BuildPersistenceState()
assertTrue(type(persistenceSnapshot) == "table", "persistence snapshot is table")
assertEqual(#persistenceSnapshot.shrines, 4, "persistence snapshot includes shrine count")
assertEqual(persistenceSnapshot.shrines[1].shrineId, "Shrine_A", "persistence snapshot deterministic order A")
assertEqual(persistenceSnapshot.shrines[2].shrineId, "Shrine_B", "persistence snapshot deterministic order B")
assertEqual(persistenceSnapshot.shrines[3].shrineId, "Shrine_C", "persistence snapshot deterministic order C")
assertEqual(persistenceSnapshot.shrines[4].shrineId, "Shrine_D", "persistence snapshot deterministic order D")

local malformedApplyOk, malformedApplyReason = shrineQueryApi.ApplyPersistenceState("bad")
assertTrue(not malformedApplyOk, "malformed persistence apply rejects")
assertEqual(malformedApplyReason, "shrine_persistence_invalid", "malformed persistence apply reason")

local unknownApplyOk, unknownApplyReason = shrineQueryApi.ApplyPersistenceState({
	shrines = {
		{
			shrineId = "Shrine_Unknown",
			isActive = false,
			essenceTotal = 0,
			tickCount = 0,
			lastTickAt = 0,
			activatedByUserId = nil,
		},
	},
})
assertTrue(not unknownApplyOk, "unknown shrine persistence apply rejects")
assertEqual(
	unknownApplyReason,
	"shrine_persistence_record_unknown_shrine index=1",
	"unknown shrine persistence apply reason"
)

local applyOk, applyReason = shrineQueryApi.ApplyPersistenceState({
	shrines = {
		{
			shrineId = "Shrine_A",
			isActive = true,
			essenceTotal = 27,
			tickCount = 9,
			lastTickAt = 301,
			activatedByUserId = legacyPlayer.UserId,
		},
		{
			shrineId = "Shrine_C",
			isActive = false,
			essenceTotal = 4,
			tickCount = 2,
			lastTickAt = 250,
			activatedByUserId = nil,
		},
	},
})
assertTrue(applyOk, "valid shrine persistence apply succeeds")
assertEqual(applyReason, nil, "valid shrine persistence apply reason")
assertEqual(shrineStateById["Shrine_A"].isActive, true, "persistence apply restores active shrine")
assertEqual(shrineStateById["Shrine_A"].essenceTotal, 27, "persistence apply restores essence total")
assertEqual(shrineStateById["Shrine_A"].tickCount, 9, "persistence apply restores tick count")
assertEqual(shrineStateById["Shrine_A"].activatedByUserId, legacyPlayer.UserId, "persistence apply restores owner")
assertEqual(shrineStateById["Shrine_B"].essenceTotal, 0, "persistence apply resets missing shrine")

local clearOk, clearReason = shrineQueryApi.ApplyPersistenceState(nil)
assertTrue(clearOk, "nil shrine persistence apply succeeds")
assertEqual(clearReason, nil, "nil shrine persistence apply reason")
assertEqual(shrineStateById["Shrine_A"].isActive, false, "nil persistence apply clears active state")
assertEqual(shrineStateById["Shrine_A"].essenceTotal, 0, "nil persistence apply clears essence")

print("shrine_service_runtime_entrypoint: all checks passed")
