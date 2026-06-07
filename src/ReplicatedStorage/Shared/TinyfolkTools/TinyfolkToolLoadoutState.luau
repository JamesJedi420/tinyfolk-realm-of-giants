--!strict

local TinyfolkToolCatalogSchema = require("../Config/TinyfolkToolCatalogSchema")

local TinyfolkToolLoadoutState: any = {}

local PROFILE_KEY = "tinyfolkToolLoadoutState"
local SELECTED_BY_ROLE_KEY = "selectedByRole"
local STATE_VERSION = 1

export type SelectionInput = {
	requesterRole: string?,
	selectedToolIds: { string }?,
}

export type SelectionResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
	selectedBySlot: { [string]: string },
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

local function normalizeSelectedByRole(value: any): { [string]: string }
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

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end
	if type(nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY] = {}
	end

	nextProfile[PROFILE_KEY]["schemaVersion"] = STATE_VERSION
	nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][TinyfolkToolCatalogSchema.Roles.Tinyfolk] = normalizeSelectedByRole(
		nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][TinyfolkToolCatalogSchema.Roles.Tinyfolk]
	)

	return nextProfile
end

local function getUnlockedToolSet(profileData: any): { [string]: boolean }
	local unlockedSet: { [string]: boolean } = {}
	local progressionState = if type(profileData) == "table" then profileData["tinyfolkToolProgressionState"] else nil
	local unlockedToolIds = if type(progressionState) == "table" then progressionState["unlockedToolIds"] else nil
	if type(unlockedToolIds) ~= "table" then
		return unlockedSet
	end

	for _, toolId in ipairs(unlockedToolIds) do
		if type(toolId) == "string" and toolId ~= "" then
			unlockedSet[toolId] = true
		end
	end

	return unlockedSet
end

local function isToolUnlocked(profileData: any, toolRecord: any, toolId: string): boolean
	if toolRecord.unlockSource == TinyfolkToolCatalogSchema.UnlockSources.Starter then
		return true
	end
	return getUnlockedToolSet(profileData)[toolId] == true
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

function TinyfolkToolLoadoutState.GetSelectedLoadout(profileData: any, role: any): { [string]: string }
	local nextProfile = ensureProfileState(profileData)
	if role ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
		return {}
	end
	return cloneTable(nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][role])
end

function TinyfolkToolLoadoutState.ResolveSelection(
	profileData: any,
	input: SelectionInput,
	catalog: any?
): SelectionResult
	local nextProfile = ensureProfileState(profileData)
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "tool_loadout_request_invalid",
			profileData = nextProfile,
			selectedBySlot = {},
		}
	end
	if input.requesterRole ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			profileData = nextProfile,
			selectedBySlot = {},
		}
	end
	if type(input.selectedToolIds) ~= "table" then
		return {
			accepted = false,
			reason = "tool_loadout_request_invalid",
			profileData = nextProfile,
			selectedBySlot = {},
		}
	end

	local slotDefinitions = TinyfolkToolCatalogSchema.GetSlotDefinitions()
	local maxSlots = #slotDefinitions
	local nextSelectedBySlot: { [string]: string } = {}
	local seenToolIds: { [string]: boolean } = {}
	local assignedCount = 0

	for _, toolId in ipairs(input.selectedToolIds) do
		if type(toolId) ~= "string" or toolId == "" then
			return {
				accepted = false,
				reason = "invalid_tool_id",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if seenToolIds[toolId] == true then
			return {
				accepted = false,
				reason = "duplicate_tool_selected",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end

		local toolRecord, lookupReason = TinyfolkToolCatalogSchema.GetToolRecord(toolId, catalog)
		if toolRecord == nil then
			return {
				accepted = false,
				reason = lookupReason or "tool_missing",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if toolRecord.role ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
			return {
				accepted = false,
				reason = "tool_not_for_role",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if toolRecord.availability ~= TinyfolkToolCatalogSchema.Availability.Available then
			return {
				accepted = false,
				reason = "tool_locked_or_unavailable",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if not isToolUnlocked(nextProfile, toolRecord, toolId) then
			return {
				accepted = false,
				reason = "tool_locked_or_unavailable",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if not hasCooldownMetadata(toolRecord) then
			return {
				accepted = false,
				reason = "tool_cooldown_metadata_missing",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end

		assignedCount += 1
		if assignedCount > maxSlots then
			return {
				accepted = false,
				reason = "slot_capacity_exceeded",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end

		seenToolIds[toolId] = true
		nextSelectedBySlot[slotDefinitions[assignedCount].slotId] = toolId
	end

	nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][TinyfolkToolCatalogSchema.Roles.Tinyfolk] = nextSelectedBySlot
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		selectedBySlot = cloneTable(nextSelectedBySlot),
	}
end

function TinyfolkToolLoadoutState.BuildDefaultLoadout(profileData: any, role: any, catalog: any?): { [string]: string }
	if role ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
		return {}
	end

	local nextProfile = ensureProfileState(profileData)
	local slotDefinitions = TinyfolkToolCatalogSchema.GetSlotDefinitions()
	local selectedBySlot: { [string]: string } = {}
	local assignedCount = 0

	local records = TinyfolkToolCatalogSchema.GetAllToolRecords(catalog)
	table.sort(records, function(left: any, right: any)
		return left.toolId < right.toolId
	end)

	for _, toolRecord in ipairs(records) do
		if assignedCount >= #slotDefinitions then
			break
		end
		if
			toolRecord.role == TinyfolkToolCatalogSchema.Roles.Tinyfolk
			and toolRecord.availability == TinyfolkToolCatalogSchema.Availability.Available
			and hasCooldownMetadata(toolRecord)
			and isToolUnlocked(nextProfile, toolRecord, toolRecord.toolId)
		then
			assignedCount += 1
			selectedBySlot[slotDefinitions[assignedCount].slotId] = toolRecord.toolId
		end
	end

	return selectedBySlot
end

return TinyfolkToolLoadoutState
