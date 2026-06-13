local AntiGuardingContainmentPressureState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/AntiGuardingContainmentPressureState")
local CaptureConfig = require("../src/ReplicatedStorage/Shared/Config/CaptureConfig")

local function assertTrue(value: any, message: string)
	if value ~= true then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function assertFalse(value: any, message: string)
	if value ~= false then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function assertEqual(actual: any, expected: any, message: string)
	if actual ~= expected then
		error(string.format("%s (expected=%s actual=%s)", message, tostring(expected), tostring(actual)))
	end
	print("PASS [" .. message .. "]")
end

local state = AntiGuardingContainmentPressureState.NewState(10, 10)
local graceTick = AntiGuardingContainmentPressureState.ResolveTick(state, {
	now = 12,
	containedAt = 10,
	custodianInProximity = true,
}, CaptureConfig)
assertEqual(graceTick.snapshot.phase, AntiGuardingContainmentPressureState.Phases.grace, "grace window blocks pressure")
assertEqual(graceTick.snapshot.pressure, 0, "grace window keeps pressure at zero")

local afterGrace = AntiGuardingContainmentPressureState.ResolveTick(graceTick.state, {
	now = 14,
	containedAt = 10,
	custodianInProximity = true,
}, CaptureConfig)
assertEqual(
	afterGrace.snapshot.phase,
	AntiGuardingContainmentPressureState.Phases.accumulating,
	"post-grace proximity accumulates"
)
assertTrue(afterGrace.snapshot.pressure > 0, "post-grace pressure increases")

local away = AntiGuardingContainmentPressureState.ResolveTick(afterGrace.state, {
	now = 14.5,
	containedAt = 10,
	custodianInProximity = false,
}, CaptureConfig)
assertEqual(
	away.snapshot.phase,
	AntiGuardingContainmentPressureState.Phases.decaying,
	"leaving proximity decays pressure"
)
assertTrue(away.snapshot.pressure < afterGrace.snapshot.pressure, "pressure falls when custodian leaves")

local sustained = AntiGuardingContainmentPressureState.NewState(0, 0)
local tickOne = AntiGuardingContainmentPressureState.ResolveTick(sustained, {
	now = 4,
	containedAt = 0,
	custodianInProximity = true,
}, CaptureConfig)
local tickTwo = AntiGuardingContainmentPressureState.ResolveTick(tickOne.state, {
	now = 10,
	containedAt = 0,
	custodianInProximity = true,
}, CaptureConfig)
assertTrue(tickTwo.counterplayReady, "sustained guarding reaches counterplay threshold")
assertEqual(tickTwo.snapshot.phase, AntiGuardingContainmentPressureState.Phases.ready, "ready phase at full pressure")

assertTrue(AntiGuardingContainmentPressureState.IsCustodianInProximity(8, CaptureConfig), "within proximity radius")
assertFalse(AntiGuardingContainmentPressureState.IsCustodianInProximity(20, CaptureConfig), "outside proximity radius")

local consumed = AntiGuardingContainmentPressureState.ResolveCounterplayConsumed(tickTwo.state, 10)
local consumedSnapshot = AntiGuardingContainmentPressureState.Snapshot(consumed, 10, CaptureConfig)
assertEqual(consumedSnapshot.phase, AntiGuardingContainmentPressureState.Phases.consumed, "counterplay marks consumed")

print("anti_guarding_containment_pressure_state: all checks passed")
