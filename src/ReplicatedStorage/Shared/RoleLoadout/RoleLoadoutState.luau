--!strict

local TraitRegistrySchema = require("../Config/TraitRegistrySchema")
local RoleLoadoutSchema = require("../Config/RoleLoadoutSchema")

local RoleLoadoutState: any = {}

local PROFILE_KEY = "roleLoadoutState"
local SELECTED_BY_ROLE_KEY = "selectedByRole"

export type SelectionInput = {
	requesterRole: string?,
	selectedTraitIds: { string }?,
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

local function normalizeSelectedByRole(value: any, role: string): { [string]: string }
	if type(value) ~= "table" then
		return {}
	end

	local normalized = {}
	local slotDefinitions = RoleLoadoutSchema.GetSlotDefinitions(role)
	for _, definition in ipairs(slotDefinitions) do
		local selectedTraitId = value[definition.slotId]
		if type(selectedTraitId) == "string" and selectedTraitId ~= "" then
			normalized[definition.slotId] = selectedTraitId
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

	nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][RoleLoadoutSchema.Roles.Giant] = normalizeSelectedByRole(
		nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][RoleLoadoutSchema.Roles.Giant],
		RoleLoadoutSchema.Roles.Giant
	)
	nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][RoleLoadoutSchema.Roles.Tinyfolk] = normalizeSelectedByRole(
		nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][RoleLoadoutSchema.Roles.Tinyfolk],
		RoleLoadoutSchema.Roles.Tinyfolk
	)

	return nextProfile
end

local function getGiantUnlockedTraitSet(profileData: any): { [string]: boolean }
	local unlockedSet: { [string]: boolean } = {}
	local giantTraitState: any = if type(profileData) == "table" then profileData["giantTraitState"] else nil
	local unlockedTraitIds: any = if type(giantTraitState) == "table" then giantTraitState["unlockedTraitIds"] else nil
	if type(unlockedTraitIds) ~= "table" then
		return unlockedSet
	end

	for _, traitId in ipairs(unlockedTraitIds) do
		if type(traitId) == "string" and traitId ~= "" then
			unlockedSet[traitId] = true
		end
	end
	return unlockedSet
end

local function isTraitTierAllowed(role: string, tier: any): boolean
	local maxTier = RoleLoadoutSchema.GetMaxSelectableTier(role)
	if type(maxTier) ~= "string" then
		return false
	end
	local tierValue = RoleLoadoutSchema.TierOrder[tier]
	local maxTierValue = RoleLoadoutSchema.TierOrder[maxTier]
	if type(tierValue) ~= "number" or type(maxTierValue) ~= "number" then
		return false
	end
	return tierValue <= maxTierValue
end

local function isTraitUnlocked(profileData: any, role: string, traitRecord: any, traitId: string): boolean
	if RoleLoadoutSchema.IsStarterUnlockSource(traitRecord.unlockSource) then
		return true
	end

	if not RoleLoadoutSchema.IsProgressionUnlockSource(traitRecord.unlockSource) then
		return false
	end

	if role == RoleLoadoutSchema.Roles.Giant then
		return getGiantUnlockedTraitSet(profileData)[traitId] == true
	end

	return false
end

local function sortRecordsForDefaultLoadout(records: { any }, role: string)
	table.sort(records, function(left: any, right: any)
		local leftPriority = if left.role == role then 0 else 1
		local rightPriority = if right.role == role then 0 else 1
		if leftPriority ~= rightPriority then
			return leftPriority < rightPriority
		end
		local slotTypePriority = {
			passive = 1,
			active = 2,
			support = 3,
			primary = 4,
			secondary = 5,
		}
		local leftSlotPriority = slotTypePriority[left.slotType] or 99
		local rightSlotPriority = slotTypePriority[right.slotType] or 99
		if leftSlotPriority ~= rightSlotPriority then
			return leftSlotPriority < rightSlotPriority
		end
		return left.traitId < right.traitId
	end)
end

function RoleLoadoutState.GetSelectedLoadout(profileData: any, role: any): { [string]: string }
	local nextProfile = ensureProfileState(profileData)
	if not RoleLoadoutSchema.IsValidRole(role) then
		return {}
	end
	return cloneTable(nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][role])
end

function RoleLoadoutState.ResolveSelection(profileData: any, input: SelectionInput, registry: any?): SelectionResult
	local nextProfile = ensureProfileState(profileData)
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "loadout_request_invalid",
			profileData = nextProfile,
			selectedBySlot = {},
		}
	end
	if not RoleLoadoutSchema.IsValidRole(input.requesterRole) then
		return {
			accepted = false,
			reason = "invalid_role",
			profileData = nextProfile,
			selectedBySlot = {},
		}
	end
	if type(input.selectedTraitIds) ~= "table" then
		return {
			accepted = false,
			reason = "loadout_request_invalid",
			profileData = nextProfile,
			selectedBySlot = {},
		}
	end

	local role = input.requesterRole :: string
	local slotIdsByType = RoleLoadoutSchema.GetSlotIdsByType(role)
	local nextSelectedBySlot: { [string]: string } = {}
	local seenTraitIds: { [string]: boolean } = {}
	local assignedCountBySlotType: { [string]: number } = {}
	local activeChannels: { [string]: boolean } = {}

	for _, traitId in ipairs(input.selectedTraitIds) do
		if type(traitId) ~= "string" or traitId == "" then
			return {
				accepted = false,
				reason = "invalid_trait_id",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if seenTraitIds[traitId] == true then
			return {
				accepted = false,
				reason = "duplicate_trait_selected",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end

		local traitRecord, lookupReason = TraitRegistrySchema.GetTraitRecord(traitId, registry)
		if traitRecord == nil then
			return {
				accepted = false,
				reason = lookupReason or "trait_missing",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if traitRecord.role ~= role and traitRecord.role ~= TraitRegistrySchema.Roles.Shared then
			return {
				accepted = false,
				reason = "trait_not_for_role",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if not isTraitTierAllowed(role, traitRecord.tier) then
			return {
				accepted = false,
				reason = "trait_tier_not_allowed",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end
		if not isTraitUnlocked(nextProfile, role, traitRecord, traitId) then
			return {
				accepted = false,
				reason = "trait_not_unlocked",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end

		local slotType = traitRecord.slotType
		local slotIdsForType = slotIdsByType[slotType]
		if type(slotIdsForType) ~= "table" then
			return {
				accepted = false,
				reason = "invalid_slot_type",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end

		local nextCount = (assignedCountBySlotType[slotType] or 0) + 1
		if nextCount > #slotIdsForType then
			return {
				accepted = false,
				reason = "slot_capacity_exceeded",
				profileData = nextProfile,
				selectedBySlot = {},
			}
		end

		local loadoutPattern: any = traitRecord.loadoutPattern
		if type(loadoutPattern) == "table" and loadoutPattern.patternType == "active_channel" then
			local activeChannel = (loadoutPattern :: any)["activeChannel"]
			if type(activeChannel) == "string" and activeChannel ~= "" then
				if activeChannels[activeChannel] == true then
					return {
						accepted = false,
						reason = "active_channel_conflict",
						profileData = nextProfile,
						selectedBySlot = {},
					}
				end
				activeChannels[activeChannel] = true
			end
		end

		seenTraitIds[traitId] = true
		assignedCountBySlotType[slotType] = nextCount
		nextSelectedBySlot[slotIdsForType[nextCount]] = traitId
	end

	nextProfile[PROFILE_KEY][SELECTED_BY_ROLE_KEY][role] = nextSelectedBySlot
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		selectedBySlot = cloneTable(nextSelectedBySlot),
	}
end

function RoleLoadoutState.BuildDefaultLoadout(profileData: any, role: any, registry: any?): { [string]: string }
	if not RoleLoadoutSchema.IsValidRole(role) then
		return {}
	end

	local candidateRecords = {}
	for _, record in ipairs(TraitRegistrySchema.GetAllTraitRecords(registry)) do
		if
			(record.role == role or record.role == TraitRegistrySchema.Roles.Shared)
			and RoleLoadoutSchema.IsStarterUnlockSource(record.unlockSource)
			and isTraitTierAllowed(role, record.tier)
		then
			table.insert(candidateRecords, record)
		end
	end
	sortRecordsForDefaultLoadout(candidateRecords, role)

	local currentProfile = ensureProfileState(profileData)
	local slotIdsByType = RoleLoadoutSchema.GetSlotIdsByType(role)
	local selectedBySlot: { [string]: string } = {}
	local assignedCountBySlotType: { [string]: number } = {}
	local activeChannels: { [string]: boolean } = {}

	for _, traitRecord in ipairs(candidateRecords) do
		local traitId = traitRecord.traitId
		if isTraitUnlocked(currentProfile, role, traitRecord, traitId) then
			local slotIdsForType = slotIdsByType[traitRecord.slotType]
			local nextCount = (assignedCountBySlotType[traitRecord.slotType] or 0) + 1
			local loadoutPattern: any = traitRecord.loadoutPattern
			local activeChannel = if type(loadoutPattern) == "table"
				then (loadoutPattern :: any)["activeChannel"]
				else nil
			local hasChannelConflict = type(activeChannel) == "string"
				and activeChannel ~= ""
				and activeChannels[activeChannel] == true
			if type(slotIdsForType) == "table" and nextCount <= #slotIdsForType and not hasChannelConflict then
				selectedBySlot[slotIdsForType[nextCount]] = traitId
				assignedCountBySlotType[traitRecord.slotType] = nextCount
				if type(activeChannel) == "string" and activeChannel ~= "" then
					activeChannels[activeChannel] = true
				end
			end
		end
	end

	return selectedBySlot
end

return RoleLoadoutState
