--!nocheck

-- Minimal Vector3 implementation for test
local globalEnv = getfenv()

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, Vector3)
end
function Vector3.__sub(a, b)
	return Vector3.new(a.x - b.x, a.y - b.y, a.z - b.z)
end
function Vector3:Magnitude()
	return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

setmetatable(Vector3, {
	__call = function(_, ...)
		return Vector3.new(...)
	end,
})

-- Patch global Vector3 for code under test
globalEnv.Vector3 = Vector3

local HidingState = require("../src/ReplicatedStorage/Shared/TinyfolkHiding/HidingState")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local now = 100
local duration = 10
local zoneId = "ZoneA"
local state = HidingState.new()

assertEqual(state.isHiding, false, "initial not hiding")
state:Enter(zoneId, now, duration)
assertEqual(state.isHiding, true, "enter sets isHiding")
assertEqual(state.zoneId, zoneId, "enter sets zoneId")
assertEqual(state.hiddenStartedAt, now, "enter sets hiddenStartedAt")
assertEqual(state.endsAt, now + duration, "enter sets endsAt")

local snapshot = state:GetSnapshot(now + 5)
assertEqual(snapshot.isHiding, true, "snapshot isHiding true")
assertEqual(snapshot.zoneId, zoneId, "snapshot zoneId")
assertEqual(snapshot.hiddenFor, 5, "snapshot hiddenFor")

local shouldReveal, reason = state:ProbeReveal(now + 11, 10, {}, Vector3.new(0, 0, 0))
assertEqual(shouldReveal, true, "timeout triggers reveal")
assertEqual(reason, "timeout", "timeout reason")

state:Exit("manual", now + 12)
assertEqual(state.isHiding, false, "exit clears isHiding")
assertEqual(state.zoneId, nil, "exit clears zoneId")
assertEqual(state.lastRevealReason, "manual", "exit sets lastRevealReason")

state:Enter(zoneId, now + 20, duration)
local giantNear = { Vector3.new(1, 0, 0) }
shouldReveal, reason = state:ProbeReveal(now + 21, 10, giantNear, Vector3.new(0, 0, 0))
assertEqual(shouldReveal, true, "giant proximity triggers reveal")
assertEqual(reason, "giant_proximity", "giant proximity reason")

print("tinyfolk_hiding_state: all checks passed")
