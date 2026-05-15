--!strict

local DownedState = require("../src/ReplicatedStorage/Shared/GiantRealm/DownedState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function createState(): any
	return DownedState.New(0)
end

local function enter(state: any, overrides: any?): any
	local params: any = {
		now = 10,
		durationSeconds = 30,
		role = "Tinyfolk",
		source = "server_test",
		reason = "test_reason",
		selfRecoveryCap = 0.5,
		movementMultiplier = 0.35,
		interactionMask = {
			escapeAttempt = false,
		},
		safeZoneProtected = false,
		validSources = {
			server_test = true,
			giant_pressure = true,
		},
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			params[key] = value
		end
	end
	return DownedState.Enter(state, params)
end

do
	local state = createState()
	local result = enter(state)
	assertTrue(result.accepted, "valid down entry accepted")
	assertEqual(result.snapshot.status, "Downed", "status becomes Downed")
	assertEqual(result.snapshot.expiresAt, 40, "expiresAt set deterministically")
	assertEqual(result.snapshot.source, "server_test", "source captured")
end

do
	local state = createState()
	local result = enter(state, { role = "Giant" })
	assertEqual(result.accepted, false, "non-Tinyfolk rejected")
	assertEqual(result.reason, "target_not_tinyfolk", "non-Tinyfolk reason")
end

do
	local state = createState()
	local result = enter(state, { source = "invalid_source" })
	assertEqual(result.accepted, false, "invalid source rejected")
	assertEqual(result.reason, "source_invalid", "invalid source reason")
end

do
	local state = createState()
	local result = enter(state, { safeZoneProtected = true })
	assertEqual(result.accepted, false, "safe-zone target rejected")
	assertEqual(result.reason, "target_in_safe_zone", "safe-zone reason")
end

do
	local state = createState()
	local first = enter(state, { now = 20, durationSeconds = 30 })
	local second = enter(state, { now = 25, durationSeconds = 50 })
	assertEqual(first.accepted, true, "first down accepted")
	assertEqual(second.accepted, false, "repeated down rejected")
	assertEqual(second.reason, "already_downed", "repeated down reason")
	assertEqual(second.snapshot.expiresAt, 50, "repeated down does not extend indefinitely")
end

do
	local state = createState()
	enter(state)
	local recover = DownedState.SelfRecover(state, 15, 0.7)
	assertEqual(recover.accepted, true, "self recovery request accepted")
	assertEqual(recover.snapshot.status, "SelfRecoveryCapped", "self recovery clamps at cap")
	assertEqual(recover.snapshot.selfRecoveryProgress, 0.5, "self recovery progress clamped to cap")
end

do
	local state = createState()
	enter(state, { now = 100, durationSeconds = 5 })
	local tickResult = DownedState.Tick(state, 106)
	assertEqual(tickResult.accepted, true, "expiry tick accepted")
	assertEqual(tickResult.snapshot.status, "SafeResolved", "expiry resolves deterministically")
end

do
	local state = createState()
	enter(state)
	assertEqual(DownedState.CanPerformInteraction(state, "escapeAttempt"), false, "escape restricted while downed")
	assertEqual(
		DownedState.CanPerformInteraction(state, "debugInspect"),
		true,
		"debug interaction allowed while downed"
	)
end

do
	local state = createState()
	enter(state, { reason = "reason_for_debug" })
	local snapshot = DownedState.Snapshot(state)
	assertEqual(snapshot.reason, "reason_for_debug", "readable debug state includes reason")
	assertEqual(snapshot.carryEligibleMarker, true, "snapshot includes carry-eligible marker")
end

do
	local state = createState()
	local unsupported = DownedState.SelfRecover(state, 10, 0.1)
	assertEqual(unsupported.accepted, false, "future ally/carry/rescue path remains unsupported when not downed")
	assertEqual(unsupported.reason, "not_downed", "unsupported reason explicit")
end

print("downed_state: all checks passed")
