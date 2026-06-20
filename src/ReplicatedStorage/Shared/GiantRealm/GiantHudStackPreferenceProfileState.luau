--!strict

local GiantHudStackConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("GiantHudStackConfig"))
	else (require :: any)("../Config/GiantHudStackConfig")

local GiantHudStackPreferenceProfileState: any = {}

GiantHudStackPreferenceProfileState.PROFILE_KEY = "giantHudStackPreference"
GiantHudStackPreferenceProfileState.EXPANDED_BY_SECTION_ID_KEY = "expandedBySectionId"

export type PreferenceSnapshot = {
	expandedBySectionId: { [string]: boolean },
}

export type PersistResult = {
	accepted: boolean,
	reason: string,
	profileData: any,
	preference: PreferenceSnapshot?,
}

local PROFILE_KEY = GiantHudStackPreferenceProfileState.PROFILE_KEY
local EXPANDED_BY_SECTION_ID_KEY = GiantHudStackPreferenceProfileState.EXPANDED_BY_SECTION_ID_KEY

local validSectionIds: { [string]: boolean } = {}
for _, sectionId in ipairs(GiantHudStackConfig.SectionOrder) do
	validSectionIds[sectionId] = true
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

local function normalizeExpanded(value: any): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

local function isValidSectionId(sectionId: any): boolean
	return type(sectionId) == "string" and validSectionIds[sectionId] == true
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end
	return nextProfile
end

local function createDefaultExpandedBySectionId(): { [string]: boolean }
	local defaults: { [string]: boolean } = {}
	for _, sectionId in ipairs(GiantHudStackConfig.SectionOrder) do
		defaults[sectionId] = false
	end
	return defaults
end

local function normalizeExpandedBySectionId(rawMap: any): { [string]: boolean }
	local snapshot = createDefaultExpandedBySectionId()
	if type(rawMap) ~= "table" then
		return snapshot
	end

	for sectionId, expanded in pairs(rawMap) do
		if isValidSectionId(sectionId) then
			local normalizedExpanded = normalizeExpanded(expanded)
			if normalizedExpanded ~= nil then
				snapshot[sectionId] = normalizedExpanded
			end
		end
	end

	return snapshot
end

local function hasAnyPersistedExpandedValue(rawPreference: any): boolean
	if type(rawPreference) ~= "table" then
		return false
	end

	local rawMap = rawPreference[EXPANDED_BY_SECTION_ID_KEY]
	if type(rawMap) ~= "table" then
		return false
	end

	for sectionId, expanded in pairs(rawMap) do
		if isValidSectionId(sectionId) and normalizeExpanded(expanded) ~= nil then
			return true
		end
	end

	return false
end

local function buildPersistedPreference(snapshot: PreferenceSnapshot): any
	local normalizedMap = normalizeExpandedBySectionId(snapshot.expandedBySectionId)
	local persisted: { [string]: boolean } = {}

	for _, sectionId in ipairs(GiantHudStackConfig.SectionOrder) do
		persisted[sectionId] = normalizedMap[sectionId] == true
	end

	return {
		[EXPANDED_BY_SECTION_ID_KEY] = persisted,
	}
end

function GiantHudStackPreferenceProfileState.CreateDefaultPreference(): PreferenceSnapshot
	return {
		expandedBySectionId = createDefaultExpandedBySectionId(),
	}
end

function GiantHudStackPreferenceProfileState.HasPersistedState(profileData: any): boolean
	if type(profileData) ~= "table" then
		return false
	end

	return hasAnyPersistedExpandedValue(profileData[PROFILE_KEY])
end

function GiantHudStackPreferenceProfileState.GetPreference(profileData: any): PreferenceSnapshot
	if not GiantHudStackPreferenceProfileState.HasPersistedState(profileData) then
		return GiantHudStackPreferenceProfileState.CreateDefaultPreference()
	end

	local rawPreference = profileData[PROFILE_KEY]
	return {
		expandedBySectionId = normalizeExpandedBySectionId(rawPreference[EXPANDED_BY_SECTION_ID_KEY]),
	}
end

function GiantHudStackPreferenceProfileState.CopyProfileField(profileData: any): any?
	if type(profileData) ~= "table" then
		return nil
	end

	if not GiantHudStackPreferenceProfileState.HasPersistedState(profileData) then
		return nil
	end

	local snapshot = GiantHudStackPreferenceProfileState.GetPreference(profileData)
	return buildPersistedPreference(snapshot)
end

function GiantHudStackPreferenceProfileState.ApplySectionExpanded(
	profileData: any,
	sectionId: any,
	expanded: any
): PersistResult
	if not isValidSectionId(sectionId) then
		return {
			accepted = false,
			reason = "section_id_invalid",
			profileData = ensureProfileState(profileData),
			preference = nil,
		}
	end

	local normalizedExpanded = normalizeExpanded(expanded)
	if normalizedExpanded == nil then
		return {
			accepted = false,
			reason = "expanded_invalid",
			profileData = ensureProfileState(profileData),
			preference = nil,
		}
	end

	local currentPreference = GiantHudStackPreferenceProfileState.GetPreference(profileData)
	local nextExpandedBySectionId = cloneTable(currentPreference.expandedBySectionId)
	nextExpandedBySectionId[sectionId] = normalizedExpanded

	local nextProfile = ensureProfileState(profileData)
	local persisted = buildPersistedPreference({
		expandedBySectionId = nextExpandedBySectionId,
	})

	nextProfile[PROFILE_KEY] = persisted
	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		preference = {
			expandedBySectionId = normalizeExpandedBySectionId(nextExpandedBySectionId),
		},
	}
end

return GiantHudStackPreferenceProfileState
