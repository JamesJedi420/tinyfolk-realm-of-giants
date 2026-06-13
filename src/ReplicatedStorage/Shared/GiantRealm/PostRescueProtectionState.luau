--!strict

local PostRescueProtectionState = {}

PostRescueProtectionState.BreakingActions = {
	downed = "downed",
	objective_task_complete = "objective_task_complete",
}

local breakingActions = {
	[PostRescueProtectionState.BreakingActions.downed] = true,
	[PostRescueProtectionState.BreakingActions.objective_task_complete] = true,
}

local DEFAULT_MOVEMENT_SPEED_MULTIPLIER = 1.15
local DEFAULT_ESCAPE_COOLDOWN_MULTIPLIER = 0.5

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

function PostRescueProtectionState.IsBreakingAction(action: any): boolean
	return type(action) == "string" and breakingActions[action] == true
end

function PostRescueProtectionState.GetMovementSpeedMultiplier(config: any): number
	local value = if config ~= nil then config.PostRescueMovementSpeedMultiplier else nil
	if isFiniteNumber(value) and (value :: number) > 0 then
		return value :: number
	end
	return DEFAULT_MOVEMENT_SPEED_MULTIPLIER
end

function PostRescueProtectionState.GetEscapeCooldownMultiplier(config: any): number
	local value = if config ~= nil then config.PostRescueEscapeCooldownMultiplier else nil
	if isFiniteNumber(value) and (value :: number) > 0 and (value :: number) <= 1 then
		return value :: number
	end
	return DEFAULT_ESCAPE_COOLDOWN_MULTIPLIER
end

function PostRescueProtectionState.Evaluate(input: any): any
	if type(input) ~= "table" then
		return {
			active = false,
			shouldClear = false,
			clearReason = nil,
		}
	end

	local breakingAction = input.breakingAction
	if PostRescueProtectionState.IsBreakingAction(breakingAction) then
		return {
			active = false,
			shouldClear = true,
			clearReason = breakingAction,
		}
	end

	if input.protected ~= true then
		return {
			active = false,
			shouldClear = false,
			clearReason = nil,
		}
	end

	if input.isDowned == true then
		return {
			active = false,
			shouldClear = true,
			clearReason = PostRescueProtectionState.BreakingActions.downed,
		}
	end

	local at = input.at
	local expiresAt = input.expiresAt
	if not isFiniteNumber(at) or not isFiniteNumber(expiresAt) then
		return {
			active = false,
			shouldClear = true,
			clearReason = "invalid_expiry",
		}
	end

	if (expiresAt :: number) <= (at :: number) then
		return {
			active = false,
			shouldClear = true,
			clearReason = "expired",
		}
	end

	return {
		active = true,
		shouldClear = false,
		clearReason = nil,
	}
end

return PostRescueProtectionState
