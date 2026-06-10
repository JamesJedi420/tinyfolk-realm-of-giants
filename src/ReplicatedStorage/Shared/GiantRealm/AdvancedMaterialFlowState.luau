--!strict

local AdvancedMaterialFlowConfig = require("../Config/AdvancedMaterialFlowConfig")

export type MaterialName = "Wood" | "Stone" | "Food" | "Metal"

local AdvancedMaterialFlowState = {}

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value > 0 and value == math.floor(value)
end

function AdvancedMaterialFlowState.ResolveInventoryGrants(
	material: MaterialName,
	deliveredAmount: number,
	configOverride: any?
): ({ [string]: number }, string?)
	if type(deliveredAmount) ~= "number" or deliveredAmount <= 0 then
		return {}, "non_positive_delivered_amount"
	end

	local config = if type(configOverride) == "table" then configOverride else AdvancedMaterialFlowConfig
	local grantTable = config.InventoryGrantsByDeliveredMaterial
	if type(grantTable) ~= "table" then
		return {}, "grant_table_missing"
	end

	local itemGrants = grantTable[material]
	if type(itemGrants) ~= "table" then
		return {}, nil
	end

	local unitsPerDelivered = 1
	local configuredUnits = config.GrantUnitsPerDeliveredMaterial
	if type(configuredUnits) == "table" and type(configuredUnits[material]) == "number" then
		unitsPerDelivered = configuredUnits[material]
	end
	if unitsPerDelivered <= 0 then
		return {}, "invalid_grant_units"
	end

	local grantMultiplier = math.floor(deliveredAmount / unitsPerDelivered)
	if grantMultiplier <= 0 then
		return {}, nil
	end

	local resolved: { [string]: number } = {}
	for itemId, count in pairs(itemGrants) do
		if type(itemId) == "string" and itemId ~= "" and isPositiveInteger(count) then
			resolved[itemId] = count * grantMultiplier
		end
	end

	if next(resolved) == nil then
		return {}, "grant_items_invalid"
	end

	return resolved, nil
end

return AdvancedMaterialFlowState
