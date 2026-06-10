--!strict

local InventoryCraftConfig = require("../Config/InventoryCraftConfig")

local InventoryCraftState: any = {}

export type State = {
	itemCounts: { [string]: number },
	craftedTotal: number,
	lastCraftRecipeId: string?,
	lastCraftAt: number?,
	lastReason: string?,
}

export type InventoryEntry = {
	itemId: string,
	displayName: string,
	kind: string,
	count: number,
	maxStack: number,
}

export type Snapshot = {
	itemCounts: { [string]: number },
	items: { InventoryEntry },
	craftedTotal: number,
	lastCraftRecipeId: string?,
	lastCraftAt: number?,
	lastReason: string?,
}

export type CraftInput = {
	recipeId: string?,
	requesterRole: string?,
	now: number?,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	state: State,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value == math.floor(value)
end

local function cloneCountMap(value: any): { [string]: number }
	local output: { [string]: number } = {}
	if type(value) ~= "table" then
		return output
	end

	for itemId, count in pairs(value) do
		if type(itemId) == "string" and isPositiveInteger(count) then
			output[itemId] = count
		end
	end

	return output
end

local function cloneState(state: State): State
	return {
		itemCounts = cloneCountMap(state.itemCounts),
		craftedTotal = state.craftedTotal,
		lastCraftRecipeId = state.lastCraftRecipeId,
		lastCraftAt = state.lastCraftAt,
		lastReason = state.lastReason,
	}
end

local function getItemCount(state: State, itemId: string): number
	return state.itemCounts[itemId] or 0
end

local function sortedItemIds(itemCounts: { [string]: number }): { string }
	local itemIds: { string } = {}
	for itemId, count in pairs(itemCounts) do
		if isPositiveInteger(count) then
			table.insert(itemIds, itemId)
		end
	end
	table.sort(itemIds)
	return itemIds
end

function InventoryCraftState.NewState(bootstrapItems: any?): State
	local state: State = {
		itemCounts = {},
		craftedTotal = 0,
		lastCraftRecipeId = nil,
		lastCraftAt = nil,
		lastReason = "initialized",
	}

	if type(bootstrapItems) == "table" then
		local transition = InventoryCraftState.AddItems(state, bootstrapItems, nil)
		state = transition.state
		state.lastReason = if transition.accepted then "bootstrapped" else transition.reason
	end

	return state
end

function InventoryCraftState.GetSnapshot(state: State, catalogOverride: any?): Snapshot
	local itemCatalog = InventoryCraftConfig.GetAllItemRecords(catalogOverride)
	local itemIndex: { [string]: any } = {}
	for _, record in ipairs(itemCatalog) do
		itemIndex[record.itemId] = record
	end

	local items: { InventoryEntry } = {}
	for _, itemId in ipairs(sortedItemIds(state.itemCounts)) do
		local count = state.itemCounts[itemId]
		local record = itemIndex[itemId]
		table.insert(items, {
			itemId = itemId,
			displayName = if record ~= nil then record.displayName else itemId,
			kind = if record ~= nil then record.kind else "material",
			count = count,
			maxStack = if record ~= nil then record.maxStack else 99,
		})
	end

	return {
		itemCounts = cloneCountMap(state.itemCounts),
		items = items,
		craftedTotal = state.craftedTotal,
		lastCraftRecipeId = state.lastCraftRecipeId,
		lastCraftAt = state.lastCraftAt,
		lastReason = state.lastReason,
	}
end

function InventoryCraftState.AddItems(state: State, additions: any, catalogOverride: any?): TransitionResult
	local nextState = cloneState(state)
	if type(additions) ~= "table" then
		return {
			accepted = false,
			reason = "additions_invalid",
			state = nextState,
		}
	end

	for itemId, amount in pairs(additions) do
		if type(itemId) ~= "string" or itemId == "" or not isPositiveInteger(amount) then
			return {
				accepted = false,
				reason = "addition_amount_invalid",
				state = nextState,
			}
		end

		local itemRecord, lookupReason = InventoryCraftConfig.GetItemRecord(itemId, catalogOverride)
		if itemRecord == nil then
			return {
				accepted = false,
				reason = lookupReason or "item_missing",
				state = nextState,
			}
		end

		local nextCount = getItemCount(nextState, itemId) + amount
		if nextCount > itemRecord.maxStack then
			return {
				accepted = false,
				reason = "item_stack_capacity_exceeded",
				state = nextState,
			}
		end

		nextState.itemCounts[itemId] = nextCount
	end

	nextState.lastReason = "items_added"
	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
	}
end

function InventoryCraftState.ResolveCraft(
	state: State,
	input: CraftInput,
	itemCatalogOverride: any?,
	recipeCatalogOverride: any?
): TransitionResult
	local nextState = cloneState(state)
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "craft_request_invalid",
			state = nextState,
		}
	end

	if input.requesterRole ~= InventoryCraftConfig.Roles.Tinyfolk then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			state = nextState,
		}
	end

	if type(input.recipeId) ~= "string" or input.recipeId == "" then
		return {
			accepted = false,
			reason = "recipe_id_invalid",
			state = nextState,
		}
	end

	local recipeRecord, lookupReason = InventoryCraftConfig.GetRecipeRecord(input.recipeId, recipeCatalogOverride)
	if recipeRecord == nil then
		return {
			accepted = false,
			reason = lookupReason or "recipe_missing",
			state = nextState,
		}
	end

	if recipeRecord.requiredRole ~= input.requesterRole then
		return {
			accepted = false,
			reason = "recipe_role_mismatch",
			state = nextState,
		}
	end

	for itemId, requiredCount in pairs(recipeRecord.inputs) do
		local ownedCount = getItemCount(nextState, itemId)
		if ownedCount < requiredCount then
			return {
				accepted = false,
				reason = "insufficient_inputs",
				state = nextState,
			}
		end
	end

	local projectedOutputs = cloneCountMap(nextState.itemCounts)
	for itemId, outputCount in pairs(recipeRecord.outputs) do
		local itemRecord = InventoryCraftConfig.GetItemRecord(itemId, itemCatalogOverride)
		if itemRecord == nil then
			return {
				accepted = false,
				reason = "output_item_missing",
				state = nextState,
			}
		end

		local nextCount = getItemCount(nextState, itemId) + outputCount
		if nextCount > itemRecord.maxStack then
			return {
				accepted = false,
				reason = "output_stack_capacity_exceeded",
				state = nextState,
			}
		end
		projectedOutputs[itemId] = nextCount
	end

	for itemId, requiredCount in pairs(recipeRecord.inputs) do
		local remaining = getItemCount(nextState, itemId) - requiredCount
		if remaining <= 0 then
			nextState.itemCounts[itemId] = nil
		else
			nextState.itemCounts[itemId] = remaining
		end
	end

	for itemId, outputCount in pairs(recipeRecord.outputs) do
		nextState.itemCounts[itemId] = getItemCount(nextState, itemId) + outputCount
	end

	nextState.craftedTotal += 1
	nextState.lastCraftRecipeId = recipeRecord.recipeId
	nextState.lastCraftAt = if isFiniteNumber(input.now) then input.now else nil
	nextState.lastReason = "crafted"

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
	}
end

return InventoryCraftState
