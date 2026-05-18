--!strict

local ScoreState = require("../src/ReplicatedStorage/Shared/GiantRealm/ScoreState")

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

local function newState()
	return ScoreState.NewState()
end

do
	local state = newState()
	local transition = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 1001,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
		metadata = { source = "test" },
	})
	assertTrue(transition.accepted, "valid score event accepted")
	assertEqual(transition.reason, "accepted", "accepted reason")
	assertEqual(transition.record.awardedPoints, 100, "base awarded points")
	local snapshot = ScoreState.GetPlayerSnapshot(transition.state, 1001)
	assertEqual(snapshot.total, 100, "player total updated")
	assertEqual(snapshot.categories.objective, 100, "category total updated")
end

do
	local state = newState()
	local unknown = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 1001,
		eventId = "unknown_event",
		actorRole = "Tinyfolk",
	})
	assertFalse(unknown.accepted, "unknown event rejected")
	assertEqual(unknown.reason, "event_unknown", "unknown event reason")
end

do
	local state = newState()
	local mismatch = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 1001,
		eventId = "capture_success",
		actorRole = "Tinyfolk",
	})
	assertFalse(mismatch.accepted, "role mismatch rejected")
	assertEqual(mismatch.reason, "actor_role_mismatch", "role mismatch reason")
end

do
	local state = newState()
	local first = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 1001,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	local second = ScoreState.ResolveScoreEvent(first.state, {
		now = 2,
		userId = 1001,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	local third = ScoreState.ResolveScoreEvent(second.state, {
		now = 3,
		userId = 1001,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	assertEqual(first.record.awardedPoints, 80, "first points")
	assertEqual(second.record.awardedPoints, 40, "second points decayed")
	assertEqual(third.record.awardedPoints, 20, "third points decayed")
end

do
	local state = newState()
	local current = state
	for i = 1, 4 do
		local transition = ScoreState.ResolveScoreEvent(current, {
			now = i,
			userId = 1002,
			eventId = "rescue_complete",
			actorRole = "Tinyfolk",
		})
		assertTrue(transition.accepted, string.format("accepted through cap baseline %d", i))
		current = transition.state
	end

	local capped = ScoreState.ResolveScoreEvent(current, {
		now = 5,
		userId = 1002,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	assertFalse(capped.accepted, "repeat cap rejects")
	assertEqual(capped.reason, "event_cap_reached", "repeat cap reason")
end

do
	local state = newState()
	local current = state
	for i = 1, 8 do
		local transition = ScoreState.ResolveScoreEvent(current, {
			now = i,
			userId = 1003,
			eventId = "escape_success",
			actorRole = "Tinyfolk",
		})
		if not transition.accepted then
			assertEqual(transition.reason, "category_cap_reached", "category cap reached reason")
			break
		end
		current = transition.state
	end
	local snapshot = ScoreState.GetPlayerSnapshot(current, 1003)
	assertTrue(snapshot.categories.objective <= 500, "objective category cap respected")
end

do
	local state = newState()
	local first = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 1004,
		eventId = "capture_success",
		actorRole = "Giant",
	})
	local second = ScoreState.ResolveScoreEvent(first.state, {
		now = 2,
		userId = 1005,
		eventId = "capture_release",
		actorRole = "Giant",
	})
	local totals = ScoreState.GetCategoryTotals(second.state)
	assertEqual(totals.control, first.record.awardedPoints + second.record.awardedPoints, "global category totals")
	local recent = ScoreState.GetRecentEvents(second.state, 1)
	assertEqual(#recent, 1, "recent events limit")
	assertEqual(recent[1].eventId, "capture_release", "recent events returns newest")
end

print("score_state: all checks passed")
