--!strict

local GiantHousingCapacityState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantHousingCapacityState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

do
	local published = GiantHousingCapacityState.ResolvePublishedCapacity(1, 1)
	assertEqual(published, 1, "base housing capacity level 0")
end

do
	local published = GiantHousingCapacityState.ResolvePublishedCapacity(1, 2)
	assertEqual(published, 2, "housing capacity scales with upgrade multiplier")
end

do
	local maxGiants = GiantHousingCapacityState.ResolveMaxGiantsFromHousing(2)
	assertEqual(maxGiants, 2, "realm max giants from published housing")
end

print("giant_housing_capacity_state.spec.luau: all checks passed")
