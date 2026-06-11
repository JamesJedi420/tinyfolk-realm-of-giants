--!strict

local SkillCatalogSchema = require("../Config/SkillCatalogSchema")

local SkillsProfileState: any = {}

local PROFILE_KEY = "skillsProfileState"
local UNLOCKED_SKILL_IDS_KEY = "unlockedSkillIds"
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
	skillId: string?,
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

local function isPersistableProgressionSkill(skillRecord: any): boolean
	return skillRecord.unlockSource == SkillCatalogSchema.UnlockSources.Progression
		and skillRecord.availability == SkillCatalogSchema.Availability.Available
end

local function normalizeUnlockedSkillIds(value: any, catalog: any?): { string }
	if type(value) ~= "table" then
		return {}
	end

	local seen: { [string]: boolean } = {}
	local normalized = {}
	for _, skillId in ipairs(value) do
		if type(skillId) ~= "string" or skillId == "" or seen[skillId] == true then
			continue
		end

		local skillRecord = SkillCatalogSchema.GetSkillRecord(skillId, catalog)
		if skillRecord == nil or not isPersistableProgressionSkill(skillRecord) then
			continue
		end

		seen[skillId] = true
		table.insert(normalized, skillId)
	end

	table.sort(normalized)
	return normalized
end

local function buildDefaultPersistedState(): any
	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = STATE_VERSION
	persisted[UNLOCKED_SKILL_IDS_KEY] = {}
	return persisted
end

local function normalizePersistedState(value: any, catalog: any?): any
	if type(value) ~= "table" then
		return buildDefaultPersistedState()
	end

	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = normalizeSchemaVersion(value[SCHEMA_VERSION_KEY])
	persisted[UNLOCKED_SKILL_IDS_KEY] = normalizeUnlockedSkillIds(value[UNLOCKED_SKILL_IDS_KEY], catalog)
	return persisted
end

local function ensureProfileState(profileData: any, catalog: any?): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	nextProfile[PROFILE_KEY] = normalizePersistedState(nextProfile[PROFILE_KEY], catalog)
	return nextProfile
end

local function buildUnlockedSkillSet(unlockedSkillIds: { string }): { [string]: boolean }
	local unlockedSet: { [string]: boolean } = {}
	for _, skillId in ipairs(unlockedSkillIds) do
		unlockedSet[skillId] = true
	end
	return unlockedSet
end

function SkillsProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	local skillsState = profileData[PROFILE_KEY]
	if type(skillsState) ~= "table" then
		return false
	end

	return type(skillsState[SCHEMA_VERSION_KEY]) == "number"
end

function SkillsProfileState.GetUnlockedSkillIds(profileData: any, catalog: any?): { string }
	local nextProfile = ensureProfileState(profileData, catalog)
	return cloneTable(nextProfile[PROFILE_KEY][UNLOCKED_SKILL_IDS_KEY])
end

function SkillsProfileState.CopyProfileField(profileData: any, catalog: any?): any
	if type(profileData) ~= "table" then
		return buildDefaultPersistedState()
	end

	return normalizePersistedState(profileData[PROFILE_KEY], catalog)
end

function SkillsProfileState.ApplyUnlockedSkillIds(profileData: any, unlockedSkillIds: any, catalog: any?): PersistResult
	local nextProfile = ensureProfileState(profileData, catalog)
	if type(unlockedSkillIds) ~= "table" then
		return {
			accepted = false,
			reason = "unlocked_skill_ids_invalid",
			profileData = nextProfile,
		}
	end

	nextProfile[PROFILE_KEY][UNLOCKED_SKILL_IDS_KEY] = normalizeUnlockedSkillIds(unlockedSkillIds, catalog)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

function SkillsProfileState.ResolveUnlock(profileData: any, skillId: any, catalog: any?): UnlockTransition
	if type(skillId) ~= "string" or skillId == "" then
		return {
			accepted = false,
			reason = "invalid_skill_id",
			profileData = ensureProfileState(profileData, catalog),
			skillId = nil,
		}
	end

	local skillRecord, lookupReason = SkillCatalogSchema.GetSkillRecord(skillId, catalog)
	if skillRecord == nil then
		return {
			accepted = false,
			reason = lookupReason or "skill_missing",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
		}
	end
	if not isPersistableProgressionSkill(skillRecord) then
		return {
			accepted = false,
			reason = "skill_not_progression_unlock",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
		}
	end

	local nextProfile = ensureProfileState(profileData, catalog)
	local unlockedSkillIds: { string } = nextProfile[PROFILE_KEY][UNLOCKED_SKILL_IDS_KEY]
	if buildUnlockedSkillSet(unlockedSkillIds)[skillId] == true then
		return {
			accepted = false,
			reason = "skill_already_unlocked",
			profileData = nextProfile,
			skillId = skillId,
		}
	end

	table.insert(unlockedSkillIds, skillId)
	table.sort(unlockedSkillIds)

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		skillId = skillId,
	}
end

return SkillsProfileState
