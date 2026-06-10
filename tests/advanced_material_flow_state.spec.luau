--!nocheck

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local AdvancedMaterialFlowConfig = require("../src/ReplicatedStorage/Shared/Config/AdvancedMaterialFlowConfig")
local AdvancedMaterialFlowState = require("../src/ReplicatedStorage/Shared/GiantRealm/AdvancedMaterialFlowState")

do
	local grants, reason = AdvancedMaterialFlowState.ResolveInventoryGrants("Metal", 2, AdvancedMaterialFlowConfig)
	assertEqual(reason, nil, "metal grant reason")
	assertEqual(grants.iron_filings, 2, "metal grants iron_filings per unit")
end

do
	local grants, reason = AdvancedMaterialFlowState.ResolveInventoryGrants("Stone", 4, AdvancedMaterialFlowConfig)
	assertEqual(reason, nil, "stone grant reason")
	assertEqual(grants.stone_shard, 2, "stone grants stone_shard per two units")
end

do
	local grants, reason = AdvancedMaterialFlowState.ResolveInventoryGrants("Wood", 4, AdvancedMaterialFlowConfig)
	assertEqual(reason, nil, "wood has no configured grants")
	assertEqual(next(grants), nil, "wood grant table empty")
end

do
	local grants, reason = AdvancedMaterialFlowState.ResolveInventoryGrants("Stone", 1, AdvancedMaterialFlowConfig)
	assertEqual(reason, nil, "partial stone grant reason")
	assertEqual(next(grants), nil, "partial stone below grant threshold")
end

print("advanced_material_flow_state.spec.luau: all checks passed")
