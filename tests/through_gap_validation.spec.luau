--!strict

local ThroughGapValidation = require("../src/ReplicatedStorage/Shared/GiantRealm/ThroughGapValidation")
local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local EscapeConfig = require("../src/ReplicatedStorage/Shared/Config/EscapeConfig")

local MockVector3: any = {}
MockVector3.__index = MockVector3

function MockVector3.new(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, MockVector3)
end

function MockVector3.Magnitude(self: any)
	return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2)
end

function MockVector3.__sub(a, b)
	return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, MockVector3)
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function run(overrides: any): any
	local params: any = {
		callerRole = RoleConfig.Roles.Giant,
		targetRole = RoleConfig.Roles.Tinyfolk,
		routeType = "TraversalGap",
		routeAllowsThroughGapReach = true,
		callerPosition = MockVector3.new(0, 0, 0),
		targetPosition = MockVector3.new(0, 0, 5),
		distanceThreshold = 10,
		angleThreshold = nil,
		lineOfSightCheck = function()
			return true
		end,
		safeZoneState = false,
		crossingPhaseValid = true,
	}

	for key, value in overrides do
		params[key] = value
	end

	return ThroughGapValidation.ValidateReachAttempt({
		EscapeConfig = EscapeConfig,
		RoleConfig = RoleConfig,
	}, params)
end

do
	local result = run({})
	assertEqual(result.valid, true, "explicit allowed gap accepts valid reach")
end

do
	local result = run({ routeAllowsThroughGapReach = false })
	assertEqual(result.valid, false, "missing allowlist metadata rejects")
end

do
	local result = run({ routeType = "OpenField" })
	assertEqual(result.valid, false, "unsupported route type rejects")
end

do
	local result = run({ callerRole = RoleConfig.Roles.Tinyfolk })
	assertEqual(result.valid, false, "non-Giant caller rejects")
end

do
	local result = run({ targetRole = RoleConfig.Roles.Giant })
	assertEqual(result.valid, false, "non-Tinyfolk target rejects")
end

do
	local result = run({ targetPosition = MockVector3.new(0, 0, 20) })
	assertEqual(result.valid, false, "out-of-range rejects")
end

do
	local result = run({ safeZoneState = true })
	assertEqual(result.valid, false, "safe-zone target rejects")
end

do
	local result = run({ crossingPhaseValid = false })
	assertEqual(result.valid, false, "not-crossing target rejects")
end

do
	local result = run({
		lineOfSightCheck = function()
			return false
		end,
	})
	assertEqual(result.valid, false, "blocked LOS callback rejects")
end
