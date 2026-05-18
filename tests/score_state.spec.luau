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

do
	local state = newState()
	local first = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 2001,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
		metadata = nil,
	})
	assertTrue(first.accepted, "nil metadata accepted")
	assertEqual(first.record.metadata, nil, "nil metadata preserved")
end

do
	local state = newState()
	local first = ScoreState.ResolveScoreEvent(state, {
		now = 1000000,
		userId = 2002,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	assertTrue(first.accepted, "very large tick accepted")
	assertEqual(first.record.now, 1000000, "very large tick preserved")
end

do
	local state = newState()
	local first = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 2003,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	local second = ScoreState.ResolveScoreEvent(first.state, {
		now = 2,
		userId = 2003,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})

	local afterDecayWindow = ScoreState.ResolveScoreEvent(second.state, {
		now = 2 + 45 + 1,
		userId = 2003,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})

	assertTrue(afterDecayWindow.record.awardedPoints == 80, "repeat counter resets after decay window expires")
end

do
	local state = newState()
	local objectiveEvents = {}

	for i = 1, 10 do
		local transition = ScoreState.ResolveScoreEvent(state, {
			now = i * 100,
			userId = 2004,
			eventId = "escape_success",
			actorRole = "Tinyfolk",
		})
		state = transition.state
		table.insert(objectiveEvents, transition)
	end

	local totals = ScoreState.GetCategoryTotals(state)
	assertEqual(totals.objective, 500, "category total at cap")
	assertTrue(objectiveEvents[#objectiveEvents].accepted == false, "later event rejected after category cap")
end

do
	local state = newState()

	local tinyfolkEscape = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 2005,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
	})

	local giantCapture = ScoreState.ResolveScoreEvent(tinyfolkEscape.state, {
		now = 2,
		userId = 2006,
		eventId = "capture_success",
		actorRole = "Giant",
	})

	local totals = ScoreState.GetCategoryTotals(giantCapture.state)
	assertEqual(totals.objective, 100, "tinyfolk objective points")
	assertEqual(totals.control, 90, "giant control points")
end

do
	local state = newState()
	local transition = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 2007,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
	})

	local snapshot = ScoreState.GetPlayerSnapshot(transition.state, 2007)
	assertEqual(snapshot.total, 100, "player score total accurate")
	assertEqual(snapshot.categories.objective, 100, "player category score accurate")

	local noSnapshot = ScoreState.GetPlayerSnapshot(transition.state, 9999)
	assertEqual(noSnapshot.total, 0, "nonexistent player score zero")
	assertEqual(noSnapshot.categories.objective or 0, 0, "nonexistent player category zero")
end

do
	local state = newState()

	for i = 1, 60 do
		local transition = ScoreState.ResolveScoreEvent(state, {
			now = i * 1000,
			userId = 2000 + ((i - 1) // 10),
			eventId = "capture_release",
			actorRole = "Giant",
		})
		state = transition.state
	end
	
	local recent = ScoreState.GetRecentEvents(state)
	assertTrue(#recent <= 50, "recent events buffer never exceeds max")
	assertTrue(#recent > 0, "recent events buffer has entries")
end


do
	local state = newState()
	
	local transition = ScoreState.ResolveScoreEvent(state, {
		now = 100,
		userId = 3001,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	
	assertTrue(transition.accepted, "rescue_complete event accepted with Tinyfolk role")
	
	local transition2 = ScoreState.ResolveScoreEvent(transition.state, {
		now = 200,
		userId = 3002,
		eventId = "rescue_complete",
		actorRole = "Tinyfolk",
	})
	
	state = transition2.state
	assertTrue(transition2.accepted, "second player rescue_complete accepted: " .. transition2.reason)
	
	local totals = ScoreState.GetCategoryTotals(state)
	local teamplayTotal = totals.teamplay or 0
	assertEqual(teamplayTotal, 160, "both events contributed to teamplay total")
end

do
	local state = newState()

	local transition1 = ScoreState.ResolveScoreEvent(state, {
		now = 100,
		userId = 5000,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
	})

	state = transition1.state

	local transition2 = ScoreState.ResolveScoreEvent(state, {
		now = 100 + 60,
		userId = 5000,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
	})

	state = transition2.state
	local record2 = transition2.record

	assertTrue(record2 ~= nil, "event at exactly decay window boundary accepted")
	assertEqual(record2.awardedPoints, 50, "decay applied at window boundary")
end
do
	local state = newState()

	local largeMetadata = {}
	for i = 1, 1000 do
		largeMetadata["key" .. i] = "value" .. i
	end

	local transition = ScoreState.ResolveScoreEvent(state, {
		now = 100,
		userId = 6000,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
		metadata = largeMetadata,
	})

	state = transition.state
	assertTrue(transition.accepted, "large metadata object accepted")
	assertEqual(transition.record.metadata, largeMetadata, "large metadata preserved")
end
do
	local state = newState()

	for i = 1, 100 do
		local userId = 3000 + (i % 10)
		local transition = ScoreState.ResolveScoreEvent(state, {
			now = i,
			userId = userId,
			eventId = "capture_release",
			actorRole = "Giant",
		})
		state = transition.state
	end

	local totals = ScoreState.GetCategoryTotals(state)
	local recent = ScoreState.GetRecentEvents(state)
	
	assertTrue((totals.control or 0) > 0, "rapid events accumulate points")
	assertTrue(#recent <= 50, "recent events buffer bounded during rapid fire")
end
do
	local state = newState()

	for i = 1, 15 do
		local transition = ScoreState.ResolveScoreEvent(state, {
			now = i * 100,
			userId = 7000,
			eventId = "capture_success",
			actorRole = "Giant",
		})
		state = transition.state
		if not transition.accepted then
			break
		end
	end

	local snap = ScoreState.GetPlayerSnapshot(state, 7000)
	assertTrue((snap.total or 0) > 0, "minMultiplier prevents points from going to zero")
	assertTrue((snap.categories.control or 0) >= 90 * 0.3, "minMultiplier respected (90 base * 0.3 min)")
end
do
	local state = ScoreState.NewState()
	state.playerScores[8000] = { total = -100, categories = { objective = -50, teamplay = -50 } }
	
	local snap = ScoreState.GetPlayerSnapshot(state, 8000)
	assertEqual(snap.total, -100, "corrupted total preserved in snapshot")
	assertEqual(snap.categories.objective, -50, "corrupted category preserved")
end

print("score_state: all checks passed")
