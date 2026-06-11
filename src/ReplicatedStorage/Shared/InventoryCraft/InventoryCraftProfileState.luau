--!strict

local InventoryCraftConfig = require("../Config/InventoryCraftConfig")

local InventoryCraftProfileState: any = {}

local PROFILE_KEY = "inventoryCraftState"
local ITEM_COUNTS_KEY = "itemCounts"
local SCHEMA_VERSION_KEY = "schemaVersion"
local STATE_VERSION = 1

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return value > 0 and value == math.floor(value)
end

local cloneTable: (value: any) -> any
cloneTable = function(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local cloned = {}
	for key, child in pairs(value) do
		cloned[key] = cloneTable(child)
	end
	return cloned
end

local function normalizeItemCounts(value: any, catalogOverride: any?): { [string]: number }
	local normalized: { [string]: number } = {}
	if type(value) ~= "table" then
		return normalized
	end

	for itemId, count in pairs(value) do
		if type(itemId) ~= "string" or itemId == "" or not isPositiveInteger(count) then
			continue
		end

		local itemRecord = InventoryCraftConfig.GetItemRecord(itemId, catalogOverride)
		if itemRecord == nil then
			continue
		end

		if count > itemRecord.maxStack then
			normalized[itemId] = itemRecord.maxStack
		else
			normalized[itemId] = count
		end
	end

	return normalized
end

local function normalizeSchemaVersion(value: any): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return STATE_VERSION
end

local function normalizePersistedState(value: any, catalogOverride: any?): any?
	if type(value) ~= "table" then
		return nil
	end
	if type(value[SCHEMA_VERSION_KEY]) ~= "number" then
		return nil
	end

	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = normalizeSchemaVersion(value[SCHEMA_VERSION_KEY])
	persisted[ITEM_COUNTS_KEY] = normalizeItemCounts(value[ITEM_COUNTS_KEY], catalogOverride)
	return persisted
end

local function ensureProfileState(profileData: any, catalogOverride: any?): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	local normalized = normalizePersistedState(nextProfile[PROFILE_KEY], catalogOverride)
	if normalized == nil then
		local persisted: any = {}
		persisted[SCHEMA_VERSION_KEY] = STATE_VERSION
		persisted[ITEM_COUNTS_KEY] = {}
		nextProfile[PROFILE_KEY] = persisted
	else
		nextProfile[PROFILE_KEY] = normalized
	end

	return nextProfile
end

function InventoryCraftProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local inventoryState = profileData[PROFILE_KEY]
	if type(inventoryState) ~= "table" then
		return false
	end

	return type(inventoryState[SCHEMA_VERSION_KEY]) == "number"
end

function InventoryCraftProfileState.GetItemCounts(profileData: any, catalogOverride: any?): { [string]: number }
	if not InventoryCraftProfileState.HasPersistedState(profileData) then
		return {}
	end

	local inventoryState = profileData[PROFILE_KEY]
	local itemCounts = if type(inventoryState) == "table" then inventoryState[ITEM_COUNTS_KEY] else nil
	return normalizeItemCounts(itemCounts, catalogOverride)
end

function InventoryCraftProfileState.CopyProfileField(profileData: any, catalogOverride: any?): any?
	if type(profileData) ~= "table" then
		return nil
	end

	return normalizePersistedState(profileData[PROFILE_KEY], catalogOverride)
end

function InventoryCraftProfileState.ApplyItemCounts(
	profileData: any,
	itemCounts: any,
	catalogOverride: any?
): PersistResult
	local nextProfile = ensureProfileState(profileData, catalogOverride)
	if type(itemCounts) ~= "table" then
		return {
			accepted = false,
			reason = "item_counts_invalid",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY][ITEM_COUNTS_KEY] = normalizeItemCounts(itemCounts, catalogOverride)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

return InventoryCraftProfileState
