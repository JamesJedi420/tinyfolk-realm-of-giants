--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
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
		remote._LastClientPayload = _payload
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
	_G._GiantTraitService_QueryAPI = nil
	setRole(tinyfolk, "Tinyfolk")
	setRole(giant, "Giant")
end

do
	resetState()
	_G._GiantTraitService_QueryAPI = {
		GetModifierSnapshot = function(_player: any)
			return { scoreEventMultiplier = 1.2 }
		end,
	}

	local boosted = scoreApi.RequestScoreEvent(giant.UserId, "capture_success", 1, nil)
	assertTrue(boosted.accepted, "giant event accepts multiplier integration")
	assertEqual(boosted.record.awardedPoints, 108, "giant event applies injected multiplier")
end

do
	resetState()
	_G._GiantTraitService_QueryAPI = nil

	local fallbackAbsent = scoreApi.RequestScoreEvent(giant.UserId, "capture_success", 1, nil)
	assertTrue(fallbackAbsent.accepted, "giant event accepted when trait api absent")
	assertEqual(fallbackAbsent.record.awardedPoints, 90, "giant event falls back safely when trait api absent")
end

do
	resetState()
	_G._GiantTraitService_QueryAPI = {
		GetModifierSnapshot = function(_player: any)
			return {}
		end,
	}

	local fallbackNoMultiplier = scoreApi.RequestScoreEvent(giant.UserId, "capture_success", 1, nil)
	assertTrue(fallbackNoMultiplier.accepted, "giant event accepted when trait api omits multiplier")
	assertEqual(
		fallbackNoMultiplier.record.awardedPoints,
		90,
		"giant event falls back safely when trait api omits multiplier"
	)
end

do
	resetState()
	_G._GiantTraitService_QueryAPI = {
		GetModifierSnapshot = function(_player: any)
			return { scoreEventMultiplier = 1.5 }
		end,
	}

	local tinyfolkResult = scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1, nil)
	assertTrue(tinyfolkResult.accepted, "tinyfolk event accepted with giant trait api present")
	assertEqual(tinyfolkResult.record.awardedPoints, 100, "tinyfolk event is not affected by giant multiplier")
end

do
	resetState()
	local accepted = scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1, { source = "runtime" })
	assertTrue(accepted.accepted, "valid score event accepted")
	assertEqual(accepted.reason, "accepted", "valid score reason")
	assertEqual(accepted.record.bucket, "normal", "expanded record bucket")
	assertEqual(accepted.record.feedbackKey, "score_escape_success", "expanded record feedback key")
	local snapshot = scoreApi.GetPlayerScoreSnapshot(tinyfolk.UserId)
	assertEqual(snapshot.total, 100, "snapshot total updated")
	assertEqual(snapshot.buckets.normal.categories.objective, 100, "snapshot exposes bucket-separated total")
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
	assertTrue(missing.record == nil, "missing actor has no record")
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

do
	resetState()
	local reward = scoreApi.RequestScoreEvent(giant.UserId, "containment_reward", 1, {
		contributionRatio = 0.5,
		endReason = "released",
		targetUserId = tinyfolk.UserId,
	})
	assertTrue(reward.accepted, "containment reward score accepted")
	assertEqual(reward.record.category, "control", "containment reward score category")
	assertEqual(reward.record.contributionRatio, 0.5, "containment reward contribution ratio")
	assertEqual(reward.record.rawPoints, 25, "containment reward raw points")
	assertEqual(reward.record.feedbackKey, "score_containment_reward", "containment reward feedback key")
	local attrs = giant:GetAttributes()
	assertEqual(attrs["ScoreLastFeedbackKey"], "score_containment_reward", "containment reward feedback attribute")

	local mismatch = scoreApi.RequestScoreEvent(tinyfolk.UserId, "containment_reward", 2, { contributionRatio = 1 })
	assertFalse(mismatch.accepted, "containment reward rejects Tinyfolk")
	assertEqual(mismatch.reason, "actor_role_mismatch", "containment reward role mismatch")
end

do
	resetState()

	for i = 1, 10 do
		scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", i * 100, nil)
	end

	local catTotals = scoreApi.GetCategoryTotals()
	assertEqual(catTotals.objective or 0, 500, "category total at cap")

	local sixthAttempt = scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1100, nil)
	assertFalse(sixthAttempt.accepted, "event rejected when category at cap")
	assertEqual(sixthAttempt.reason, "category_cap_reached", "correct rejection reason for category cap")
end

do
	resetState()
	local _first = scoreApi.RequestScoreEvent(tinyfolk.UserId, "rescue_complete", 1, nil)
	local second = scoreApi.RequestScoreEvent(tinyfolk.UserId, "rescue_complete", 2, nil)
	local third = scoreApi.RequestScoreEvent(tinyfolk.UserId, "rescue_complete", 3, nil)

	local recent = scoreApi.GetRecentScoreEvents(2)
	assertEqual(#recent, 2, "recent returns requested limit")
	assertEqual(recent[1].sequence, second.record.sequence, "recent oldest is second event")
	assertEqual(recent[2].sequence, third.record.sequence, "recent newest is third event")
end

do
	resetState()
	scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1, nil)
	local recent = scoreApi.GetRecentScoreEvents(0)
	assertEqual(#recent, 0, "recent returns empty for zero limit")
end

do
	resetState()

	for i = 1, 3 do
		scoreApi.RequestScoreEvent(giant.UserId, "capture_success", i, nil)
	end

	local snapshot = scoreApi.GetPlayerScoreSnapshot(giant.UserId)
	assertTrue(snapshot.total > 0, "snapshot total updated after multiple events")
	assertTrue(snapshot.categories.control > 0, "snapshot category total updated")
end

do
	resetState()
	scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1, { source = "test" })

	local attrs = tinyfolk:GetAttributes()
	assertTrue(attrs["ScoreTotal"] == 100, "score total attribute set")
	assertTrue(attrs["ScoreObjective"] == 100, "score category attribute set")
	assertEqual(attrs["ScoreLastFeedbackKey"], "score_escape_success", "score feedback attribute set")
	assertEqual(attrs["ScoreLastAwardedPoints"], 100, "score awarded-points attribute set")
	assertEqual(attrs["ScoreLastBucket"], "normal", "score bucket attribute set")
	assertEqual(attrs["ScoreLastCategoryCapReached"], false, "score cap attribute false")
end

do
	resetState()
	local attributes1 = tinyfolk:GetAttributes()
	assertTrue(attributes1["ScoreTotal"] == 0, "initial score attributes zero")

	scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1, nil)

	local attributes2 = tinyfolk:GetAttributes()
	assertTrue(attributes2["ScoreTotal"] == 100, "score attributes updated after event")

	resetState()

	local attributes3 = tinyfolk:GetAttributes()
	assertTrue(attributes3["ScoreTotal"] == 0, "score attributes reset after reset call")
end

do
	resetState()
	scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1, nil)
	scoreApi.RequestScoreEvent(giant.UserId, "capture_success", 2, nil)

	local tinyfolkSnap = scoreApi.GetPlayerScoreSnapshot(tinyfolk.UserId)
	local giantSnap = scoreApi.GetPlayerScoreSnapshot(giant.UserId)

	assertEqual(tinyfolkSnap.total, 100, "tinyfolk score 100")
	assertEqual(giantSnap.total, 90, "giant score 90")

	local totals = scoreApi.GetCategoryTotals()
	assertEqual(totals.objective, 100, "objective total 100")
	assertEqual(totals.control, 90, "control total 90")
end

do
	resetState()
	local partial = scoreApi.RequestScoreEvent(tinyfolk.UserId, "objective_partial", 1, {
		contributionRatio = 0.5,
	})
	assertTrue(partial.accepted, "service accepts proportional event")
	assertEqual(partial.record.contributionRatio, 0.5, "service proportional contribution ratio")
	assertEqual(partial.record.rawPoints, 30, "service proportional raw points")
	assertEqual(partial.record.awardedPoints, 30, "service proportional awarded points")

	local missing = scoreApi.RequestScoreEvent(tinyfolk.UserId, "objective_partial", 2, nil)
	assertFalse(missing.accepted, "service rejects missing proportional metadata")
	assertEqual(missing.reason, "missing_contribution", "service missing proportional reason")
	assertEqual(missing.feedbackKey, "score_objective_partial", "service rejected proportional feedback key")
end

do
	resetState()
	for i = 1, 10 do
		scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", i * 100, nil)
	end

	local bonus = scoreApi.RequestScoreEvent(tinyfolk.UserId, "tutorial_bonus", 2000, nil)
	assertTrue(bonus.accepted, "service bonus bypasses normal cap")
	assertEqual(bonus.record.bucket, "bonus", "service bonus record bucket")

	local snapshot = scoreApi.GetPlayerScoreSnapshot(tinyfolk.UserId)
	assertEqual(snapshot.categories.objective, 500, "service normal objective remains capped")
	assertEqual(snapshot.buckets.bonus.categories.objective, 200, "service bonus bucket exposed")

	local bucketTotals = scoreApi.GetBucketTotals()
	assertEqual(bucketTotals.normal.categories.objective, 500, "service normal bucket total exposed")
	assertEqual(bucketTotals.bonus.categories.objective, 200, "service bonus bucket total exposed")
end

do
	resetState()
	local requestRemote = remotesFolder._Children["ScoreEventRequest"]
	local responseRemote = remotesFolder._Children["ScoreEventResponse"]

	requestRemote._Handler(tinyfolk, {
		eventId = "objective_partial",
		now = 1,
		metadata = { contributionRatio = 0.75 },
	})

	local payload = responseRemote._LastClientPayload
	assertTrue(payload.accepted, "remote table payload accepted")
	assertEqual(payload.record.eventId, "objective_partial", "remote table payload event id")
	assertEqual(payload.record.contributionRatio, 0.75, "remote table payload metadata contribution")

	requestRemote._Handler(tinyfolk, "escape_success")
	local stringPayload = responseRemote._LastClientPayload
	assertTrue(stringPayload.accepted, "remote string payload remains compatible")
	assertEqual(stringPayload.record.eventId, "escape_success", "remote string payload event id")
end

do
	resetState()
	for i = 1, 10 do
		scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", i * 100, nil)
	end

	local capped = scoreApi.RequestScoreEvent(tinyfolk.UserId, "escape_success", 1200, nil)
	assertFalse(capped.accepted, "service capped normal category rejected")
	assertEqual(capped.reason, "category_cap_reached", "service capped normal category reason")
	assertEqual(capped.categoryCapReached, true, "service capped normal category flag")
	assertEqual(capped.feedbackKey, "score_escape_success", "service capped normal category feedback")

	local attrs = tinyfolk:GetAttributes()
	assertEqual(attrs["ScoreLastCategoryCapReached"], true, "service capped attribute true")
	assertEqual(attrs["ScoreLastFeedbackKey"], "score_escape_success", "service capped feedback attribute")
end

print("score_service_runtime_entrypoint: all checks passed")
