--!strict

local TinyfolkToolCatalogSchema: any = {}

export type ToolRole = "Tinyfolk"
export type ToolCategory = "escape" | "sabotage" | "stealth" | "rescue"
export type ToolAvailability = "available" | "locked"
export type ToolUnlockSource = "starter" | "progression"
export type ToolCooldownRecord = {
	key: string,
	seconds: number,
}
export type ToolRecord = {
	toolId: string,
	displayName: string,
	description: string?,
	role: ToolRole,
	categories: { string },
	tags: { string }?,
	unlockSource: ToolUnlockSource,
	availability: ToolAvailability,
	cooldown: ToolCooldownRecord?,
	chargesMax: number?,
	sourceId: string,
}

export type SlotDefinition = {
	slotId: string,
	required: boolean,
}

TinyfolkToolCatalogSchema.SCHEMA_VERSION = 1
TinyfolkToolCatalogSchema.CATALOG_VERSION = "tinyfolk_tools_v1"

TinyfolkToolCatalogSchema.Roles = {
	Tinyfolk = "Tinyfolk",
}

TinyfolkToolCatalogSchema.Categories = {
	Escape = "escape",
	Sabotage = "sabotage",
	Stealth = "stealth",
	Rescue = "rescue",
}

TinyfolkToolCatalogSchema.Availability = {
	Available = "available",
	Locked = "locked",
}

TinyfolkToolCatalogSchema.UnlockSources = {
	Starter = "starter",
	Progression = "progression",
}

TinyfolkToolCatalogSchema.SlotDefinitions = {
	{ slotId = "tool_1", required = false },
	{ slotId = "tool_2", required = false },
}

local VALID_CATEGORIES = {
	escape = true,
	sabotage = true,
	stealth = true,
	rescue = true,
}

local VALID_AVAILABILITY = {
	available = true,
	locked = true,
}

local VALID_UNLOCK_SOURCE = {
	starter = true,
	progression = true,
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

local function isNonNegativeNumber(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	return value >= 0
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function cloneStringArray(source: { string }): { string }
	local copied = {}
	for _, value in ipairs(source) do
		table.insert(copied, value)
	end
	return copied
end

local function cloneToolRecord(record: ToolRecord): ToolRecord
	local cooldown: ToolCooldownRecord? = nil
	local sourceCooldown: any = record.cooldown
	if type(sourceCooldown) == "table" then
		cooldown = {
			key = (sourceCooldown :: any)["key"],
			seconds = (sourceCooldown :: any)["seconds"],
		}
	end

	return {
		toolId = record.toolId,
		displayName = record.displayName,
		description = record.description,
		role = record.role,
		categories = cloneStringArray(record.categories),
		tags = if type(record.tags) == "table" then cloneStringArray(record.tags) else nil,
		unlockSource = record.unlockSource,
		availability = record.availability,
		cooldown = cooldown,
		chargesMax = record.chargesMax,
		sourceId = record.sourceId,
	}
end

local function validateCategories(categories: any): (boolean, string?)
	if type(categories) ~= "table" or #categories <= 0 then
		return false, "tool_categories_invalid"
	end

	local seen = {}
	for _, category in ipairs(categories) do
		if type(category) ~= "string" or VALID_CATEGORIES[category] ~= true then
			return false, "tool_category_invalid"
		end
		if seen[category] == true then
			return false, "tool_categories_duplicate"
		end
		seen[category] = true
	end
	return true, nil
end

local function validateTags(tags: any): (boolean, string?)
	if tags == nil then
		return true, nil
	end
	if type(tags) ~= "table" then
		return false, "tool_tags_invalid"
	end

	local seen = {}
	for _, tag in ipairs(tags) do
		if not isNonEmptyString(tag) then
			return false, "tool_tag_invalid"
		end
		if seen[tag] == true then
			return false, "tool_tags_duplicate"
		end
		seen[tag] = true
	end
	return true, nil
end

local function validateCooldown(cooldown: any): (boolean, string?)
	if type(cooldown) ~= "table" then
		return false, "tool_cooldown_missing"
	end
	if not isNonEmptyString(cooldown.key) then
		return false, "tool_cooldown_key_invalid"
	end
	if not isNonNegativeNumber(cooldown.seconds) then
		return false, "tool_cooldown_seconds_invalid"
	end
	return true, nil
end

local defaultToolCatalog: { ToolRecord } = {
	{
		toolId = "grappling_hook",
		displayName = "Grappling Hook",
		description = "A fast movement anchor for escape routes.",
		role = "Tinyfolk",
		categories = { "escape" },
		tags = { "starter_tool" },
		unlockSource = "starter",
		availability = "available",
		cooldown = {
			key = "tinyfolk_tool_grappling_hook",
			seconds = 30,
		},
		chargesMax = 1,
		sourceId = "tin68_tinyfolk_tool_grappling_hook",
	},
	{
		toolId = "lockpick",
		displayName = "Lockpick",
		description = "A sabotage utility for bypassing basic locks.",
		role = "Tinyfolk",
		categories = { "sabotage", "rescue" },
		tags = { "starter_tool" },
		unlockSource = "starter",
		availability = "available",
		cooldown = {
			key = "tinyfolk_tool_lockpick",
			seconds = 18,
		},
		chargesMax = 1,
		sourceId = "tin68_tinyfolk_tool_lockpick",
	},
	{
		toolId = "smoke_bomb",
		displayName = "Smoke Bomb",
		description = "A stealth cover burst to break line-of-sight.",
		role = "Tinyfolk",
		categories = { "stealth", "rescue" },
		tags = { "starter_tool" },
		unlockSource = "starter",
		availability = "available",
		cooldown = {
			key = "tinyfolk_tool_smoke_bomb",
			seconds = 45,
		},
		chargesMax = 1,
		sourceId = "tin68_tinyfolk_tool_smoke_bomb",
	},
	{
		toolId = "decoy",
		displayName = "Decoy",
		description = "A distraction lure for escape and sabotage windows.",
		role = "Tinyfolk",
		categories = { "escape", "sabotage", "stealth" },
		tags = { "starter_tool" },
		unlockSource = "starter",
		availability = "available",
		cooldown = {
			key = "tinyfolk_tool_decoy",
			seconds = 24,
		},
		chargesMax = 1,
		sourceId = "tin68_tinyfolk_tool_decoy",
	},
}

TinyfolkToolCatalogSchema.DEFAULT_TOOL_CATALOG = defaultToolCatalog

function TinyfolkToolCatalogSchema.GetSlotDefinitions(): { SlotDefinition }
	local copied = {}
	for _, definition in ipairs(TinyfolkToolCatalogSchema.SlotDefinitions) do
		table.insert(copied, {
			slotId = definition.slotId,
			required = definition.required,
		})
	end
	return copied
end

function TinyfolkToolCatalogSchema.GetMaxSelectableSlots(): number
	return #TinyfolkToolCatalogSchema.SlotDefinitions
end

function TinyfolkToolCatalogSchema.ValidateToolRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "tool_record_invalid"
	end
	if not isNonEmptyString(record.toolId) then
		return false, "tool_id_invalid"
	end
	if not isNonEmptyString(record.displayName) then
		return false, "tool_display_name_invalid"
	end
	if record.description ~= nil and not isNonEmptyString(record.description) then
		return false, "tool_description_invalid"
	end
	if record.role ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
		return false, "tool_role_invalid"
	end

	local categoriesOk, categoriesReason = validateCategories(record.categories)
	if not categoriesOk then
		return false, categoriesReason
	end

	local tagsOk, tagsReason = validateTags(record.tags)
	if not tagsOk then
		return false, tagsReason
	end

	if type(record.unlockSource) ~= "string" or VALID_UNLOCK_SOURCE[record.unlockSource] ~= true then
		return false, "tool_unlock_source_invalid"
	end
	if type(record.availability) ~= "string" or VALID_AVAILABILITY[record.availability] ~= true then
		return false, "tool_availability_invalid"
	end

	local cooldownOk, cooldownReason = validateCooldown(record.cooldown)
	if not cooldownOk then
		return false, cooldownReason
	end

	if record.chargesMax ~= nil and not isPositiveInteger(record.chargesMax) then
		return false, "tool_charges_max_invalid"
	end
	if not isNonEmptyString(record.sourceId) then
		return false, "tool_source_id_invalid"
	end

	return true, nil
end

function TinyfolkToolCatalogSchema.ValidateToolCatalog(catalog: any): (boolean, string?)
	if type(catalog) ~= "table" then
		return false, "tool_catalog_invalid"
	end
	local seen = {}
	for index, record in ipairs(catalog) do
		local valid, reason = TinyfolkToolCatalogSchema.ValidateToolRecord(record)
		if not valid then
			return false, string.format("%s index=%d", tostring(reason), index)
		end
		if seen[record.toolId] == true then
			return false, string.format("tool_id_duplicate index=%d", index)
		end
		seen[record.toolId] = true
	end
	return true, nil
end

function TinyfolkToolCatalogSchema.GetToolRecord(toolId: any, catalog: any?): (ToolRecord?, string?)
	if not isNonEmptyString(toolId) then
		return nil, "tool_id_invalid"
	end
	local sourceCatalog = if type(catalog) == "table" then catalog else defaultToolCatalog
	for _, record in ipairs(sourceCatalog) do
		if record.toolId == toolId then
			return cloneToolRecord(record), nil
		end
	end
	return nil, "tool_missing"
end

function TinyfolkToolCatalogSchema.GetAllToolRecords(catalog: any?): { ToolRecord }
	local sourceCatalog = if type(catalog) == "table" then catalog else defaultToolCatalog
	local copied = {}
	for _, record in ipairs(sourceCatalog) do
		table.insert(copied, cloneToolRecord(record))
	end
	return copied
end

return TinyfolkToolCatalogSchema
