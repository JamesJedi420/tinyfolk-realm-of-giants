local PostRescueProtectionState = require("../src/ReplicatedStorage/Shared/GiantRealm/PostRescueProtectionState")

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

local active = PostRescueProtectionState.Evaluate({
	protected = true,
	expiresAt = 20,
	at = 10,
	isDowned = false,
})
assertTrue(active.active, "active protection accepted")
assertFalse(active.shouldClear, "active protection does not clear")

local expired = PostRescueProtectionState.Evaluate({
	protected = true,
	expiresAt = 10,
	at = 10,
	isDowned = false,
})
assertFalse(expired.active, "expired protection inactive")
assertTrue(expired.shouldClear, "expired protection clears")

local downed = PostRescueProtectionState.Evaluate({
	protected = true,
	expiresAt = 20,
	at = 10,
	isDowned = true,
})
assertFalse(downed.active, "downed cancels protection")
assertEqual(downed.clearReason, PostRescueProtectionState.BreakingActions.downed, "downed clear reason")

local objectiveBreak = PostRescueProtectionState.Evaluate({
	protected = true,
	expiresAt = 20,
	at = 10,
	isDowned = false,
	breakingAction = PostRescueProtectionState.BreakingActions.objective_task_complete,
})
assertFalse(objectiveBreak.active, "objective completion cancels protection")
assertTrue(objectiveBreak.shouldClear, "objective completion should clear")

assertEqual(
	PostRescueProtectionState.GetMovementSpeedMultiplier({ PostRescueMovementSpeedMultiplier = 1.2 }),
	1.2,
	"movement multiplier from config"
)
assertEqual(
	PostRescueProtectionState.GetEscapeCooldownMultiplier({ PostRescueEscapeCooldownMultiplier = 0.4 }),
	0.4,
	"escape cooldown multiplier from config"
)

print("post_rescue_protection_state: all checks passed")
