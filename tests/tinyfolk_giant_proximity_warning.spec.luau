--!nocheck
local Config = require("../src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local TimedConditionStateLogic = require("../src/ReplicatedStorage/Shared/TinyfolkStatus/TimedConditionStateLogic")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function makePosition(x: number, y: number, z: number): any
	return { X = x, Y = y, Z = z }
end

do
	assertEqual(
		TimedConditionStateLogic.ResolveGiantProximityWarningLevel(Config, 0, false),
		"none",
		"zero exposure has no warning"
	)
	assertEqual(
		TimedConditionStateLogic.ResolveGiantProximityWarningLevel(Config, 0.1, false),
		"watch",
		"watch warning threshold"
	)
	assertEqual(
		TimedConditionStateLogic.ResolveGiantProximityWarningLevel(Config, 0.45, false),
		"near",
		"near warning threshold"
	)
	assertEqual(
		TimedConditionStateLogic.ResolveGiantProximityWarningLevel(Config, 0.75, false),
		"danger",
		"danger warning threshold"
	)
	assertEqual(
		TimedConditionStateLogic.ResolveGiantProximityWarningLevel(Config, 0.2, true),
		"danger",
		"panic escalates warning without distance"
	)
end

do
	local _nextState, snapshot = TimedConditionStateLogic.ResolveTick({}, Config, {
		now = 10,
		position = makePosition(0, 0, 0),
		isTinyfolk = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
		nearbyFearSources = {
			{ userId = 2001, position = makePosition(36, 0, 0) },
			{ userId = 2002, position = makePosition(12, 0, 0) },
		},
	})

	assertEqual(snapshot.fearExposureRatio, 0.8, "nearest alive giant still drives fear exposure")
	assertEqual(snapshot.giantProximityWarningLevel, "danger", "multiple giants collapse to one coarse warning")
	assertTrue(snapshot.fearNearestGiantUserId ~= nil, "internal snapshot may retain nearest source for server logic")
end

do
	local _nextState, snapshot = TimedConditionStateLogic.ResolveTick({}, Config, {
		now = 10,
		position = makePosition(0, 0, 0),
		isTinyfolk = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
		nearbyFearSources = {
			{ userId = "bad", position = nil },
			{ userId = 2003, position = { X = 1, Y = "bad", Z = 0 } },
		},
	})

	assertEqual(snapshot.fearExposureRatio, 0, "malformed sources ignored")
	assertEqual(snapshot.giantProximityWarningLevel, "none", "malformed sources produce no warning")
	assertEqual(snapshot.fearNearestGiantUserId, nil, "malformed sources do not select a source")
end

do
	local _nextState, snapshot = TimedConditionStateLogic.ResolveTick({}, Config, {
		now = 10,
		position = makePosition(0, 0, 0),
		isTinyfolk = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
		nearbyFearSources = {
			{ userId = 2004, position = { X = 0 / 0, Y = 0, Z = 0 } },
			{ userId = 2005, position = { X = math.huge, Y = 0, Z = 0 } },
		},
	})

	assertEqual(snapshot.fearExposureRatio, 0, "non-finite source positions ignored")
	assertEqual(snapshot.giantProximityWarningLevel, "none", "non-finite source positions produce no warning")
	assertEqual(snapshot.fearNearestGiantUserId, nil, "non-finite source positions do not select a source")
end

do
	local _nextState, snapshot = TimedConditionStateLogic.ResolveTick({}, Config, {
		now = 10,
		position = makePosition(0, 0, 0),
		isTinyfolk = true,
		hasAliveHumanoid = true,
		hasRootPart = true,
		nearbyFearSources = {},
	})

	assertEqual(snapshot.fearExposureRatio, 0, "empty source set has no exposure")
	assertEqual(snapshot.giantProximityWarningLevel, "none", "empty source set clears warning")
end

print("tinyfolk_giant_proximity_warning: all checks passed")
