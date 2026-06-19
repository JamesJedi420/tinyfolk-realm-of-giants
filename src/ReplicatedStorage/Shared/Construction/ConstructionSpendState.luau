--!strict

local ConstructionSpendState = {}

export type MaterialCost = {
	wood: number,
	stone: number,
	food: number,
	metal: number,
}

export type CostConfigEntry = {
	wood: number?,
	stone: number?,
	food: number?,
	metal: number?,
}

export type StoredFlowSnapshot = {
	Wood: { stored: number? },
	Stone: { stored: number? },
	Food: { stored: number? },
	Metal: { stored: number? },
}

local function isFiniteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0
end

local function resolveOptionalCost(value: any): (number?, string?)
	if value == nil then
		return 0, nil
	end
	if not isFiniteNonNegative(value) then
		return nil, "invalid_cost_field"
	end
	return value, nil
end

function ConstructionSpendState.NormalizeCostEntry(entry: CostConfigEntry?): (MaterialCost?, string?)
	if type(entry) ~= "table" then
		return nil, "missing_cost_entry"
	end

	if not isFiniteNonNegative(entry.wood) or not isFiniteNonNegative(entry.stone) then
		return nil, "invalid_wood_or_stone"
	end

	local food, foodError = resolveOptionalCost(entry.food)
	if food == nil then
		return nil, foodError
	end

	local metal, metalError = resolveOptionalCost(entry.metal)
	if metal == nil then
		return nil, metalError
	end

	return {
		wood = entry.wood :: number,
		stone = entry.stone :: number,
		food = food,
		metal = metal,
	}, nil
end

function ConstructionSpendState.ResolveSiteCost(
	siteId: string,
	costBySiteId: { [string]: CostConfigEntry }
): (MaterialCost?, string?)
	if type(siteId) ~= "string" or siteId == "" then
		return nil, "invalid_site_id"
	end

	local configured = costBySiteId[siteId]
	return ConstructionSpendState.NormalizeCostEntry(configured)
end

function ConstructionSpendState.ResolveDistrictCost(defaultCost: CostConfigEntry): (MaterialCost?, string?)
	return ConstructionSpendState.NormalizeCostEntry(defaultCost)
end

function ConstructionSpendState.HasPositiveSpend(cost: MaterialCost): boolean
	return cost.wood > 0 or cost.stone > 0 or cost.food > 0 or cost.metal > 0
end

function ConstructionSpendState.ValidateAffordability(
	cost: MaterialCost,
	flowSnapshot: StoredFlowSnapshot
): (boolean, string?)
	if not ConstructionSpendState.HasPositiveSpend(cost) then
		return false, "zero_cost"
	end

	local woodStored = if type(flowSnapshot.Wood) == "table" then flowSnapshot.Wood.stored else nil
	local stoneStored = if type(flowSnapshot.Stone) == "table" then flowSnapshot.Stone.stored else nil
	local foodStored = if type(flowSnapshot.Food) == "table" then flowSnapshot.Food.stored else nil
	local metalStored = if type(flowSnapshot.Metal) == "table" then flowSnapshot.Metal.stored else nil

	if type(woodStored) ~= "number" or type(stoneStored) ~= "number" then
		return false, "invalid_flow_snapshot"
	end

	if woodStored < cost.wood then
		return false, string.format("insufficient_wood required=%.0f stored=%.0f", cost.wood, woodStored)
	end

	if stoneStored < cost.stone then
		return false, string.format("insufficient_stone required=%.0f stored=%.0f", cost.stone, stoneStored)
	end

	local resolvedFoodStored = if type(foodStored) == "number" then foodStored else 0
	if resolvedFoodStored < cost.food then
		return false, string.format("insufficient_food required=%.0f stored=%.0f", cost.food, resolvedFoodStored)
	end

	local resolvedMetalStored = if type(metalStored) == "number" then metalStored else 0
	if resolvedMetalStored < cost.metal then
		return false, string.format("insufficient_metal required=%.0f stored=%.0f", cost.metal, resolvedMetalStored)
	end

	return true, nil
end

return ConstructionSpendState
