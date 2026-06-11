--!strict

local SkillCatalogSchema = require("../Config/SkillCatalogSchema")

local SkillsProfileState: any = {}

local PROFILE_KEY = "skillsProfileState"
local UNLOCKED_SKILL_IDS_KEY = "unlockedSkillIds"
local SKILL_PROGRESS_BY_ID_KEY = "skillProgressById"
local SCHEMA_VERSION_KEY = "schemaVersion"
local STATE_VERSION = 2

export type SkillProgressRecord = {
	level: number,
	xp: number,
	cooldownEndsAt: number?,
}

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

export type ProgressTransition = {
	accepted: boolean,
	reason: string,
	profileData: any,
	skillId: string?,
	progress: SkillProgressRecord?,
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

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function normalizeSchemaVersion(value: any): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return STATE_VERSION
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

local function buildDefaultSkillProgressRecord(_skillId: string, _catalog: any?): SkillProgressRecord
	return {
		level = 1,
		xp = 0,
		cooldownEndsAt = nil,
	}
end

local function normalizeSkillProgressRecord(skillId: string, value: any, catalog: any?): SkillProgressRecord
	local maxLevel = SkillCatalogSchema.GetSkillMaxLevel(skillId, catalog)
	local maxXp = SkillCatalogSchema.ResolveMaxXpForSkill(skillId, catalog)
	local xp = if isFiniteNumber(value.xp) and value.xp >= 0 then math.floor(value.xp) else 0
	xp = math.min(xp, maxXp)
	local level = SkillCatalogSchema.ResolveLevelFromXp(skillId, xp, catalog)
	level = math.clamp(level, 1, maxLevel)
	local cooldownEndsAt = if isFiniteNumber(value.cooldownEndsAt) and value.cooldownEndsAt >= 0
		then value.cooldownEndsAt
		else nil

	return {
		level = level,
		xp = xp,
		cooldownEndsAt = cooldownEndsAt,
	}
end

local function normalizeSkillProgressById(
	value: any,
	unlockedSkillIds: { string },
	catalog: any?
): { [string]: SkillProgressRecord }
	local unlockedSet = {}
	for _, skillId in ipairs(unlockedSkillIds) do
		unlockedSet[skillId] = true
	end

	local normalized: { [string]: SkillProgressRecord } = {}
	if type(value) ~= "table" then
		for _, skillId in ipairs(unlockedSkillIds) do
			normalized[skillId] = buildDefaultSkillProgressRecord(skillId, catalog)
		end
		return normalized
	end

	for skillId, progressValue in pairs(value) do
		if type(skillId) ~= "string" or skillId == "" or unlockedSet[skillId] ~= true then
			continue
		end

		local skillRecord = SkillCatalogSchema.GetSkillRecord(skillId, catalog)
		if skillRecord == nil or not isPersistableProgressionSkill(skillRecord) then
			continue
		end

		if type(progressValue) ~= "table" then
			continue
		end

		normalized[skillId] = normalizeSkillProgressRecord(skillId, progressValue, catalog)
	end

	for _, skillId in ipairs(unlockedSkillIds) do
		if normalized[skillId] == nil then
			normalized[skillId] = buildDefaultSkillProgressRecord(skillId, catalog)
		end
	end

	return normalized
end

local function buildDefaultPersistedState(): any
	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = STATE_VERSION
	persisted[UNLOCKED_SKILL_IDS_KEY] = {}
	persisted[SKILL_PROGRESS_BY_ID_KEY] = {}
	return persisted
end

local function normalizePersistedState(value: any, catalog: any?): any
	if type(value) ~= "table" then
		return buildDefaultPersistedState()
	end

	local unlockedSkillIds = normalizeUnlockedSkillIds(value[UNLOCKED_SKILL_IDS_KEY], catalog)
	local persisted: any = {}
	persisted[SCHEMA_VERSION_KEY] = normalizeSchemaVersion(value[SCHEMA_VERSION_KEY])
	persisted[UNLOCKED_SKILL_IDS_KEY] = unlockedSkillIds
	persisted[SKILL_PROGRESS_BY_ID_KEY] =
		normalizeSkillProgressById(value[SKILL_PROGRESS_BY_ID_KEY], unlockedSkillIds, catalog)
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

local function getSkillProgressFromState(skillsState: any, skillId: string): SkillProgressRecord?
	local progressById = skillsState[SKILL_PROGRESS_BY_ID_KEY]
	if type(progressById) ~= "table" then
		return nil
	end
	local progress = progressById[skillId]
	if type(progress) ~= "table" then
		return nil
	end
	return cloneTable(progress)
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

function SkillsProfileState.GetSkillProgressById(profileData: any, catalog: any?): { [string]: SkillProgressRecord }
	local nextProfile = ensureProfileState(profileData, catalog)
	return cloneTable(nextProfile[PROFILE_KEY][SKILL_PROGRESS_BY_ID_KEY])
end

function SkillsProfileState.GetSkillProgress(profileData: any, skillId: any, catalog: any?): SkillProgressRecord?
	local nextProfile = ensureProfileState(profileData, catalog)
	return getSkillProgressFromState(nextProfile[PROFILE_KEY], skillId)
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

	local skillsState = nextProfile[PROFILE_KEY]
	skillsState[UNLOCKED_SKILL_IDS_KEY] = normalizeUnlockedSkillIds(unlockedSkillIds, catalog)
	skillsState[SKILL_PROGRESS_BY_ID_KEY] =
		normalizeSkillProgressById(skillsState[SKILL_PROGRESS_BY_ID_KEY], skillsState[UNLOCKED_SKILL_IDS_KEY], catalog)
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
	}
end

function SkillsProfileState.ApplySkillProgressById(
	profileData: any,
	skillProgressById: any,
	catalog: any?
): PersistResult
	local nextProfile = ensureProfileState(profileData, catalog)
	if type(skillProgressById) ~= "table" then
		return {
			accepted = false,
			reason = "skill_progress_by_id_invalid",
			profileData = nextProfile,
		}
	end

	local skillsState = nextProfile[PROFILE_KEY]
	skillsState[SKILL_PROGRESS_BY_ID_KEY] =
		normalizeSkillProgressById(skillProgressById, skillsState[UNLOCKED_SKILL_IDS_KEY], catalog)
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
	local skillsState = nextProfile[PROFILE_KEY]
	local unlockedSkillIds: { string } = skillsState[UNLOCKED_SKILL_IDS_KEY]
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
	skillsState[SKILL_PROGRESS_BY_ID_KEY] =
		normalizeSkillProgressById(skillsState[SKILL_PROGRESS_BY_ID_KEY], unlockedSkillIds, catalog)

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		skillId = skillId,
	}
end

function SkillsProfileState.ResolveAwardXp(
	profileData: any,
	skillId: any,
	xpAmount: any,
	catalog: any?
): ProgressTransition
	if type(skillId) ~= "string" or skillId == "" then
		return {
			accepted = false,
			reason = "invalid_skill_id",
			profileData = ensureProfileState(profileData, catalog),
			skillId = nil,
			progress = nil,
		}
	end

	local skillRecord, lookupReason = SkillCatalogSchema.GetSkillRecord(skillId, catalog)
	if skillRecord == nil then
		return {
			accepted = false,
			reason = lookupReason or "skill_missing",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
			progress = nil,
		}
	end
	if not isPersistableProgressionSkill(skillRecord) then
		return {
			accepted = false,
			reason = "skill_not_progression_unlock",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
			progress = nil,
		}
	end

	if not isFiniteNumber(xpAmount) or xpAmount <= 0 then
		return {
			accepted = false,
			reason = "xp_amount_invalid",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
			progress = nil,
		}
	end

	local nextProfile = ensureProfileState(profileData, catalog)
	local skillsState = nextProfile[PROFILE_KEY]
	if buildUnlockedSkillSet(skillsState[UNLOCKED_SKILL_IDS_KEY])[skillId] ~= true then
		return {
			accepted = false,
			reason = "skill_not_unlocked",
			profileData = nextProfile,
			skillId = skillId,
			progress = nil,
		}
	end

	local progressById = skillsState[SKILL_PROGRESS_BY_ID_KEY]
	local currentProgress = progressById[skillId]
	local nextXp =
		math.min(SkillCatalogSchema.ResolveMaxXpForSkill(skillId, catalog), currentProgress.xp + math.floor(xpAmount))
	local nextProgress = normalizeSkillProgressRecord(skillId, {
		xp = nextXp,
		cooldownEndsAt = currentProgress.cooldownEndsAt,
	}, catalog)
	progressById[skillId] = nextProgress

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		skillId = skillId,
		progress = cloneTable(nextProgress),
	}
end

function SkillsProfileState.ResolveSetCooldown(
	profileData: any,
	skillId: any,
	cooldownEndsAt: any,
	catalog: any?
): ProgressTransition
	if type(skillId) ~= "string" or skillId == "" then
		return {
			accepted = false,
			reason = "invalid_skill_id",
			profileData = ensureProfileState(profileData, catalog),
			skillId = nil,
			progress = nil,
		}
	end

	local skillRecord, lookupReason = SkillCatalogSchema.GetSkillRecord(skillId, catalog)
	if skillRecord == nil then
		return {
			accepted = false,
			reason = lookupReason or "skill_missing",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
			progress = nil,
		}
	end
	if not isPersistableProgressionSkill(skillRecord) then
		return {
			accepted = false,
			reason = "skill_not_progression_unlock",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
			progress = nil,
		}
	end

	if cooldownEndsAt ~= nil and (not isFiniteNumber(cooldownEndsAt) or cooldownEndsAt < 0) then
		return {
			accepted = false,
			reason = "cooldown_ends_at_invalid",
			profileData = ensureProfileState(profileData, catalog),
			skillId = skillId,
			progress = nil,
		}
	end

	local nextProfile = ensureProfileState(profileData, catalog)
	local skillsState = nextProfile[PROFILE_KEY]
	if buildUnlockedSkillSet(skillsState[UNLOCKED_SKILL_IDS_KEY])[skillId] ~= true then
		return {
			accepted = false,
			reason = "skill_not_unlocked",
			profileData = nextProfile,
			skillId = skillId,
			progress = nil,
		}
	end

	local progressById = skillsState[SKILL_PROGRESS_BY_ID_KEY]
	local currentProgress = progressById[skillId]
	local nextProgress = normalizeSkillProgressRecord(skillId, {
		xp = currentProgress.xp,
		cooldownEndsAt = cooldownEndsAt,
	}, catalog)
	progressById[skillId] = nextProgress

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		skillId = skillId,
		progress = cloneTable(nextProgress),
	}
end

return SkillsProfileState
