--!strict

local GrabState = require("../src/ReplicatedStorage/Shared/GiantRealm/GrabState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function enterCarried(state: any, overrides: any?): any
	local params: any = {
		now = 10,
		carriedByUserId = 1,
		targetUserId = 2,
		cooldownSeconds = 0.5,
		counterplayRequired = 3,
		source = "test",
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			params[key] = value
		end
	end
	return GrabState.EnterCarried(state, params)
end

do
	local state = GrabState.New(0)
	local result = enterCarried(state)
	assertTrue(result.accepted, "valid carried entry accepted")
	assertEqual(result.snapshot.state, "Carried", "state becomes Carried")
	assertEqual(result.snapshot.carriedByUserId, 1, "snapshot includes carrier")
	assertEqual(result.snapshot.targetUserId, 2, "snapshot includes target")
	assertEqual(result.snapshot.cooldownEndsAt, 10.5, "cooldown ends deterministically")
end

do
	local state = GrabState.New(0)
	local result = enterCarried(state, { carriedByUserId = "missing" })
	assertFalse(result.accepted, "missing carrier rejected")
	assertEqual(result.reason, "carried_by_user_id_invalid", "missing carrier reason")
end

do
	local state = GrabState.New(0)
	enterCarried(state)
	local repeated = GrabState.CanAttemptGrab(state, 10.1)
	assertFalse(repeated.accepted, "already carried rejects grab attempt")
	assertEqual(repeated.reason, "already_carried", "already carried reason")
end

do
	local state = GrabState.New(0)
	enterCarried(state)
	local release = GrabState.Release(state, { now = 11, reason = "placed" })
	assertTrue(release.accepted, "release accepted")
	assertEqual(release.snapshot.state, "Released", "release sets Released state")
	assertEqual(release.snapshot.releaseReason, "placed", "release reason exposed")
	assertFalse(release.snapshot.isCarried, "release clears carried marker")
	local cooldown = GrabState.CanAttemptGrab(state, 10.25)
	assertFalse(cooldown.accepted, "cooldown rejects repeated attempt")
	assertEqual(cooldown.reason, "request_cooldown", "cooldown reason")
end

do
	local state = GrabState.New(0)
	enterCarried(state, { counterplayRequired = 2 })
	local first = GrabState.ApplyCounterplay(state, {
		now = 11,
		progressDelta = 1,
		counterplayCooldownSeconds = 0.25,
	})
	assertTrue(first.accepted, "first counterplay accepted")
	assertEqual(first.snapshot.state, "Counterplay", "counterplay state exposed")
	assertEqual(first.snapshot.counterplayProgress, 1, "counterplay progress increments")
	local repeated = GrabState.ApplyCounterplay(state, {
		now = 11.1,
		progressDelta = 1,
		counterplayCooldownSeconds = 0.25,
	})
	assertFalse(repeated.accepted, "counterplay cooldown rejects")
	assertEqual(repeated.reason, "counterplay_cooldown", "counterplay cooldown reason")
	local second = GrabState.ApplyCounterplay(state, {
		now = 11.3,
		progressDelta = 1,
		counterplayCooldownSeconds = 0.25,
	})
	assertTrue(second.accepted, "threshold counterplay accepted")
	assertEqual(second.snapshot.state, "Released", "threshold releases")
	assertEqual(second.snapshot.releaseReason, "counterplay_completed", "threshold release reason")
	assertFalse(second.snapshot.isCarried, "threshold clears carried marker")
end

do
	local state = GrabState.New(0)
	assertTrue(GrabState.CanPerformCarriedInteraction(state, "escapeAttempt"), "free actors can interact")
	enterCarried(state)
	assertFalse(GrabState.CanPerformCarriedInteraction(state, "escapeAttempt"), "carried actors cannot escape")
	assertTrue(
		GrabState.CanPerformCarriedInteraction(state, "carriedCounterplay"),
		"carried actors can counterplay"
	)
end

print("grab_state: all checks passed")
