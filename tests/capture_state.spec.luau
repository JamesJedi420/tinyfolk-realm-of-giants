--!nocheck
local CaptureState = require("../src/ReplicatedStorage/Shared/GiantRealm/CaptureState")

local function assert(condition: boolean, message: string)
	if not condition then
		error(message)
	end
end

local testsPassed = 0
local testsFailed = 0

local function test(name: string, fn: () -> ())
	local success, err = pcall(fn)
	if success then
		testsPassed += 1
		print("✓", name)
	else
		testsFailed += 1
		print("✗", name)
		print("  ", err)
	end
end

local function resetState()
	return CaptureState.NewState()
end

test("NewState returns empty state", function()
	local state = resetState()
	assert(state.captureByTarget ~= nil, "captureByTarget missing")
	assert(state.custodianByTarget ~= nil, "custodianByTarget missing")
	assert(#state.captureByTarget == 0, "captureByTarget not empty")
	assert(#state.custodianByTarget == 0, "custodianByTarget not empty")
end)

test("ResolveRequest rejects invalid_now", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 0 / 0,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject invalid now")
	assert(result.reason == "invalid_now", "reason should be invalid_now")
end)

test("ResolveRequest rejects custodian_not_giant", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Tinyfolk",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject non-giant custodian")
	assert(result.reason == "custodian_not_giant", "reason should be custodian_not_giant")
end)

test("ResolveRequest rejects target_not_tinyfolk", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Giant",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject non-tinyfolk target")
	assert(result.reason == "target_not_tinyfolk", "reason should be target_not_tinyfolk")
end)

test("ResolveRequest rejects custodian_not_alive", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = false,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject dead custodian")
	assert(result.reason == "custodian_not_alive", "reason should be custodian_not_alive")
end)

test("ResolveRequest rejects target_not_downed", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = false,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject non-downed target")
	assert(result.reason == "target_not_downed", "reason should be target_not_downed")
end)

test("ResolveRequest rejects target_out_of_range", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = false,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject out of range")
	assert(result.reason == "target_out_of_range", "reason should be target_out_of_range")
end)

test("ResolveRequest accepts valid capture", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == true, "should accept valid capture")
	assert(result.reason == "accepted", "reason should be accepted")
	assert(result.record ~= nil, "record should exist")
	if result.record then
		assert(result.record.custodianUserId == 1, "custodian user id mismatch")
		assert(result.record.targetUserId == 2, "target user id mismatch")
		assert(result.record.startedAt == 1, "started at mismatch")
		assert(result.record.expiresAt == 9, "expires at should be now + custody window")
	end
end)

test("ResolveRequest rejects target_already_captured", function()
	local state = resetState()

	local firstResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local secondResult = CaptureState.ResolveRequest(firstResult.state, {
		now = 2,
		custodianUserId = 3,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	assert(secondResult.accepted == false, "should reject duplicate capture")
	assert(secondResult.reason == "target_already_captured", "reason should be target_already_captured")
end)

test("ResolveRequest rejects custodian_already_holding", function()
	local state = resetState()

	local firstResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local secondResult = CaptureState.ResolveRequest(firstResult.state, {
		now = 2,
		custodianUserId = 1,
		targetUserId = 3,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	assert(secondResult.accepted == false, "should reject custodian already holding")
	assert(secondResult.reason == "custodian_already_holding", "reason should be custodian_already_holding")
end)

test("PruneExpired removes expired captures", function()
	local state = resetState()

	local acceptResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 5,
	})

	assert(acceptResult.record ~= nil, "record should exist")
	if acceptResult.record then
		assert(acceptResult.record.expiresAt == 6, "expires at should be 6")
	end

	local pruned = CaptureState.PruneExpired(acceptResult.state, 7)
	local captures = CaptureState.GetAllCaptures(pruned)
	assert(#captures == 0, "should have no captures after expiry")
end)

test("PruneExpired keeps non-expired captures", function()
	local state = resetState()

	local acceptResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 5,
	})

	local pruned = CaptureState.PruneExpired(acceptResult.state, 5)
	local captures = CaptureState.GetAllCaptures(pruned)
	assert(#captures == 1, "should still have 1 capture")
end)

test("ResolveRelease removes active capture", function()
	local state = resetState()

	local acceptResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local releaseResult = CaptureState.ResolveRelease(acceptResult.state, {
		now = 3,
		targetUserId = 2,
	})

	assert(releaseResult.accepted == true, "should accept release")
	assert(releaseResult.reason == "released", "reason should be released")

	local captures = CaptureState.GetAllCaptures(releaseResult.state)
	assert(#captures == 0, "should have no captures after release")
end)

test("ResolveRelease rejects capture_missing", function()
	local state = resetState()
	local result = CaptureState.ResolveRelease(state, {
		now = 1,
		targetUserId = 2,
	})
	assert(result.accepted == false, "should reject missing capture")
	assert(result.reason == "capture_missing", "reason should be capture_missing")
end)

test("GetTargetCapture returns active capture", function()
	local state = resetState()

	local acceptResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local record = CaptureState.GetTargetCapture(acceptResult.state, 2)
	assert(record ~= nil, "should have record for target")
	if record then
		assert(record.custodianUserId == 1, "custodian user id mismatch")
		assert(record.targetUserId == 2, "target user id mismatch")
	end
end)

test("GetCustodianCapture returns active capture", function()
	local state = resetState()

	local acceptResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local record = CaptureState.GetCustodianCapture(acceptResult.state, 1)
	assert(record ~= nil, "should have record for custodian")
	if record then
		assert(record.targetUserId == 2, "target user id mismatch")
	end
end)

test("GetAllCaptures returns all captures sorted", function()
	local state = resetState()

	local result1 = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local result2 = CaptureState.ResolveRequest(result1.state, {
		now = 1,
		custodianUserId = 3,
		targetUserId = 4,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local captures = CaptureState.GetAllCaptures(result2.state)
	assert(#captures == 2, "should have 2 captures")
end)

test("RemovePlayer clears custodian captures", function()
	local state = resetState()

	local acceptResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local cleaned = CaptureState.RemovePlayer(acceptResult.state, 1)
	local captures = CaptureState.GetAllCaptures(cleaned)
	assert(#captures == 0, "should have no captures after custodian removal")
end)

test("RemovePlayer clears target captures", function()
	local state = resetState()

	local acceptResult = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})

	local cleaned = CaptureState.RemovePlayer(acceptResult.state, 2)
	local captures = CaptureState.GetAllCaptures(cleaned)
	assert(#captures == 0, "should have no captures after target removal")
end)

test("ResolveRequest rejects invalid_custodian_user_id", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = -1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject negative custodian user id")
	assert(result.reason == "invalid_custodian_user_id", "reason should be invalid_custodian_user_id")
end)

test("ResolveRequest rejects invalid_target_user_id", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 0,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject zero target user id")
	assert(result.reason == "invalid_target_user_id", "reason should be invalid_target_user_id")
end)

test("ResolveRequest rejects self_capture_not_allowed", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 1,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 8,
	})
	assert(result.accepted == false, "should reject self-capture")
	assert(result.reason == "self_capture_not_allowed", "reason should be self_capture_not_allowed")
end)

test("ResolveRequest rejects custody_window_invalid", function()
	local state = resetState()
	local result = CaptureState.ResolveRequest(state, {
		now = 1,
		custodianUserId = 1,
		targetUserId = 2,
		custodianRole = "Giant",
		targetRole = "Tinyfolk",
		custodianAlive = true,
		targetDowned = true,
		inRange = true,
		custodyWindowSeconds = 100,
	})
	assert(result.accepted == false, "should reject excessive custody window")
	assert(result.reason == "custody_window_invalid", "reason should be custody_window_invalid")
end)

print("\n" .. testsPassed .. " passed, " .. testsFailed .. " failed")
if testsFailed > 0 then
	error(testsFailed .. " tests failed")
end
