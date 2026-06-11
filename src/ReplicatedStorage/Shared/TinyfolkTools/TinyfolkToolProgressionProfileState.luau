--!strict

local TinyfolkToolCatalogSchema = require("../Config/TinyfolkToolCatalogSchema")

local TinyfolkToolProgressionProfileState: any = {}

local PROFILE_KEY = "tinyfolkToolProgressionState"
local UNLOCKED_TOOL_IDS_KEY = "unlockedToolIds"
local SCHEMA_VERSION_KEY = "schemaVersion"
local STATE_VERSION = 1

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
}

export type UnlockTransition = {
	accepted: boolean,
	reason: string,
	profileData: any,
	toolId: string?,
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

local function hasCooldownMetadata(toolRecord: any): boolean
	local cooldown = toolRecord.cooldown
	if type(cooldown) ~= "table" then
		return false
	end
	if type(cooldown.key) ~= "string" or cooldown.key == "" then
		return false
	end
	if type(cooldown.seconds) ~= "number" then
		return false
	end
	if cooldown.seconds ~= cooldown.seconds or cooldown.seconds == math.huge or cooldown.seconds == -math.huge then
		return false
	end
	return cooldown.seconds >= 0
end

local function isPersistableProgressionTool(toolRecord: any): boolean
	return toolRecord.role == TinyfolkToolCatalogSchema.Roles.Tinyfolk
		and toolRecord.unlockSource == TinyfolkToolCatalogSchema.UnlockSources.Progression
		and toolRecord.availability == TinyfolkToolCatalogSchema.Availability.Available
		and hasCooldownMetadata(toolRecord)
end

local function normalizeUnlockedToolIds(value: any, catalog: any?): { string }
	if type(value) ~= "table" then
		return {}
	end

	local seen: { [string]: boolean } = {}
	local normalized = {}
	for _, toolId in ipairs(value) do
		if type(toolId) ~= "string" or toolId == "" or seen[toolId] == true then
			continue
		end

		local toolRecord = TinyfolkToolCatalogSchema.GetToolRecord(toolId, catalog)
		if toolRecord == nil or not isPersistableProgressionTool(toolRecord) then
			continue
		end

		seen[toolId] = true
		table.insert(normalized, toolId)
	end

	table.sort(normalized)
	return normalized
end

local function buildDefaultPersistedState(): any
	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = STATE_VERSION
	persisted[UNLOCKED_TOOL_IDS_KEY] = {}
	return persisted
end

local function normalizePersistedState(value: any, catalog: any?): any
	if type(value) ~= "table" then
		return buildDefaultPersistedState()
	end

	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = normalizeSchemaVersion(value[SCHEMA_VERSION_KEY])
	persisted[UNLOCKED_TOOL_IDS_KEY] = normalizeUnlockedToolIds(value[UNLOCKED_TOOL_IDS_KEY], catalog)
	return persisted
end

local function ensureProfileState(profileData: any, catalog: any?): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	nextProfile[PROFILE_KEY] = normalizePersistedState(nextProfile[PROFILE_KEY], catalog)
	return nextProfile
end

local function buildUnlockedToolSet(unlockedToolIds: { string }): { [string]: boolean }
	local unlockedSet: { [string]: boolean } = {}
	for _, toolId in ipairs(unlockedToolIds) do
		unlockedSet[toolId] = true
	end
	return unlockedSet
end

function TinyfolkToolProgressionProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local progressionState = profileData[PROFILE_KEY]
	if type(progressionState) ~= "table" then
		return false
	end

	return type(progressionState[SCHEMA_VERSION_KEY]) == "number"
end

function TinyfolkToolProgressionProfileState.GetUnlockedToolIds(profileData: any, catalog: any?): { string }
	local nextProfile = ensureProfileState(profileData, catalog)
	return cloneTable(nextProfile[PROFILE_KEY][UNLOCKED_TOOL_IDS_KEY])
end

function TinyfolkToolProgressionProfileState.GetUnlockedToolSet(profileData: any, catalog: any?): { [string]: boolean }
	return buildUnlockedToolSet(TinyfolkToolProgressionProfileState.GetUnlockedToolIds(profileData, catalog))
end

function TinyfolkToolProgressionProfileState.CopyProfileField(profileData: any, catalog: any?): any
	if type(profileData) ~= "table" then
		return buildDefaultPersistedState()
	end

	return normalizePersistedState(profileData[PROFILE_KEY], catalog)
end

function TinyfolkToolProgressionProfileState.ApplyUnlockedToolIds(
	profileData: any,
	unlockedToolIds: any,
	catalog: any?
): PersistResult
	local nextProfile = ensureProfileState(profileData, catalog)
	if type(unlockedToolIds) ~= "table" then
		return {
			accepted = false,
			reason = "unlocked_tool_ids_invalid",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY][UNLOCKED_TOOL_IDS_KEY] = normalizeUnlockedToolIds(unlockedToolIds, catalog)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

function TinyfolkToolProgressionProfileState.ResolveUnlock(
	profileData: any,
	toolId: any,
	catalog: any?
): UnlockTransition
	if type(toolId) ~= "string" or toolId == "" then
		return {
			accepted = false,
			reason = "invalid_tool_id",
			profileData = ensureProfileState(profileData, catalog),
			toolId = nil,
		}
	end

	local toolRecord, lookupReason = TinyfolkToolCatalogSchema.GetToolRecord(toolId, catalog)
	if toolRecord == nil then
		return {
			accepted = false,
			reason = lookupReason or "tool_missing",
			profileData = ensureProfileState(profileData, catalog),
			toolId = toolId,
		}
	end
	if not isPersistableProgressionTool(toolRecord) then
		return {
			accepted = false,
			reason = "tool_not_progression_unlock",
			profileData = ensureProfileState(profileData, catalog),
			toolId = toolId,
		}
	end

	local nextProfile = ensureProfileState(profileData, catalog)
	local unlockedToolIds: { string } = nextProfile[PROFILE_KEY][UNLOCKED_TOOL_IDS_KEY]
	if buildUnlockedToolSet(unlockedToolIds)[toolId] == true then
		return {
			accepted = false,
			reason = "tool_already_unlocked",
			profileData = nextProfile,
			toolId = toolId,
		}
	end

	table.insert(unlockedToolIds, toolId)
	table.sort(unlockedToolIds)

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		toolId = toolId,
	}
end

return TinyfolkToolProgressionProfileState
