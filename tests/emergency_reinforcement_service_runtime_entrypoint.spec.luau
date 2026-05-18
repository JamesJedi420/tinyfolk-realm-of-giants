--!strict

local MockPlayer = require("../tests/mocks/MockPlayer")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
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
		_Attributes = {},
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

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function makePart(name: string, position: any)
	local part = makeNode(name, "BasePart")
	part.Position = position
	part.CFrame = { Position = position }
	return part
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
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
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireClient(self: any, _player: any, payload: any)
		self._LastClientPayload = payload
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "EmergencyReinforcementRequest", makeRemoteEvent("EmergencyReinforcementRequest"))
addChild(remotesFolder, "EmergencyReinforcementResponse", makeRemoteEvent("EmergencyReinforcementResponse"))
addChild(
	remotesFolder,
	"EmergencyReinforcementDebugStateRequest",
	makeRemoteEvent("EmergencyReinforcementDebugStateRequest")
)
addChild(
	remotesFolder,
	"EmergencyReinforcementDebugStateResponse",
	makeRemoteEvent("EmergencyReinforcementDebugStateResponse")
)

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(
	configFolder,
	"EmergencyReinforcementConfig",
	"../../ReplicatedStorage/Shared/Config/EmergencyReinforcementConfig"
)

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
addChild(
	giantRealmFolder,
	"EmergencyReinforcementState",
	"../../ReplicatedStorage/Shared/GiantRealm/EmergencyReinforcementState"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local objectivesFolder = makeNode("Objectives", "Folder")
local callCenterPart = makePart("CallCenter_A", { x = 0, y = 0, z = 0 })
addChild(objectivesFolder, "CallCenter_A", callCenterPart)

local spawnsFolder = makeNode("Spawns", "Folder")
local reinforcementSpawnPart = makePart("ReinforcementSpawn", { x = 20, y = 0, z = 0 })
addChild(spawnsFolder, "ReinforcementSpawn", reinforcementSpawnPart)

local mapFolder = makeNode("Map", "Folder")
addChild(mapFolder, "Objectives", objectivesFolder)
addChild(mapFolder, "Spawns", spawnsFolder)

local workspaceService = makeNode("Workspace", "Workspace")
addChild(workspaceService, "Map", mapFolder)

local requester = MockPlayer.new(1101, "RequesterTinyfolk", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
local giant = MockPlayer.new(1102, "GiantUser", {
	role = "Giant",
	positionZ = 4,
	health = 100,
})
local candidate = MockPlayer.new(1103, "CandidateTinyfolk", {
	role = "Tinyfolk",
	positionZ = 8,
	health = 0,
})

local playersList: { any } = { requester, giant, candidate }
local playersService: any = {
	PlayerAdded = makeSignal(),
	PlayerRemoving = makeSignal(),
}

function playersService:GetPlayers(): { any }
	return playersList
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

require("../src/ServerScriptService/Services/EmergencyReinforcementService.server")

local reinforcementApi: any = _G._EmergencyReinforcementService_QueryAPI
assertTrue(type(reinforcementApi) == "table", "service exposes query API")

reinforcementApi.ResetForTests(0)

local function setRole(player: any, role: string)
	player:SetAttribute("Role", role)
end

local function setHumanoidHealth(player: any, health: number)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Health = health
	end
end

local function resetEdgeCaseWorld()
	setRole(requester, "Tinyfolk")
	setRole(giant, "Giant")
	setRole(candidate, "Tinyfolk")
	setHumanoidHealth(requester, 100)
	setHumanoidHealth(giant, 100)
	setHumanoidHealth(candidate, 0)

	callCenterPart.Position = requester.Character:FindFirstChild("HumanoidRootPart").Position
	callCenterPart.CFrame = { Position = callCenterPart.Position }

	spawnsFolder._Children["ReinforcementSpawn"] = reinforcementSpawnPart
	reinforcementSpawnPart:SetAttribute("InSafeZone", false)
	reinforcementSpawnPart:SetAttribute("SafeZoneType", nil)
	reinforcementSpawnPart:SetAttribute("SafeZoneProtectionEndsAt", nil)
end

resetEdgeCaseWorld()

do
	resetEdgeCaseWorld()
	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 20)

	assertFalse(rejected.accepted, "request rejects before min match elapsed")
	assertEqual(rejected.reason, "match_not_ready", "before min elapsed reason")
end

do
	resetEdgeCaseWorld()
	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "WrongObjective",
	}, 100)

	assertFalse(rejected.accepted, "wrong objective request rejected")
	assertEqual(rejected.reason, "invalid_objective", "wrong objective reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	setRole(requester, "Giant")
	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "WrongObjective",
	}, 100)

	assertFalse(rejected.accepted, "non-tinyfolk with invalid objective rejected")
	assertEqual(rejected.reason, "requester_not_tinyfolk", "role gate precedes objective probing")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "WrongObjective",
	}, 100)
	assertFalse(rejected.accepted, "invalid objective baseline reject")
	assertEqual(rejected.reason, "invalid_objective", "invalid objective baseline reason")

	local throttled = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "WrongObjective",
	}, 100.01)
	assertFalse(throttled.accepted, "rapid repeated invalid request is throttled")
	assertEqual(throttled.reason, "request_cooldown", "rapid repeated invalid request cooldown reason")

	local accepted = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100.06)
	assertTrue(accepted.accepted, "invalid request does not consume accepted-request cooldown")
	assertEqual(accepted.reason, "accepted", "valid follow-up accepted after reject cooldown window")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	local accepted = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertTrue(accepted.accepted, "valid request accepted")
	assertEqual(accepted.reason, "accepted", "valid request reason")
	assertEqual(accepted.snapshot.used, true, "accepted request marks used")
	assertEqual(accepted.snapshot.spawnedUserId, candidate.UserId, "accepted request picks deterministic candidate")
	assertTrue(reinforcementApi.IsCallAvailable(100) == false, "call no longer available after use")
	assertEqual(candidate:GetAttribute("EmergencyReinforcementEnabled"), true, "candidate flagged as reinforcement")
	assertEqual(candidate:GetAttribute("ReinforcementClass"), "Private", "candidate class initialized")
	assertEqual(candidate:GetAttribute("ReinforcementLoadoutPreset"), "Army", "candidate loadout initialized")

	local second = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 101)
	assertFalse(second.accepted, "second request rejected")
	assertEqual(second.reason, "reinforcement_already_used", "rapid repeat request rejects by one-time lock")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	-- Force threshold rejection by reviving candidate so active Tinyfolk count reaches threshold.
	setHumanoidHealth(candidate, 100)
	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)
	assertFalse(rejected.accepted, "request rejects when threshold not met")
	assertEqual(rejected.reason, "active_tinyfolk_threshold_not_met", "threshold rejection reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	callCenterPart.Position = { x = 999, y = 0, z = 0 }
	callCenterPart.CFrame = { Position = callCenterPart.Position }

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "request rejects when objective is out of range")
	assertEqual(rejected.reason, "objective_out_of_range", "objective out of range reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	spawnsFolder._Children["ReinforcementSpawn"] = nil

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "request rejects when reinforcement spawn is missing")
	assertEqual(rejected.reason, "reinforcement_spawn_missing", "missing reinforcement spawn reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	reinforcementSpawnPart:SetAttribute("InSafeZone", true)
	reinforcementSpawnPart:SetAttribute("SafeZoneType", "SharedHub")

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "request rejects when reinforcement spawn is protected")
	assertEqual(rejected.reason, "reinforcement_spawn_protected", "protected reinforcement spawn reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	setRole(candidate, "Giant")

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "request rejects when no reinforcement candidate exists")
	assertEqual(rejected.reason, "reinforcement_candidate_missing", "missing candidate reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	setHumanoidHealth(requester, 0)

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "request rejects when requester is not alive")
	assertEqual(rejected.reason, "requester_not_alive", "requester alive gate rejection reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	setRole(requester, "Giant")

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "request rejects when requester is not Tinyfolk")
	assertEqual(rejected.reason, "requester_not_tinyfolk", "requester role rejection reason")
end

print("emergency_reinforcement_service_runtime_entrypoint: all checks passed")
