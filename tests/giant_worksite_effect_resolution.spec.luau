--!strict

local GiantWorksiteEffectResolution =
	require("../src/ReplicatedStorage/Shared/GiantRealm/GiantWorksiteEffectResolution")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

do
	local base = GiantWorksiteEffectResolution.ResolveEffects({
		shrineLevel = 0,
		dwellingLevel = 0,
	})
	assertEqual(base.maxHealth, 100, "base max health")
	assertEqual(base.walkSpeed, 16, "base walk speed")
	assertEqual(base.powerBudget, 100, "base power budget")
	assertEqual(base.movementControl, 1, "base movement control")
end

do
	local shrineMax = GiantWorksiteEffectResolution.ResolveEffects({
		shrineLevel = 3,
		dwellingLevel = 0,
	})
	assertEqual(shrineMax.maxHealthBonus, 50, "shrine L3 health parity")
	assertEqual(shrineMax.powerBudgetBonus, 25, "shrine L3 power parity")
	assertEqual(shrineMax.walkSpeedBonus, 0, "shrine L3 no walk bonus")
end

do
	local dwellingMax = GiantWorksiteEffectResolution.ResolveEffects({
		shrineLevel = 0,
		dwellingLevel = 3,
	})
	assertEqual(dwellingMax.walkSpeedBonus, 6, "dwelling L3 walk parity")
	assertEqual(dwellingMax.movementControlBonus, 0.25, "dwelling L3 movement parity")
	assertEqual(dwellingMax.maxHealthBonus, 0, "dwelling L3 no health bonus")
end

do
	local combined = GiantWorksiteEffectResolution.ResolveEffects({
		shrineLevel = 3,
		dwellingLevel = 3,
	})
	assertEqual(combined.maxHealth, 150, "combined max health")
	assertEqual(combined.walkSpeed, 22, "combined walk speed")
	assertEqual(combined.powerBudget, 125, "combined power budget")
	assertEqual(combined.movementControl, 1.25, "combined movement control")
end

print("giant_worksite_effect_resolution.spec.luau: all checks passed")
