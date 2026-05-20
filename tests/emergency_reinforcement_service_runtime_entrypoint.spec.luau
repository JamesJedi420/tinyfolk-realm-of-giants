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

local function assertSnapshotSchema(snapshot: any, label: string)
	assertEqual(type(snapshot), "table", string.format("%s snapshot table", label))
	assertEqual(type(snapshot.available), "boolean", string.format("%s snapshot.available", label))
	assertEqual(type(snapshot.used), "boolean", string.format("%s snapshot.used", label))
	assertTrue(
		snapshot.callStartedAt == nil or type(snapshot.callStartedAt) == "number",
		string.format("%s snapshot.callStartedAt", label)
	)
	assertTrue(
		snapshot.cooldownEndsAt == nil or type(snapshot.cooldownEndsAt) == "number",
		string.format("%s snapshot.cooldownEndsAt", label)
	)
	assertTrue(
		snapshot.triggeredByUserId == nil or type(snapshot.triggeredByUserId) == "number",
		string.format("%s snapshot.triggeredByUserId", label)
	)
	assertTrue(
		snapshot.spawnedUserId == nil or type(snapshot.spawnedUserId) == "number",
		string.format("%s snapshot.spawnedUserId", label)
	)
	assertTrue(
		snapshot.lastReason == nil or type(snapshot.lastReason) == "string",
		string.format("%s snapshot.lastReason", label)
	)
	assertTrue(
		snapshot.lastObjectiveId == nil or type(snapshot.lastObjectiveId) == "string",
		string.format("%s snapshot.lastObjectiveId", label)
	)
	assertEqual(type(snapshot.activeTinyfolkCount), "number", string.format("%s snapshot.activeTinyfolkCount", label))
	assertEqual(
		type(snapshot.activeTinyfolkThreshold),
		"number",
		string.format("%s snapshot.activeTinyfolkThreshold", label)
	)
	assertEqual(type(snapshot.readinessReason), "string", string.format("%s snapshot.readinessReason", label))
	assertEqual(type(snapshot.matchStartedAt), "number", string.format("%s snapshot.matchStartedAt", label))
end

local function assertResponseSchema(response: any, label: string)
	assertEqual(type(response), "table", string.format("%s response table", label))
	assertEqual(type(response.accepted), "boolean", string.format("%s response.accepted", label))
	assertEqual(type(response.reason), "string", string.format("%s response.reason", label))
	assertSnapshotSchema(response.snapshot, string.format("%s response.snapshot", label))
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

local tokenConsumeResult: any = {
	accepted = true,
	reason = "accepted",
	tokenState = nil,
}
local tokenSnapshotResult: any = {
	accepted = true,
	reason = "accepted",
	tokenState = {
		remainingTokens = 1,
		revoked = false,
	},
}
local tokenConsumeCallCount = 0
_G._RealmObjectiveService_QueryAPI = {
	RequestConsumeEmergencyToken = function(_requesterUserId: number, _objectiveId: string, _at: number): any
		tokenConsumeCallCount += 1
		return tokenConsumeResult
	end,
	GetEmergencyTokenSnapshot = function(_objectiveId: string, _at: number): any
		return tokenSnapshotResult
	end,
}

require("../src/ServerScriptService/Services/EmergencyReinforcementService.server")

local reinforcementApi: any = _G._EmergencyReinforcementService_QueryAPI
assertTrue(type(reinforcementApi) == "table", "service exposes query API")

local rawRequestReinforcement = reinforcementApi.RequestReinforcement
reinforcementApi.RequestReinforcement = function(requesterUserId: any, payload: any, at: any): any
	local result = rawRequestReinforcement(requesterUserId, payload, at)
	assertResponseSchema(result, "RequestReinforcement contract")
	return result
end

local rawGetStateSnapshot = reinforcementApi.GetStateSnapshot
reinforcementApi.GetStateSnapshot = function(at: any): any
	local snapshot = rawGetStateSnapshot(at)
	assertSnapshotSchema(snapshot, "GetStateSnapshot contract")
	return snapshot
end

local debugRequestRemote: any = remotesFolder._Children["EmergencyReinforcementDebugStateRequest"]
local debugResponseRemote: any = remotesFolder._Children["EmergencyReinforcementDebugStateResponse"]

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

	objectivesFolder._Children["CallCenter_A"] = callCenterPart

	callCenterPart.Position = requester.Character:FindFirstChild("HumanoidRootPart").Position
	callCenterPart.CFrame = { Position = callCenterPart.Position }

	spawnsFolder._Children["ReinforcementSpawn"] = reinforcementSpawnPart
	reinforcementSpawnPart:SetAttribute("InSafeZone", false)
	reinforcementSpawnPart:SetAttribute("SafeZoneType", nil)
	reinforcementSpawnPart:SetAttribute("SafeZoneProtectionEndsAt", nil)

	tokenConsumeCallCount = 0
	tokenConsumeResult = {
		accepted = true,
		reason = "accepted",
		tokenState = nil,
	}
	tokenSnapshotResult = {
		accepted = true,
		reason = "accepted",
		tokenState = {
			remainingTokens = 1,
			revoked = false,
		},
	}
end

resetEdgeCaseWorld()

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()

	local querySnapshot = reinforcementApi.GetStateSnapshot(100)
	assertSnapshotSchema(querySnapshot, "query snapshot explicit assertion")
	assertEqual(type(reinforcementApi.IsCallAvailable(100)), "boolean", "IsCallAvailable returns boolean")

	assertEqual(type(debugRequestRemote._Handler), "function", "debug request remote handler is bound")
	debugRequestRemote._Handler(requester, nil)
	assertSnapshotSchema(debugResponseRemote._LastClientPayload, "debug snapshot explicit assertion")
end

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
	local reinforcementApiAny: any = reinforcementApi

	local invalidRequesterId = reinforcementApiAny.RequestReinforcement("bad", {
		objectiveId = "CallCenter_A",
	}, 100)
	assertFalse(invalidRequesterId.accepted, "request rejects non-numeric requester id")
	assertEqual(invalidRequesterId.reason, "requester_user_id_invalid", "non-numeric requester id reason")

	local invalidRequesterFractional = reinforcementApiAny.RequestReinforcement(1101.5, {
		objectiveId = "CallCenter_A",
	}, 100)
	assertFalse(invalidRequesterFractional.accepted, "request rejects fractional requester id")
	assertEqual(invalidRequesterFractional.reason, "requester_user_id_invalid", "fractional requester id reason")

	local requesterMissing = reinforcementApi.RequestReinforcement(999999, {
		objectiveId = "CallCenter_A",
	}, 100)
	assertFalse(requesterMissing.accepted, "request rejects unknown requester id")
	assertEqual(requesterMissing.reason, "requester_not_found", "unknown requester reason")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	setHumanoidHealth(requester, 0)

	local first = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)
	assertFalse(first.accepted, "not-alive requester rejects")
	assertEqual(first.reason, "requester_not_alive", "not-alive requester reason")

	local second = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100.01)
	assertFalse(second.accepted, "not-alive requester is not masked by cooldown")
	assertEqual(second.reason, "requester_not_alive", "not-alive precedence over cooldown")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	local reinforcementApiAny: any = reinforcementApi

	local invalidNow = reinforcementApiAny.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 0 / 0)
	assertTrue(type(invalidNow.snapshot) == "table", "invalid now request returns snapshot")
	assertTrue(type(invalidNow.snapshot.matchStartedAt) == "number", "invalid now snapshot has numeric match start")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()

	objectivesFolder._Children["CallCenter_A"] = nil
	spawnsFolder._Children["ReinforcementSpawn"] = nil
	setRole(candidate, "Giant")

	local snapshot = reinforcementApi.GetStateSnapshot(100)
	assertEqual(snapshot.readinessReason, "invalid_objective", "snapshot readiness prioritizes missing objective")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()

	spawnsFolder._Children["ReinforcementSpawn"] = nil
	setRole(candidate, "Giant")

	local snapshot = reinforcementApi.GetStateSnapshot(100)
	assertEqual(snapshot.readinessReason, "reinforcement_spawn_missing", "snapshot readiness prioritizes missing spawn")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()

	reinforcementSpawnPart:SetAttribute("InSafeZone", true)
	reinforcementSpawnPart:SetAttribute("SafeZoneType", "SharedHub")
	setRole(candidate, "Giant")

	local snapshot = reinforcementApi.GetStateSnapshot(100)
	assertEqual(
		snapshot.readinessReason,
		"reinforcement_spawn_protected",
		"snapshot readiness prioritizes protected spawn"
	)
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	setRole(candidate, "Giant")

	local snapshot = reinforcementApi.GetStateSnapshot(100)
	assertEqual(
		snapshot.readinessReason,
		"reinforcement_candidate_missing",
		"snapshot readiness falls through to missing candidate"
	)
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	reinforcementApi.SetStateTransitionResolverForTests(function(_state: any, _input: any): any
		return {
			accepted = "bad",
			reason = 42,
			state = nil,
		}
	end)

	local failed = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)
	assertFalse(failed.accepted, "transition fault rejects request")
	assertEqual(failed.reason, "state_transition_failed", "transition fault rejection reason")
	assertEqual(failed.snapshot.lastReason, "state_transition_failed", "transition fault updates snapshot reason")

	reinforcementApi.SetStateTransitionResolverForTests(nil)
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	reinforcementApi.SetStateTransitionResolverForTests(function(_state: any, _input: any): any
		error("forced transition exception")
		return nil
	end)

	local failed = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)
	assertFalse(failed.accepted, "transition exception rejects request")
	assertEqual(failed.reason, "state_transition_failed", "transition exception rejection reason")
	assertEqual(failed.snapshot.lastReason, "state_transition_failed", "transition exception updates snapshot reason")

	reinforcementApi.SetStateTransitionResolverForTests(nil)
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

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenSnapshotResult = {
		accepted = false,
		reason = "objective_token_inactive",
		tokenState = nil,
	}

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "token snapshot rejection propagates to reinforcement")
	assertEqual(rejected.reason, "objective_token_inactive", "token snapshot rejection reason preserved")
	assertFalse(rejected.snapshot.used, "token snapshot rejection does not consume one-time-use")
	assertEqual(tokenConsumeCallCount, 0, "token consume is not called when snapshot rejects")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenSnapshotResult = {
		accepted = true,
		reason = "accepted",
		tokenState = {
			remainingTokens = 0,
			revoked = false,
		},
	}

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "token snapshot exhausted rejects reinforcement")
	assertEqual(rejected.reason, "token_unavailable", "token snapshot exhausted reason")
	assertFalse(rejected.snapshot.used, "token snapshot exhausted does not consume one-time-use")
	assertEqual(tokenConsumeCallCount, 0, "token consume not called when token is unavailable")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenSnapshotResult = {
		accepted = true,
		reason = "accepted",
		tokenState = {
			remainingTokens = 2,
			revoked = false,
			nextAvailableAt = 125,
		},
	}

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "token snapshot nextAvailableAt gate rejects reinforcement")
	assertEqual(rejected.reason, "token_not_ready", "token nextAvailableAt rejection reason")
	assertFalse(rejected.snapshot.used, "token nextAvailableAt rejection does not consume one-time-use")
	assertEqual(tokenConsumeCallCount, 0, "token consume not called when token is not ready")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenSnapshotResult = {
		accepted = true,
		reason = "accepted",
		tokenState = {
			remainingTokens = 2,
			revoked = false,
			scheduleWindows = {
				{ startsAt = 10, endsAt = 20 },
				{ startsAt = 40, endsAt = 60 },
			},
		},
	}

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "token snapshot schedule window gate rejects reinforcement")
	assertEqual(rejected.reason, "token_not_scheduled", "token schedule window rejection reason")
	assertFalse(rejected.snapshot.used, "token schedule window rejection does not consume one-time-use")
	assertEqual(tokenConsumeCallCount, 0, "token consume not called when token is outside schedule")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenSnapshotResult = {
		accepted = true,
		reason = "accepted",
		tokenState = {
			remainingTokens = 2,
			revoked = false,
			scheduleWindows = {
				{ startsAt = 90, endsAt = 130 },
			},
		},
	}

	local accepted = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertTrue(accepted.accepted, "token snapshot active schedule window allows reinforcement")
	assertEqual(accepted.reason, "accepted", "token schedule window accept reason")
	assertEqual(tokenConsumeCallCount, 1, "token consume called once when token is scheduled")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenConsumeResult = {
		accepted = false,
		reason = "token_already_consumed",
		tokenState = nil,
	}

	local rejected = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(rejected.accepted, "token consume rejection propagates to reinforcement")
	assertEqual(rejected.reason, "token_already_consumed", "token consume rejection reason preserved")
	assertTrue(type(rejected.snapshot) == "table", "token rejection includes snapshot")
	assertFalse(rejected.snapshot.used, "token reject does not consume one-time-use")

	tokenConsumeResult = {
		accepted = true,
		reason = "accepted",
		tokenState = nil,
	}
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenConsumeResult = {
		accepted = true,
		reason = "accepted",
		tokenState = nil,
	}

	local accepted = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertTrue(accepted.accepted, "token consumed + transition accepted = reinforcement accepted")
	assertEqual(accepted.reason, "accepted", "token + transition accepted reason")
	assertEqual(accepted.snapshot.used, true, "token accepted marks reinforcement used")
end

do
	reinforcementApi.ResetForTests(0)
	resetEdgeCaseWorld()
	tokenConsumeResult = {
		accepted = true,
		reason = "accepted",
		tokenState = nil,
	}

	reinforcementApi.SetStateTransitionResolverForTests(function(_state: any, _input: any): any
		return {
			accepted = true,
			reason = "accepted",
			state = {
				used = false,
				callStartedAt = nil,
				cooldownEndsAt = nil,
				triggeredByUserId = nil,
				spawnedUserId = nil,
				lastReason = nil,
				lastObjectiveId = nil,
			},
		}
	end)

	spawnsFolder._Children["ReinforcementSpawn"] = nil

	local compensationRequired = reinforcementApi.RequestReinforcement(requester.UserId, {
		objectiveId = "CallCenter_A",
	}, 100)

	assertFalse(compensationRequired.accepted, "token consumed + spawn failure = reinforcement_spawn_failed")
	assertEqual(compensationRequired.reason, "reinforcement_spawn_failed", "compensation-trace failure reason")
	assertTrue(type(compensationRequired.snapshot) == "table", "compensation-trace includes snapshot")

	reinforcementApi.SetStateTransitionResolverForTests(nil)
	spawnsFolder._Children["ReinforcementSpawn"] = reinforcementSpawnPart

	tokenConsumeResult = {
		accepted = true,
		reason = "accepted",
		tokenState = nil,
	}
end

print("emergency_reinforcement_service_runtime_entrypoint: all checks passed")
