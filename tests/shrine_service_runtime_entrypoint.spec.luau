--!strict

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

local sharedConstructionFolder = makeNode("Construction", "Folder", "ReplicatedStorage.Shared.Construction")
sharedConstructionFolder._Children["ContextualTaskProgressLogic"] =
	"../../ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic"
sharedConstructionFolder._Children["TaskQteTimingLogic"] =
	"../../ReplicatedStorage/Shared/Construction/TaskQteTimingLogic"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
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

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
scriptParent._Children["GiantEssenceSession"] = "../../ServerScriptService/Services/GiantEssenceSession"
script = {
	Parent = scriptParent,
} :: any

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local ShrineConfig = require("../src/ReplicatedStorage/Shared/Config/ShrineConfig")

local legacyPlayer = makeAlivePlayer(7201, Vector3.new(-8, 0, 10))
legacyPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
legacyPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Worshipper)

local taskPlayer = makeAlivePlayer(7202, Vector3.new(-8, 0, 10))
taskPlayer:SetAttribute("Role", RoleConfig.Roles.Tinyfolk)
taskPlayer:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Worshipper)

table.insert(playersList, legacyPlayer)
table.insert(playersList, taskPlayer)

local loaded, loadError = pcall(function()
	require("../src/ServerScriptService/Services/ShrineService.server")
end)
if not loaded then
	error(string.format("FAIL [shrine service loads]: %s", tostring(loadError)))
end

assertTrue(activateRemote._Handler ~= nil, "shrine service binds ShrineActivateRequest handler")

local shrineStateById = _G._ShrineService_ShrineState
assertTrue(type(shrineStateById) == "table", "shrine state export present")

activateRemote:FireServer(legacyPlayer, "Shrine_B")
assertEqual(shrineStateById["Shrine_B"].isActive, true, "legacy string payload still activates shrine")

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
assertEqual(shrineStateById["Shrine_A"].isActive, true, "task complete activates shrine")
assertEqual(taskPlayer:GetAttribute("ShrineTaskLastReason"), "completed", "task complete sets completed reason")
assertEqual(taskPlayer:GetAttribute("ShrineTaskObjectiveState"), "completed", "task complete sets completed state")

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

print("shrine_service_runtime_entrypoint: all checks passed")
