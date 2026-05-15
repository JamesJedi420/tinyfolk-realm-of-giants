--!strict

local TraversalGapBlockState = require("../src/ReplicatedStorage/Shared/GiantRealm/TraversalGapBlockState")
local EscapeConfig = require("../src/ReplicatedStorage/Shared/Config/EscapeConfig")
local MatchSimulation: any = require("../tests/harness/MatchSimulation")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function create(now: number, existingRecord: any?): any
	return TraversalGapBlockState.CreateBlock(EscapeConfig, {
		routeId = "EscapeRoute_A",
		blockedByUserId = 101,
		now = now,
		existingRecord = existingRecord,
	})
end

do
	local result = create(10, nil)
	assertTrue(result.accepted, "valid request accepted")
	assertEqual(result.snapshot.state, "Startup", "valid request starts in Startup")
	assertEqual(result.record.startupStartedAt, 10, "startup starts at now")
	assertEqual(result.record.startupEndsAt, 11, "startup ends deterministically")
	assertEqual(result.record.activeStartsAt, 11, "active starts after startup")
	assertEqual(result.record.activeEndsAt, 15, "active ends after configured duration")
	assertEqual(result.record.expiresAt, 15, "expires at active end")
	assertEqual(TraversalGapBlockState.ResolveState(result.record, 11), "Active", "state becomes Active")
	assertEqual(TraversalGapBlockState.ResolveState(result.record, 15), "Expired", "state becomes Expired")
end

do
	local result = create(20, nil)
	assertFalse(
		TraversalGapBlockState.ShouldRejectTraversal(result.record, 20.5, false),
		"Startup does not reject traversal"
	)
	assertTrue(TraversalGapBlockState.ShouldRejectTraversal(result.record, 21, false), "Active rejects traversal")
	assertFalse(
		TraversalGapBlockState.ShouldRejectTraversal(result.record, 25, false),
		"Expired does not reject traversal"
	)
end

do
	local result = create(30, nil)
	assertFalse(
		TraversalGapBlockState.ShouldRejectTraversal(result.record, 31, true),
		"explicit exemption allows traversal despite Active block"
	)
end

do
	local first = create(40, nil)
	local repeatedStartup = create(40.5, first.record)
	local repeatedActive = create(41, first.record)

	assertFalse(repeatedStartup.accepted, "repeated Startup block rejected")
	assertEqual(repeatedStartup.reason, "block_startup", "repeated Startup reason")
	assertEqual(repeatedStartup.record, first.record, "repeated Startup does not refresh record")
	assertFalse(repeatedActive.accepted, "repeated Active block rejected")
	assertEqual(repeatedActive.reason, "block_active", "repeated Active reason")
	assertEqual(repeatedActive.record, first.record, "repeated Active does not refresh record")
end

do
	local first = create(50, nil)
	local afterExpired = create(55, first.record)

	assertTrue(afterExpired.accepted, "expired block allows new block")
	assertEqual(afterExpired.record.startupStartedAt, 55, "new block uses fresh start time")
end

do
	local sim = MatchSimulation.new({ clock = os.clock })
	sim:addPlayer(1, "GiantPlayer", { role = "Giant" })

	sim:queueAction(1, "blockTraversalGap", {
		userId = 1,
		routeId = "EscapeRoute_A",
		config = {
			TraversalGapBlockStartupSeconds = 1,
			TraversalGapBlockActiveSeconds = 4,
		},
	})

	sim:advanceTick()

	local log = sim:getLog()
	assertEqual(log[2], "[Tick 1] Traversal gap block by GiantPlayer: Accepted", "Traversal-gap block succeeds")
end

print("traversal_gap_block_state: all checks passed")
