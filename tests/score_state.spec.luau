--!nocheck
local ScoreState = require("../src/ReplicatedStorage/Shared/GiantRealm/ScoreState")
local ScoreConfig = require("../src/ReplicatedStorage/Shared/Config/ScoreConfig")

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

local function withTemporaryEvent(eventId: string, definition: any, callback: () -> ())
	local previous = ScoreConfig.EventDefinitions[eventId]
	ScoreConfig.EventDefinitions[eventId] = definition
	callback()
	ScoreConfig.EventDefinitions[eventId] = previous
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
	assertEqual(transition.record.bucket, "normal", "default normal bucket")
	assertEqual(transition.record.rawPoints, 100, "raw points recorded")
	assertEqual(transition.record.contributionRatio, 1, "fixed score contribution ratio")
	assertEqual(transition.record.categoryCapReached, false, "category cap not reached")
	assertEqual(transition.record.feedbackKey, "score_escape_success", "feedback key recorded")
	local snapshot = ScoreState.GetPlayerSnapshot(transition.state, 1001)
	assertEqual(snapshot.total, 100, "player total updated")
	assertEqual(snapshot.categories.objective, 100, "category total updated")
	assertEqual(snapshot.buckets.normal.total, 100, "normal bucket total updated")
	assertEqual(snapshot.buckets.normal.categories.objective, 100, "normal objective bucket updated")
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
	withTemporaryEvent("bad_bucket_event", {
		category = "objective",
		bucket = "norml",
		basePoints = 100,
		valueRule = "fixed",
		decayWindowSeconds = 0,
		decayMultiplier = 1,
		minMultiplier = 1,
		repeatCap = 1,
		actorRole = "Tinyfolk",
		feedbackKey = "score_bad_bucket",
	}, function()
		local rejected = ScoreState.ResolveScoreEvent(newState(), {
			now = 1,
			userId = 1010,
			eventId = "bad_bucket_event",
			actorRole = "Tinyfolk",
		})
		assertFalse(rejected.accepted, "invalid bucket event rejected")
		assertEqual(rejected.reason, "invalid_reward_bucket", "invalid bucket reason")
		assertEqual(rejected.feedbackKey, "score_bad_bucket", "invalid bucket preserves feedback key")
	end)
end

do
	withTemporaryEvent("bad_category_event", {
		category = "unknown_category",
		bucket = "normal",
		basePoints = 100,
		valueRule = "fixed",
		decayWindowSeconds = 0,
		decayMultiplier = 1,
		minMultiplier = 1,
		repeatCap = 1,
		actorRole = "Tinyfolk",
	}, function()
		local rejected = ScoreState.ResolveScoreEvent(newState(), {
			now = 1,
			userId = 1011,
			eventId = "bad_category_event",
			actorRole = "Tinyfolk",
		})
		assertFalse(rejected.accepted, "invalid category event rejected")
		assertEqual(rejected.reason, "invalid_score_category", "invalid category reason")
	end)
end

do
	withTemporaryEvent("bad_category_role_event", {
		category = "control",
		bucket = "normal",
		basePoints = 100,
		valueRule = "fixed",
		decayWindowSeconds = 0,
		decayMultiplier = 1,
		minMultiplier = 1,
		repeatCap = 1,
		actorRole = "Tinyfolk",
	}, function()
		local rejected = ScoreState.ResolveScoreEvent(newState(), {
			now = 1,
			userId = 1012,
			eventId = "bad_category_role_event",
			actorRole = "Tinyfolk",
		})
		assertFalse(rejected.accepted, "category role mismatch event rejected")
		assertEqual(rejected.reason, "invalid_category_role", "category role mismatch reason")
	end)
end

do
	withTemporaryEvent("bad_value_rule_event", {
		category = "objective",
		bucket = "normal",
		basePoints = 100,
		valueRule = "mystery",
		decayWindowSeconds = 0,
		decayMultiplier = 1,
		minMultiplier = 1,
		repeatCap = 1,
		actorRole = "Tinyfolk",
	}, function()
		local rejected = ScoreState.ResolveScoreEvent(newState(), {
			now = 1,
			userId = 1013,
			eventId = "bad_value_rule_event",
			actorRole = "Tinyfolk",
		})
		assertFalse(rejected.accepted, "invalid value rule event rejected")
		assertEqual(rejected.reason, "invalid_value_rule", "invalid value rule reason")
	end)
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
	local current = state
	for i = 1, 10 do
		local transition = ScoreState.ResolveScoreEvent(current, {
			now = i * 100,
			userId = 9100,
			eventId = "escape_success",
			actorRole = "Tinyfolk",
		})
		current = transition.state
	end

	local bonus = ScoreState.ResolveScoreEvent(current, {
		now = 2000,
		userId = 9100,
		eventId = "tutorial_bonus",
		actorRole = "Tinyfolk",
	})
	local hidden = ScoreState.ResolveScoreEvent(bonus.state, {
		now = 2001,
		userId = 9100,
		eventId = "hidden_discovery",
		actorRole = "Tinyfolk",
	})
	local compensation = ScoreState.ResolveScoreEvent(hidden.state, {
		now = 2002,
		userId = 9100,
		eventId = "compensation_grant",
		actorRole = "Tinyfolk",
	})

	assertTrue(bonus.accepted, "bonus bucket bypasses normal category cap")
	assertTrue(hidden.accepted, "hidden bucket bypasses normal category cap")
	assertTrue(compensation.accepted, "compensation bucket bypasses normal category cap")

	local snapshot = ScoreState.GetPlayerSnapshot(compensation.state, 9100)
	assertEqual(snapshot.categories.objective, 500, "normal objective category remains capped")
	assertEqual(snapshot.buckets.bonus.categories.objective, 200, "bonus objective bucket tracked separately")
	assertEqual(snapshot.buckets.hidden.categories.objective, 75, "hidden objective bucket tracked separately")
	assertEqual(
		snapshot.buckets.compensation.categories.teamplay,
		150,
		"compensation teamplay bucket tracked separately"
	)

	local bucketTotals = ScoreState.GetBucketTotals(compensation.state)
	assertEqual(bucketTotals.normal.categories.objective, 500, "normal bucket global total")
	assertEqual(bucketTotals.bonus.categories.objective, 200, "bonus bucket global total")
end

do
	local state = newState()
	local low = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 9200,
		eventId = "objective_partial",
		actorRole = "Tinyfolk",
		metadata = { contributionRatio = 0.1 },
	})
	assertTrue(low.accepted, "low proportional contribution accepted")
	assertEqual(low.record.contributionRatio, 0.25, "low contribution clamps to minimum")
	assertEqual(low.record.rawPoints, 15, "low contribution raw points")
	assertEqual(low.record.awardedPoints, 15, "low contribution awarded points")

	local high = ScoreState.ResolveScoreEvent(low.state, {
		now = 100,
		userId = 9200,
		eventId = "objective_partial",
		actorRole = "Tinyfolk",
		metadata = { contributionRatio = 5 },
	})
	assertTrue(high.accepted, "high proportional contribution accepted")
	assertEqual(high.record.contributionRatio, 1, "high contribution clamps to maximum")
	assertEqual(high.record.rawPoints, 60, "high contribution raw points")
	assertEqual(high.record.awardedPoints, 60, "high contribution awarded points after repeat reset")
end

do
	local state = newState()
	local missing = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 9300,
		eventId = "objective_partial",
		actorRole = "Tinyfolk",
		metadata = nil,
	})
	assertFalse(missing.accepted, "missing proportional metadata rejected")
	assertEqual(missing.reason, "missing_contribution", "missing proportional metadata reason")
	assertEqual(missing.feedbackKey, "score_objective_partial", "missing proportional feedback key")
end

do
	local state = newState()
	local current = state
	for i = 1, 10 do
		local transition = ScoreState.ResolveScoreEvent(current, {
			now = i * 100,
			userId = 9400,
			eventId = "escape_success",
			actorRole = "Tinyfolk",
		})
		current = transition.state
	end

	local capped = ScoreState.ResolveScoreEvent(current, {
		now = 1200,
		userId = 9400,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
	})
	assertFalse(capped.accepted, "maxed category rejects normal award")
	assertEqual(capped.reason, "category_cap_reached", "maxed category reason")
	assertEqual(capped.categoryCapReached, true, "maxed category flag")
	assertEqual(capped.feedbackKey, "score_escape_success", "maxed category feedback key")
end

do
	local state = newState()
	local first = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 9500,
		eventId = "objective_partial",
		actorRole = "Tinyfolk",
		metadata = { contributionRatio = 1 },
	})
	local second = ScoreState.ResolveScoreEvent(first.state, {
		now = 2,
		userId = 9500,
		eventId = "objective_partial",
		actorRole = "Tinyfolk",
		metadata = { contributionRatio = 1 },
	})
	assertEqual(first.record.awardedPoints, 60, "first proportional repeat baseline")
	assertEqual(second.record.awardedPoints, 30, "proportional repeat depreciation")
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
	assertTrue(transition.record.metadata ~= largeMetadata, "metadata cloned instead of aliased")
	assertEqual(transition.record.metadata.key1000, "value1000", "cloned metadata value preserved")
	largeMetadata["key1000"] = "mutated"
	assertEqual(transition.record.metadata.key1000, "value1000", "record metadata immune to caller mutation")
end

do
	local state = newState()
	local transition = ScoreState.ResolveScoreEvent(state, {
		now = 1,
		userId = 6100,
		eventId = "escape_success",
		actorRole = "Tinyfolk",
	})

	local recentZero = ScoreState.GetRecentEvents(transition.state, 0)
	local recentNegative = ScoreState.GetRecentEvents(transition.state, -3)
	assertEqual(#recentZero, 0, "recent events with zero limit returns empty")
	assertEqual(#recentNegative, 0, "recent events with negative limit returns empty")
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

do
	local state: any = ScoreState.NewState()
	state.playerScores[8001] = { total = 15 }
	state.recentEvents = {
		{
			sequence = 1,
			userId = 8001,
			eventId = "legacy_score",
			category = "objective",
			awardedPoints = 15,
			now = 10,
		},
	}

	local snap = ScoreState.GetPlayerSnapshot(state, 8001)
	assertEqual(snap.total, 15, "legacy snapshot without categories preserves total")
	assertEqual(snap.categories.objective or 0, 0, "legacy snapshot missing categories returns empty category table")

	local recent = ScoreState.GetRecentEvents(state, 1)
	assertEqual(recent[1].bucket, "normal", "legacy recent event defaults bucket")
	assertEqual(recent[1].rawPoints, 15, "legacy recent event defaults raw points")
	assertEqual(recent[1].contributionRatio, 1, "legacy recent event defaults contribution ratio")
	assertEqual(recent[1].categoryCapReached, false, "legacy recent event defaults cap flag")
end

print("score_state: all checks passed")
