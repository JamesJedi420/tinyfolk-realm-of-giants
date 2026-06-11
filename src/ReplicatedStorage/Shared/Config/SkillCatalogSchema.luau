--!strict

local SkillCatalogSchema: any = {}

export type SkillAvailability = "available" | "locked"
export type SkillUnlockSource = "starter" | "progression"
export type SkillRecord = {
	skillId: string,
	displayName: string,
	unlockSource: SkillUnlockSource,
	availability: SkillAvailability,
	sourceId: string,
}

SkillCatalogSchema.SCHEMA_VERSION = 1
SkillCatalogSchema.CATALOG_VERSION = "tinyfolk_skills_v1"

SkillCatalogSchema.Availability = {
	Available = "available",
	Locked = "locked",
}

SkillCatalogSchema.UnlockSources = {
	Starter = "starter",
	Progression = "progression",
}

local VALID_AVAILABILITY = {
	available = true,
	locked = true,
}

local VALID_UNLOCK_SOURCE = {
	starter = true,
	progression = true,
}

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function cloneSkillRecord(record: SkillRecord): SkillRecord
	return {
		skillId = record.skillId,
		displayName = record.displayName,
		unlockSource = record.unlockSource,
		availability = record.availability,
		sourceId = record.sourceId,
	}
end

local defaultSkillCatalog: { SkillRecord } = {}

SkillCatalogSchema.DEFAULT_SKILL_CATALOG = defaultSkillCatalog

function SkillCatalogSchema.ValidateSkillRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "skill_record_invalid"
	end
	if not isNonEmptyString(record.skillId) then
		return false, "skill_id_invalid"
	end
	if not isNonEmptyString(record.displayName) then
		return false, "skill_display_name_invalid"
	end
	if type(record.unlockSource) ~= "string" or VALID_UNLOCK_SOURCE[record.unlockSource] ~= true then
		return false, "skill_unlock_source_invalid"
	end
	if type(record.availability) ~= "string" or VALID_AVAILABILITY[record.availability] ~= true then
		return false, "skill_availability_invalid"
	end
	if not isNonEmptyString(record.sourceId) then
		return false, "skill_source_id_invalid"
	end

	return true, nil
end

function SkillCatalogSchema.ValidateSkillCatalog(catalog: any): (boolean, string?)
	if type(catalog) ~= "table" then
		return false, "skill_catalog_invalid"
	end
	local seen = {}
	for index, record in ipairs(catalog) do
		local valid, reason = SkillCatalogSchema.ValidateSkillRecord(record)
		if not valid then
			return false, string.format("%s index=%d", tostring(reason), index)
		end
		if seen[record.skillId] == true then
			return false, string.format("skill_id_duplicate index=%d", index)
		end
		seen[record.skillId] = true
	end
	return true, nil
end

function SkillCatalogSchema.GetSkillRecord(skillId: any, catalog: any?): (SkillRecord?, string?)
	if not isNonEmptyString(skillId) then
		return nil, "skill_id_invalid"
	end
	local sourceCatalog = if type(catalog) == "table" then catalog else defaultSkillCatalog
	for _, record in ipairs(sourceCatalog) do
		if record.skillId == skillId then
			return cloneSkillRecord(record), nil
		end
	end
	return nil, "skill_missing"
end

function SkillCatalogSchema.GetAllSkillRecords(catalog: any?): { SkillRecord }
	local sourceCatalog = if type(catalog) == "table" then catalog else defaultSkillCatalog
	local copied = {}
	for _, record in ipairs(sourceCatalog) do
		table.insert(copied, cloneSkillRecord(record))
	end
	return copied
end

return SkillCatalogSchema
