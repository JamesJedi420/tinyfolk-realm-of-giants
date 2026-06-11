--!strict

local TinyfolkToolCatalogSchema = require("../Config/TinyfolkToolCatalogSchema")

local TinyfolkToolLoadoutProfileState: any = {}

local PROFILE_KEY = "tinyfolkToolLoadoutState"
local SELECTED_BY_ROLE_KEY = "selectedByRole"
local SCHEMA_VERSION_KEY = "schemaVersion"
local STATE_VERSION = 1
local TINYFOLK_ROLE = TinyfolkToolCatalogSchema.Roles.Tinyfolk

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

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

local function normalizeSchemaVersion(value: any): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return STATE_VERSION
end

local function normalizeSelectedBySlot(value: any): { [string]: string }
	if type(value) ~= "table" then
		return {}
	end

	local normalized = {}
	for _, definition in ipairs(TinyfolkToolCatalogSchema.GetSlotDefinitions()) do
		local selectedToolId = value[definition.slotId]
		if type(selectedToolId) == "string" and selectedToolId ~= "" then
			normalized[definition.slotId] = selectedToolId
		end
	end
	return normalized
end

local function buildDefaultPersistedState(): any
	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = STATE_VERSION
	persisted[SELECTED_BY_ROLE_KEY] = {}
	persisted[SELECTED_BY_ROLE_KEY][TINYFOLK_ROLE] = {}
	return persisted
end

local function normalizePersistedState(value: any): any
	if type(value) ~= "table" then
		return buildDefaultPersistedState()
	end

	local selectedByRole: any = value[SELECTED_BY_ROLE_KEY]
	local tinyfolkSelected: any = if type(selectedByRole) == "table" then selectedByRole[TINYFOLK_ROLE] else nil

	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = normalizeSchemaVersion(value[SCHEMA_VERSION_KEY])
	persisted[SELECTED_BY_ROLE_KEY] = {}
	persisted[SELECTED_BY_ROLE_KEY][TINYFOLK_ROLE] = normalizeSelectedBySlot(tinyfolkSelected)
	return persisted
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	nextProfile[PROFILE_KEY] = normalizePersistedState(nextProfile[PROFILE_KEY])
	return nextProfile
end

function TinyfolkToolLoadoutProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local loadoutState = profileData[PROFILE_KEY]
	if type(loadoutState) ~= "table" then
		return false
	end

	return type(loadoutState[SCHEMA_VERSION_KEY]) == "number"
end

function TinyfolkToolLoadoutProfileState.GetSelectedLoadout(profileData: any, role: any): { [string]: string }
	if role ~= TINYFOLK_ROLE then
		return {}
	end

	local nextProfile = ensureProfileState(profileData)
	local selectedByRole: any = nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY]
	local selectedBySlot: any = if type(selectedByRole) == "table" then selectedByRole[TINYFOLK_ROLE] else nil
	return cloneTable(normalizeSelectedBySlot(selectedBySlot))
end

function TinyfolkToolLoadoutProfileState.CopyProfileField(profileData: any): any
	if type(profileData) ~= "table" then
		return buildDefaultPersistedState()
	end

	return normalizePersistedState(profileData[PROFILE_KEY])
end

function TinyfolkToolLoadoutProfileState.ApplySelectedLoadout(
	profileData: any,
	role: any,
	selectedBySlot: any
): PersistResult
	local nextProfile = ensureProfileState(profileData)
	if role ~= TINYFOLK_ROLE then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			profileData = nextProfile,
		}
	end
	if type(selectedBySlot) ~= "table" then
		return {
			accepted = false,
			reason = "tool_loadout_selection_invalid",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][TINYFOLK_ROLE] = normalizeSelectedBySlot(selectedBySlot)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

return TinyfolkToolLoadoutProfileState
