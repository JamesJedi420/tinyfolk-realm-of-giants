--!nocheck

local ConstructionSpendState = require("../src/ReplicatedStorage/Shared/Construction/ConstructionSpendState")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertNil(actual: any, label: string)
	if actual ~= nil then
		error(string.format("FAIL [%s]: expected nil got %s", label, tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local normalized, normalizeError = ConstructionSpendState.NormalizeCostEntry({
	wood = 4,
	stone = 2,
	food = 1,
	metal = 3,
})
assertNil(normalizeError, "full cost entry normalizes without error")
assertEqual(normalized.wood, 4, "normalized wood")
assertEqual(normalized.metal, 3, "normalized metal")

local defaulted, defaultedError = ConstructionSpendState.NormalizeCostEntry({
	wood = 5,
	stone = 1,
})
assertNil(defaultedError, "optional food/metal default to zero")
assertEqual(defaulted.food, 0, "default food")
assertEqual(defaulted.metal, 0, "default metal")

local invalidWood, invalidWoodError = ConstructionSpendState.NormalizeCostEntry({
	wood = -1,
	stone = 1,
})
assertNil(invalidWood, "negative wood rejected")
assertEqual(invalidWoodError, "invalid_wood_or_stone", "negative wood reason")

local siteCost, siteError = ConstructionSpendState.ResolveSiteCost("ConstructionSite_C", {
	ConstructionSite_C = {
		wood = 6,
		stone = 8,
		metal = 3,
	},
})
assertNil(siteError, "site cost resolves")
assertEqual(siteCost.metal, 3, "site metal cost")

local missingSite, missingSiteError = ConstructionSpendState.ResolveSiteCost("MissingSite", {})
assertNil(missingSite, "missing site rejected")
assertEqual(missingSiteError, "missing_cost_entry", "missing site reason")

local affordable, affordError = ConstructionSpendState.ValidateAffordability(
	{ wood = 5, stone = 2, food = 1, metal = 3 },
	{
		Wood = { stored = 10 },
		Stone = { stored = 4 },
		Food = { stored = 2 },
		Metal = { stored = 3 },
	}
)
assertTrue(affordable, "affordable when all stored totals sufficient")
assertNil(affordError, "affordable has no error")

local unaffordableMetal, metalError = ConstructionSpendState.ValidateAffordability(
	{ wood = 0, stone = 0, food = 0, metal = 2 },
	{
		Wood = { stored = 0 },
		Stone = { stored = 0 },
		Food = { stored = 0 },
		Metal = { stored = 1 },
	}
)
assertTrue(not unaffordableMetal, "insufficient metal rejected")
assertEqual(metalError, "insufficient_metal required=2 stored=1", "insufficient metal reason")

local zeroCost, zeroCostError = ConstructionSpendState.ValidateAffordability(
	{ wood = 0, stone = 0, food = 0, metal = 0 },
	{
		Wood = { stored = 99 },
		Stone = { stored = 99 },
		Food = { stored = 99 },
		Metal = { stored = 99 },
	}
)
assertTrue(not zeroCost, "zero total spend rejected")
assertEqual(zeroCostError, "zero_cost", "zero cost reason")

print("construction_spend_state.spec.luau: all checks passed")
