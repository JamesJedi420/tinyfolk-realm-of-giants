--!strict

local RansomSocialGateState = require("../src/ReplicatedStorage/Shared/GiantRealm/RansomSocialGateState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local blocked = RansomSocialGateState.ResolvePostGate(10, 20)
assertEqual(blocked.allowed, false, "post blocked below min control")
assertEqual(blocked.reason, "social_control_insufficient", "post blocked reason")

local allowed = RansomSocialGateState.ResolvePostGate(25, 20)
assertEqual(allowed.allowed, true, "post allowed at min control")

assertEqual(RansomSocialGateState.ResolveEffectiveFoodCost(10, 1), 10, "neutral bonus keeps cost")
assertEqual(RansomSocialGateState.ResolveEffectiveFoodCost(10, 2), 5, "favor bonus halves cost")
assertEqual(RansomSocialGateState.ResolveEffectiveFoodCost(10, nil), 10, "missing bonus neutral")

print("ransom_social_gate_state.spec.luau: all checks passed")
