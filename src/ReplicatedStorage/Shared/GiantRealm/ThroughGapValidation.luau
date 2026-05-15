--!strict

-- ThroughGapValidation: Validates Giant through-gap reach attempts.

local ThroughGapValidation = {}

export type ValidationResult = {
	valid: boolean,
	reason: string?,
}

function ThroughGapValidation.ValidateReachAttempt(
	configs: {
		EscapeConfig: any,
		RoleConfig: any,
	},
	params: {
		callerRole: string,
		targetRole: string,
		routeType: string?,
		routeAllowsThroughGapReach: boolean,
		callerPosition: any,
		targetPosition: any,
		distanceThreshold: number,
		angleThreshold: number?,
		lineOfSightCheck: ((any, any) -> boolean)?,
		safeZoneState: boolean,
		crossingPhaseValid: boolean,
	}
): ValidationResult
	local EscapeConfig = configs.EscapeConfig
	local RoleConfig = configs.RoleConfig

	-- Validate roles
	if params.callerRole ~= RoleConfig.Roles.Giant then
		return { valid = false, reason = "caller_not_giant" }
	end
	if params.targetRole ~= RoleConfig.Roles.Tinyfolk then
		return { valid = false, reason = "target_not_tinyfolk" }
	end

	if params.routeAllowsThroughGapReach ~= true then
		return { valid = false, reason = "route_disallows_through_gap_reach" }
	end

	if type(params.routeType) ~= "string" then
		return { valid = false, reason = "route_type_missing" }
	end

	if EscapeConfig.SupportedThroughGapRouteTypes[params.routeType] ~= true then
		return { valid = false, reason = "route_type_unsupported" }
	end

	-- Validate positions
	if not params.callerPosition or not params.targetPosition then
		return { valid = false, reason = "missing_position_data" }
	end

	-- Validate distance
	local delta = params.callerPosition - params.targetPosition
	local distance: number? = nil
	if type(delta) == "table" and type((delta :: any).Magnitude) == "function" then
		distance = (delta :: any):Magnitude()
	elseif type(delta) == "table" and type((delta :: any).Magnitude) == "number" then
		distance = (delta :: any).Magnitude
	elseif type(delta) == "number" then
		distance = math.abs(delta)
	end

	if distance == nil then
		return { valid = false, reason = "distance_unavailable" }
	end

	if distance > params.distanceThreshold then
		return { valid = false, reason = "target_out_of_range" }
	end

	-- Validate angle (if applicable)
	if params.angleThreshold then
		return { valid = false, reason = "angle_validation_not_implemented" }
	end

	-- Validate line of sight
	local lineOfSightCheck = params.lineOfSightCheck
	if type(lineOfSightCheck) ~= "function" then
		return { valid = false, reason = "line_of_sight_check_missing" }
	end

	local lineOfSightCheckFn: any = lineOfSightCheck

	if not lineOfSightCheckFn(params.callerPosition, params.targetPosition) then
		return { valid = false, reason = "line_of_sight_blocked" }
	end

	-- Validate safe-zone state
	if params.safeZoneState then
		return { valid = false, reason = "target_in_safe_zone" }
	end

	-- Validate crossing phase
	if not params.crossingPhaseValid then
		return { valid = false, reason = "invalid_crossing_phase" }
	end

	-- All validations passed
	return { valid = true, reason = nil }
end

return ThroughGapValidation
