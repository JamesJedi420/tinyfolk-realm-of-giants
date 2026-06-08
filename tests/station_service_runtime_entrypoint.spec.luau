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
local activateRemote = makeRemoteEvent("StationActivateRequest")
local debugRequestRemote = makeRemoteEvent("StationDebugStateRequest")
local debugResponseRemote = makeRemoteEvent("StationDebugStateResponse")
addChild(remotesFolder, "StationActivateRequest", activateRemote)
addChild(remotesFolder, "StationDebugStateRequest", debugRequestRemote)
addChild(remotesFolder, "StationDebugStateResponse", debugResponseRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["SpecialistConfig"] = "../../ReplicatedStorage/Shared/Config/SpecialistConfig"
configFolder._Children["VillageWorksiteUpgradeConfig"] =
	"../../ReplicatedStorage/Shared/Config/VillageWorksiteUpgradeConfig"

local giantRealmFolder = makeNode("GiantRealm", "Folder", "ReplicatedStorage.Shared.GiantRealm")
giantRealmFolder._Children["VillageWorksiteUpgradeState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradeState"

local sharedConstructionFolder = makeNode("Construction", "Folder", "ReplicatedStorage.Shared.Construction")
sharedConstructionFolder._Children["ContextualTaskProgressLogic"] =
	"../../ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic"
sharedConstructionFolder._Children["TaskQteTimingLogic"] =
	"../../ReplicatedStorage/Shared/Construction/TaskQteTimingLogic"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(sharedFolder, "Construction", sharedConstructionFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local stationsFolder = makeNode("Stations", "Folder", "Workspace.Map.Stations")
addChild(stationsFolder, "WorkStation_A", makeBasePart("WorkStation_A", 10, 0, 10))
addChild(stationsFolder, "WorkStation_B", makeBasePart("WorkStation_B", 12, 0, 10))
addChild(stationsFolder, "WorkStation_C", makeBasePart("WorkStation_C", 20, 0, 10))
addChild(stationsFolder, "MiningStation_A", makeBasePart("MiningStation_A", 14, 0, 10))
addChild(stationsFolder, "Warehouse_A", makeBasePart("Warehouse_A", 30, 0, 10))
addChild(stationsFolder, "Granary_A", makeBasePart("Granary_A", 35, 0, 10))
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

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = {
	Parent = scriptParent,
} :: any

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local StationConfig = require("../src/ReplicatedStorage/Shared/Config/StationConfig")

local legacyPlayer = makeAlivePlayer(7101, Vector3.new(10, 0, 10))
legacyPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
legacyPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Woodcutter)

local taskPlayer = makeAlivePlayer(7102, Vector3.new(10, 0, 10))
taskPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
taskPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Woodcutter)

local interactionAssignPlayer = makeAlivePlayer(7104, Vector3.new(20, 0, 10))
interactionAssignPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
interactionAssignPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)
interactionAssignPlayer:SetAttribute("SpecialistAssignedStationId", nil)

local targetReassignPlayer = makeAlivePlayer(7105, Vector3.new(10, 0, 10))
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
		return true, "assigned"
	end,
}

local loaded, loadError = pcall(function()
	require("../src/ServerScriptService/Services/StationService.server")
end)
if not loaded then
	error(string.format("FAIL [station service loads]: %s", tostring(loadError)))
end

assertTrue(activateRemote._Handler ~= nil, "station service binds StationActivateRequest handler")

local stationStateById = _G._StationService_StationState
assertTrue(type(stationStateById) == "table", "station state export present")

StationConfig.RequestCooldownSeconds = 0
StationConfig.RequiredSpecialistRoleByStationId.WorkStation_B = SpecialistConfig.SpecialistRoles.Woodcutter
StationConfig.RequiredSpecialistRoleByStationId.WorkStation_C = SpecialistConfig.SpecialistRoles.Woodcutter
activateRemote:FireServer(interactionAssignPlayer, "WorkStation_C")
assertEqual(
	interactionAssignPlayer:GetAttribute("SpecialistRole"),
	SpecialistConfig.SpecialistRoles.Woodcutter,
	"station activation assigns required specialist role"
)
assertEqual(
	interactionAssignPlayer:GetAttribute("SpecialistAssignedStationId"),
	"WorkStation_C",
	"station activation assigns station id"
)
assertEqual(#interactionAssignCalls, 1, "station activation called interaction assignment API")
assertEqual(stationStateById["WorkStation_C"].isActive, true, "station activation starts after assignment")

runServiceHeartbeat:Fire(StationConfig.GenerationIntervalSeconds)
assertTrue(stationStateById["WorkStation_C"].resourceTotal > 0, "assigned station generates material on tick")
assertEqual(stationStateById["WorkStation_C"].isActive, true, "assigned station remains active after valid tick")

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")
local flowBeforeHaul = ResourceFlowState.GetMaterialSnapshot("Wood")
activateRemote:FireServer(interactionAssignPlayer, "WorkStation_C")
local flowAfterHaul = ResourceFlowState.GetMaterialSnapshot("Wood")
assertTrue(flowAfterHaul.inTransit > flowBeforeHaul.inTransit, "assigned specialist moves produced Wood to transit")

activateRemote:FireServer(targetReassignPlayer, "WorkStation_A")
runServiceHeartbeat:Fire(StationConfig.GenerationIntervalSeconds)
local workstationATickCountBeforeReassign = stationStateById["WorkStation_A"].tickCount
assertTrue(workstationATickCountBeforeReassign > 0, "WorkStation_A generates before target reassignment")

_G._SpecialistAssignmentService_QueryAPI.AssignForInteraction(
	targetReassignPlayer,
	SpecialistConfig.SpecialistRoles.Woodcutter,
	"WorkStation_B"
)
runServiceHeartbeat:Fire(StationConfig.GenerationIntervalSeconds)
assertEqual(stationStateById["WorkStation_A"].isActive, false, "WorkStation_A stops after assignment target changes")
assertEqual(
	stationStateById["WorkStation_A"].tickCount,
	workstationATickCountBeforeReassign,
	"WorkStation_A does not tick after target reassignment"
)
ResourceFlowState.TransferProducedToInTransit("Wood", 999)

activateRemote:FireServer(legacyPlayer, "WorkStation_B")
assertEqual(stationStateById["WorkStation_B"].isActive, true, "legacy string payload still activates station")

activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "begin",
	now = 100,
})
assertEqual(taskPlayer:GetAttribute("StationTaskActiveStationId"), "WorkStation_A", "task begin sets active station id")
assertEqual(taskPlayer:GetAttribute("StationTaskLastReason"), "began", "task begin sets began reason")
assertEqual(taskPlayer:GetAttribute("StationTaskObjectiveState"), "progressing", "task begin sets progressing state")

local warnsBeforeNotReady = #warns
activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "complete",
	now = 100.5,
})
local sawNotReady = false
for i = warnsBeforeNotReady + 1, #warns do
	if string.find(warns[i], "task_not_ready", 1, true) ~= nil then
		sawNotReady = true
		break
	end
end
assertTrue(sawNotReady, "task complete before duration is rejected")
assertEqual(stationStateById["WorkStation_A"].isActive, false, "not_ready rejection keeps station inactive")

activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "cancel",
	now = 100,
})
assertTrue(taskPlayer:GetAttribute("StationTaskActiveStationId") == nil, "task cancel clears active station id")
assertEqual(taskPlayer:GetAttribute("StationTaskLastReason"), "canceled", "task cancel sets canceled reason")
assertEqual(taskPlayer:GetAttribute("StationTaskObjectiveState"), "idle", "task cancel sets idle state")

activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "begin",
	now = 102,
})
activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "complete",
	now = 104,
})
assertEqual(stationStateById["WorkStation_A"].isActive, true, "task complete activates station")
assertEqual(taskPlayer:GetAttribute("StationTaskLastReason"), "completed", "task complete sets completed reason")
assertEqual(taskPlayer:GetAttribute("StationTaskObjectiveState"), "completed", "task complete sets completed state")

activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "begin",
	now = 106,
})
activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "disrupt",
	now = 106.2,
})
assertEqual(taskPlayer:GetAttribute("StationTaskObjectiveState"), "regressing", "task disrupt sets regressing state")
assertEqual(taskPlayer:GetAttribute("StationTaskLastReason"), "disrupted", "task disrupt sets disrupted reason")

activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "disrupt",
	now = 106.6,
})
activateRemote:FireServer(taskPlayer, {
	stationId = "WorkStation_A",
	mode = "disrupt",
	now = 106.9,
})
assertTrue(sawWarnContaining("task_regression_cap_reached"), "task regression cap rejection is surfaced")

-- TIN-154 QTE slice: optional complete-time window can award early completion or apply disruption penalty.
StationConfig.TaskQteEnabled = true
StationConfig.TaskQteWindowSeconds = 0.2
StationConfig.TaskQteBonusSeconds = 0.35
StationConfig.TaskQteFailureDisrupts = true

local qtePlayer = makeAlivePlayer(7103, Vector3.new(18, 0, 10))
qtePlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
qtePlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Miner)
table.insert(playersList, qtePlayer)

activateRemote:FireServer(qtePlayer, {
	stationId = "MiningStation_A",
	mode = "begin",
	now = 120,
})
activateRemote:FireServer(qtePlayer, {
	stationId = "MiningStation_A",
	mode = "complete",
	now = 121.35,
	qteTapAt = 121.35,
})
assertEqual(qtePlayer:GetAttribute("StationTaskQteResult"), "success", "QTE success marks station task qte attribute")
assertEqual(qtePlayer:GetAttribute("StationTaskLastReason"), "completed", "QTE success allows completed reason")

activateRemote:FireServer(qtePlayer, {
	stationId = "MiningStation_A",
	mode = "begin",
	now = 130,
})
local warnsBeforeQteFail = #warns
activateRemote:FireServer(qtePlayer, {
	stationId = "MiningStation_A",
	mode = "complete",
	now = 133.0,
	qteTapAt = 133.0,
})

local sawQteFailed = false
for i = warnsBeforeQteFail + 1, #warns do
	if string.find(warns[i], "task_qte_failed", 1, true) ~= nil then
		sawQteFailed = true
		break
	end
end
assertTrue(sawQteFailed, "QTE miss rejects completion with task_qte_failed")
assertEqual(qtePlayer:GetAttribute("StationTaskQteResult"), "failed", "QTE failure marks station task qte attribute")
assertEqual(
	qtePlayer:GetAttribute("StationTaskObjectiveState"),
	"regressing",
	"QTE failure applies disruption regression penalty"
)

print("station_service_runtime_entrypoint: all checks passed")
