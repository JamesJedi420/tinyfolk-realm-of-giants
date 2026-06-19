--!strict

local LaborComplianceState = require("../src/ReplicatedStorage/Shared/GiantRealm/LaborComplianceState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

assertEqual(LaborComplianceState.ApplyComplianceYield(4, 1.25), 5, "yield scales up with bonus")
assertEqual(LaborComplianceState.ApplyComplianceYield(4, nil), 4, "neutral bonus unchanged")
assertEqual(LaborComplianceState.ApplyComplianceYield(1, 1.5), 1, "minimum yield of 1 when base positive")
assertEqual(LaborComplianceState.ApplyComplianceYield(0, 1.5), 0, "zero base stays zero")

local mockApi = {
	GetEffectSnapshot = function(_targetUserId: number?)
		return { favorComplianceBonus = 1.2 }
	end,
}
assertEqual(LaborComplianceState.ResolveFavorComplianceBonus(mockApi, 101), 1.2, "reads snapshot bonus")
assertEqual(LaborComplianceState.ResolveFavorComplianceBonus(nil, 101), 1, "missing api neutral")

print("labor_compliance_state.spec.luau: all checks passed")
