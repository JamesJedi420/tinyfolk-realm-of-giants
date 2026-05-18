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

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireClient(_self: any, _player: any, _payload: any)
		return
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "ScoreEventRequest", makeRemoteEvent("ScoreEventRequest"))
addChild(remotesFolder, "ScoreEventResponse", makeRemoteEvent("ScoreEventResponse"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "ScoreConfig", "../../ReplicatedStorage/Shared/Config/ScoreConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "ScoreState", "../../ReplicatedStorage/Shared/GiantRealm/ScoreState")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local tinyfolk = MockPlayer.new(3101, "TinyfolkScorer", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
local giant = MockPlayer.new(3102, "GiantScorer", {
	role = "Giant",
	positionZ = 2,
	health = 100,
})

local playersList: { any } = { tinyfolk, giant }
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
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

require("../src/ServerScriptService/Services/ScoreService.server")

local scoreApi: any = _G._ScoreService_QueryAPI
assertTrue(type(scoreApi) == "table", "service exposes query api")

local function setRole(player: any, role: string)
	player:SetAttribute("Role", role)
end

local function resetState()
	scoreApi.ResetForTests()
	setRole(tinyfolk, "Tinyfolk")
	setRole(giant, "Giant")
end

do
	resetState()
	local accepted = scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1, { source = "runtime" })
	assertTrue(accepted.accepted, "valid score event accepted")
	assertEqual(accepted.reason, "accepted", "valid score reason")
	local snapshot = scoreApi.GetPlayerScoreSnapshot(tinyfolk.UserId)
	assertEqual(snapshot.total, 100, "snapshot total updated")
end

do
	resetState()
	local mismatch = scoreApi.RequestScoreEvent(tinyfolk.UserId, "capture_success", 1, nil)
	assertFalse(mismatch.accepted, "role mismatch rejected")
	assertEqual(mismatch.reason, "actor_role_mismatch", "role mismatch reason")
end

do
	resetState()
	local unknown = scoreApi.RequestScoreEvent(tinyfolk.UserId, "does_not_exist", 1, nil)
	assertFalse(unknown.accepted, "unknown event rejected")
	assertEqual(unknown.reason, "event_unknown", "unknown event reason")
end

do
	resetState()
	local missing = scoreApi.RequestScoreEvent(999999, "escape_success", 1, nil)
	assertFalse(missing.accepted, "missing actor rejected")
	assertEqual(missing.reason, "actor_not_found", "missing actor reason")
end

do
	resetState()
	local first = scoreApi.RequestScoreEvent(giant.UserId, "capture_success", 1, nil)
	local second = scoreApi.RequestScoreEvent(giant.UserId, "capture_success", 2, nil)
	assertTrue(first.accepted and second.accepted, "capture events accepted")
	assertTrue(second.record.awardedPoints < first.record.awardedPoints, "repeat depreciation applied")
	local totals = scoreApi.GetCategoryTotals()
	assertTrue((totals.control or 0) > 0, "category totals exposed")
	local recent = scoreApi.GetRecentScoreEvents(1)
	assertEqual(#recent, 1, "recent limit works")
	assertEqual(recent[1].eventId, "capture_success", "recent newest event id")
end

print("score_service_runtime_entrypoint: all checks passed")
