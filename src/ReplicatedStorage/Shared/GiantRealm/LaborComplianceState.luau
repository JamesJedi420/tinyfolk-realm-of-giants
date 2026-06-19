--!strict

local LaborComplianceState = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function LaborComplianceState.ApplyComplianceYield(baseAmount: number, complianceBonus: number?): number
	if not isFiniteNumber(baseAmount) or baseAmount <= 0 then
		return if isFiniteNumber(baseAmount) then baseAmount else 0
	end

	local resolvedBonus = 1
	if isFiniteNumber(complianceBonus) and (complianceBonus :: number) > 0 then
		resolvedBonus = complianceBonus :: number
	end

	local scaled = math.floor(baseAmount * resolvedBonus)
	return math.max(1, scaled)
end

function LaborComplianceState.ResolveFavorComplianceBonus(queryApi: any?, targetUserId: number?): number
	if type(queryApi) ~= "table" or type(queryApi.GetEffectSnapshot) ~= "function" then
		return 1
	end

	local effectSnapshot = queryApi.GetEffectSnapshot(targetUserId)
	if type(effectSnapshot) ~= "table" then
		return 1
	end

	local complianceBonus = effectSnapshot.favorComplianceBonus
	if type(complianceBonus) ~= "number" or complianceBonus ~= complianceBonus or complianceBonus <= 0 then
		return 1
	end

	return complianceBonus
end

return LaborComplianceState
