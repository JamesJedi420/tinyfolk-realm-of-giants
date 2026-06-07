--!strict

local TraitRegistrySchema = require("../Config/TraitRegistrySchema")

local GiantTraitState: any = {}

local PROFILE_KEY = "giantTraitState"
local UNLOCKED_TRAIT_IDS_KEY = "unlockedTraitIds"

export type UnlockInput = {
	traitId: string,
	requesterRole: string?,
	unlockSource: string?,
}

export type UnlockTransition = {
	accepted: boolean,
	reason: string,
	profileData: any,
	traitId: string?,
}

export type ModifierSnapshot = {
	stationProductionMultiplier: number,
	scoreEventMultiplier: number,
	unlockedTraitIds: { string },
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

local function normalizeUnlockedTraitIds(value: any): { string }
	if type(value) ~= "table" then
		return {}
	end

	local seen: { [string]: boolean } = {}
	local normalized = {}
	for _, traitId in ipairs(value) do
		if type(traitId) == "string" and traitId ~= "" and not seen[traitId] then
			seen[traitId] = true
			table.insert(normalized, traitId)
		end
	end
	table.sort(normalized)
	return normalized
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end

	nextProfile[PROFILE_KEY][UNLOCKED_TRAIT_IDS_KEY] =
		normalizeUnlockedTraitIds(nextProfile[PROFILE_KEY][UNLOCKED_TRAIT_IDS_KEY])

	return nextProfile
end

local function getUnlockedSet(unlockedTraitIds: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, traitId in ipairs(unlockedTraitIds) do
		set[traitId] = true
	end
	return set
end

function GiantTraitState.GetUnlockedTraitIds(profileData: any): { string }
	local nextProfile = ensureProfileState(profileData)
	return cloneTable(nextProfile[PROFILE_KEY][UNLOCKED_TRAIT_IDS_KEY])
end

function GiantTraitState.ResolveUnlock(profileData: any, input: UnlockInput): UnlockTransition
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "unlock_request_invalid",
			profileData = ensureProfileState(profileData),
			traitId = nil,
		}
	end

	if type(input.traitId) ~= "string" or input.traitId == "" then
		return {
			accepted = false,
			reason = "invalid_trait_id",
			profileData = ensureProfileState(profileData),
			traitId = nil,
		}
	end

	if input.requesterRole ~= "Giant" then
		return {
			accepted = false,
			reason = "requester_not_giant",
			profileData = ensureProfileState(profileData),
			traitId = input.traitId,
		}
	end

	local traitRecord, lookupReason = TraitRegistrySchema.GetTraitRecord(input.traitId)
	if traitRecord == nil then
		return {
			accepted = false,
			reason = lookupReason or "trait_missing",
			profileData = ensureProfileState(profileData),
			traitId = input.traitId,
		}
	end

	if traitRecord.role ~= TraitRegistrySchema.Roles.Giant then
		return {
			accepted = false,
			reason = "trait_not_giant",
			profileData = ensureProfileState(profileData),
			traitId = input.traitId,
		}
	end

	if input.unlockSource ~= nil and input.unlockSource ~= traitRecord.unlockSource then
		return {
			accepted = false,
			reason = "trait_unlock_source_mismatch",
			profileData = ensureProfileState(profileData),
			traitId = input.traitId,
		}
	end

	if traitRecord.unlockSource ~= TraitRegistrySchema.UnlockSources.Initial then
		return {
			accepted = false,
			reason = "trait_unlock_source_unmet",
			profileData = ensureProfileState(profileData),
			traitId = input.traitId,
		}
	end

	local nextProfile = ensureProfileState(profileData)
	local unlockedTraitIds: { string } = nextProfile[PROFILE_KEY][UNLOCKED_TRAIT_IDS_KEY]
	local unlockedSet = getUnlockedSet(unlockedTraitIds)
	if unlockedSet[input.traitId] == true then
		return {
			accepted = false,
			reason = "trait_already_unlocked",
			profileData = nextProfile,
			traitId = input.traitId,
		}
	end

	table.insert(unlockedTraitIds, input.traitId)
	table.sort(unlockedTraitIds)

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		traitId = input.traitId,
	}
end

function GiantTraitState.ResolveModifierSnapshot(profileData: any): ModifierSnapshot
	local nextProfile = ensureProfileState(profileData)
	local unlockedTraitIds: { string } = nextProfile[PROFILE_KEY][UNLOCKED_TRAIT_IDS_KEY]
	local multiplier = 1
	local scoreEventMultiplier = 1

	for _, traitId in ipairs(unlockedTraitIds) do
		local traitRecord = TraitRegistrySchema.GetTraitRecord(traitId)
		if traitRecord ~= nil and traitRecord.role == TraitRegistrySchema.Roles.Giant then
			local modifiers: any = traitRecord.modifiers
			if type(modifiers) == "table" then
				local stationMultiplier = modifiers["stationProductionMultiplier"]
				if isFiniteNumber(stationMultiplier) and stationMultiplier > 0 then
					multiplier *= stationMultiplier
				end

				local scoreMultiplier = modifiers["scoreEventMultiplier"]
				if isFiniteNumber(scoreMultiplier) and scoreMultiplier > 0 then
					scoreEventMultiplier *= scoreMultiplier
				end
			end
		end
	end

	return {
		stationProductionMultiplier = multiplier,
		scoreEventMultiplier = scoreEventMultiplier,
		unlockedTraitIds = cloneTable(unlockedTraitIds),
	}
end

return GiantTraitState
