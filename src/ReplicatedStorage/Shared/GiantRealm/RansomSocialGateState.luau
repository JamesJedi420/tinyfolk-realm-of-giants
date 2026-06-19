--!strict

local RansomSocialGateState = {}

export type PostGateResult = {
	allowed: boolean,
	reason: string,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function RansomSocialGateState.ResolvePostGate(control: number, minControl: number): PostGateResult
	local resolvedMin = if isFiniteNumber(minControl) and minControl >= 0 then minControl else 0
	local resolvedControl = if isFiniteNumber(control) then control else 0
	if resolvedControl < resolvedMin then
		return { allowed = false, reason = "social_control_insufficient" }
	end
	return { allowed = true, reason = "accepted" }
end

function RansomSocialGateState.ResolveEffectiveFoodCost(baseCost: number, favorComplianceBonus: number?): number
	if not isFiniteNumber(baseCost) or baseCost <= 0 then
		return 0
	end

	local resolvedBonus = 1
	if isFiniteNumber(favorComplianceBonus) and (favorComplianceBonus :: number) > 0 then
		resolvedBonus = favorComplianceBonus :: number
	end

	local effectiveCost = math.ceil(baseCost / resolvedBonus)
	return math.min(baseCost, math.max(1, effectiveCost))
end

return RansomSocialGateState
