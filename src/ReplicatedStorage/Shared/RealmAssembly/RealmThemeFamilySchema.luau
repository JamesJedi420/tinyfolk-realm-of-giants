--!strict

local RealmThemeFamilySchema: any = {}

export type ThemeAccessibilityDefaults = {
	readabilityProfile: string,
	colorContrastMode: string,
	requiresAlternativeRoutes: boolean,
}

export type ThemeFamilyRecord = {
	themeId: string,
	assetPaletteIds: { string },
	lightingProfileIds: { string },
	audioProfileIds: { string },
	allowedDistrictTypes: { string },
	landmarkTags: { string },
	districtTags: { string },
	variantRules: { string },
	accessibilityDefaults: ThemeAccessibilityDefaults,
}

RealmThemeFamilySchema.DEFAULT_THEME_FAMILY_REGISTRY = {
	{
		themeId = "industrial_frontier",
		assetPaletteIds = { "palette_iron_brick" },
		lightingProfileIds = { "lighting_smoky_dawn" },
		audioProfileIds = { "audio_mechanical_wind" },
		allowedDistrictTypes = { "workyard", "warehouse", "catwalk", "service_tunnel" },
		landmarkTags = { "furnace_core", "loading_crane", "smoke_stack" },
		districtTags = { "high_wall", "low_visibility", "vertical_link" },
		variantRules = { "night_shift", "steam_overload", "storm_front" },
		accessibilityDefaults = {
			readabilityProfile = "high",
			colorContrastMode = "high",
			requiresAlternativeRoutes = true,
		},
	},
	{
		themeId = "flooded_settlement",
		assetPaletteIds = { "palette_moss_stone" },
		lightingProfileIds = { "lighting_foggy_noon" },
		audioProfileIds = { "audio_water_echo" },
		allowedDistrictTypes = { "canal", "plaza", "garden", "drainway" },
		landmarkTags = { "bell_tower", "collapsed_courtyard", "sluice_hub" },
		districtTags = { "open_sightline", "flooded_lane", "detour_cluster" },
		variantRules = { "heavy_rain", "low_tide" },
		accessibilityDefaults = {
			readabilityProfile = "standard",
			colorContrastMode = "high",
			requiresAlternativeRoutes = true,
		},
	},
}

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return string.len(value) > 0
end

local function hasUniqueStrings(values: { string }): boolean
	local seen = {}
	for _, value in ipairs(values) do
		if seen[value] then
			return false
		end
		seen[value] = true
	end
	return true
end

local function cloneStringArray(source: { string }): { string }
	local result = {}
	for _, value in ipairs(source) do
		table.insert(result, value)
	end
	return result
end

local function validateStringArray(values: any, reason: string, minimumCount: number?): (boolean, string?)
	if type(values) ~= "table" then
		return false, reason
	end
	if minimumCount ~= nil and #values < minimumCount then
		return false, reason
	end
	for _, value in ipairs(values) do
		if not isNonEmptyString(value) then
			return false, reason
		end
	end
	if not hasUniqueStrings(values) then
		return false, reason
	end
	return true, nil
end

local function cloneRecord(record: ThemeFamilyRecord): ThemeFamilyRecord
	return {
		themeId = record.themeId,
		assetPaletteIds = cloneStringArray(record.assetPaletteIds),
		lightingProfileIds = cloneStringArray(record.lightingProfileIds),
		audioProfileIds = cloneStringArray(record.audioProfileIds),
		allowedDistrictTypes = cloneStringArray(record.allowedDistrictTypes),
		landmarkTags = cloneStringArray(record.landmarkTags),
		districtTags = cloneStringArray(record.districtTags),
		variantRules = cloneStringArray(record.variantRules),
		accessibilityDefaults = {
			readabilityProfile = record.accessibilityDefaults.readabilityProfile,
			colorContrastMode = record.accessibilityDefaults.colorContrastMode,
			requiresAlternativeRoutes = record.accessibilityDefaults.requiresAlternativeRoutes,
		},
	}
end

local function hasString(values: { string }, expected: string): boolean
	for _, value in ipairs(values) do
		if value == expected then
			return true
		end
	end
	return false
end

function RealmThemeFamilySchema.ValidateThemeFamilyRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "theme_family_record_invalid"
	end
	if not isNonEmptyString(record.themeId) then
		return false, "theme_family_id_invalid"
	end

	local ok, reason = validateStringArray(record.assetPaletteIds, "theme_family_asset_palettes_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.lightingProfileIds, "theme_family_lighting_profiles_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.audioProfileIds, "theme_family_audio_profiles_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.allowedDistrictTypes, "theme_family_allowed_district_types_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.landmarkTags, "theme_family_landmark_tags_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.districtTags, "theme_family_district_tags_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.variantRules, "theme_family_variant_rules_invalid", 1)
	if not ok then
		return false, reason
	end

	if type(record.accessibilityDefaults) ~= "table" then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if not isNonEmptyString(record.accessibilityDefaults.readabilityProfile) then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if not isNonEmptyString(record.accessibilityDefaults.colorContrastMode) then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if type(record.accessibilityDefaults.requiresAlternativeRoutes) ~= "boolean" then
		return false, "theme_family_accessibility_defaults_invalid"
	end

	return true, nil
end

function RealmThemeFamilySchema.ValidateThemeFamilyRegistry(registry: any): (boolean, string?)
	if type(registry) ~= "table" then
		return false, "theme_family_registry_invalid"
	end

	local seenThemeIds = {}
	for index, record in ipairs(registry) do
		local valid, reason = RealmThemeFamilySchema.ValidateThemeFamilyRecord(record)
		if not valid then
			return false, string.format("%s index=%d", reason or "theme_family_record_invalid", index)
		end
		if seenThemeIds[record.themeId] then
			return false, string.format("theme_family_id_duplicate index=%d", index)
		end
		seenThemeIds[record.themeId] = true
	end

	return true, nil
end

function RealmThemeFamilySchema.GetThemeFamilyRecord(themeId: any, registry: any?): (ThemeFamilyRecord?, string?)
	if not isNonEmptyString(themeId) then
		return nil, "theme_family_id_invalid"
	end

	local source: any = registry
	if source == nil then
		source = RealmThemeFamilySchema.DEFAULT_THEME_FAMILY_REGISTRY
	end

	for _, record in ipairs(source :: { any }) do
		if record.themeId == themeId then
			return cloneRecord(record), nil
		end
	end

	return nil, "theme_family_missing"
end

function RealmThemeFamilySchema.GetAllThemeFamilyRecords(registry: any?): { ThemeFamilyRecord }
	local source: any = registry
	if source == nil then
		source = RealmThemeFamilySchema.DEFAULT_THEME_FAMILY_REGISTRY
	end

	local result = {}
	for _, record in ipairs(source :: { any }) do
		table.insert(result, cloneRecord(record))
	end
	table.sort(result, function(a: ThemeFamilyRecord, b: ThemeFamilyRecord)
		return a.themeId < b.themeId
	end)

	return result
end

function RealmThemeFamilySchema.BuildThemeFamilySnapshot(registry: any?): { ThemeFamilyRecord }
	return RealmThemeFamilySchema.GetAllThemeFamilyRecords(registry)
end

function RealmThemeFamilySchema.ValidateThemeLink(input: any, registry: any?): (boolean, string?)
	if type(input) ~= "table" then
		return false, "theme_link_input_invalid"
	end
	if not isNonEmptyString(input.themeId) then
		return false, "theme_family_missing"
	end
	if not isNonEmptyString(input.assetPaletteId) then
		return false, "theme_family_asset_palette_invalid"
	end
	if not isNonEmptyString(input.lightingProfileId) then
		return false, "theme_family_lighting_profile_invalid"
	end
	if not isNonEmptyString(input.audioProfileId) then
		return false, "theme_family_audio_profile_invalid"
	end

	local ok, reason = validateStringArray(input.allowedDistrictTypes, "theme_family_allowed_district_types_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(input.landmarkTags, "theme_family_landmark_tags_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(input.districtTags, "theme_family_district_tags_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(input.variantRules, "theme_family_variant_rules_invalid", 1)
	if not ok then
		return false, reason
	end

	if type(input.accessibilityProfile) ~= "table" then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if not isNonEmptyString(input.accessibilityProfile.readabilityProfile) then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if not isNonEmptyString(input.accessibilityProfile.colorContrastMode) then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if type(input.accessibilityProfile.requiresAlternativeRoutes) ~= "boolean" then
		return false, "theme_family_accessibility_defaults_invalid"
	end

	local record, missingReason = RealmThemeFamilySchema.GetThemeFamilyRecord(input.themeId, registry)
	if record == nil then
		return false, missingReason or "theme_family_missing"
	end

	if not hasString(record.assetPaletteIds, input.assetPaletteId) then
		return false, "theme_family_asset_palette_invalid"
	end
	if not hasString(record.lightingProfileIds, input.lightingProfileId) then
		return false, "theme_family_lighting_profile_invalid"
	end
	if not hasString(record.audioProfileIds, input.audioProfileId) then
		return false, "theme_family_audio_profile_invalid"
	end
	for _, districtType in ipairs(input.allowedDistrictTypes) do
		if not hasString(record.allowedDistrictTypes, districtType) then
			return false, "theme_family_allowed_district_types_invalid"
		end
	end
	for _, landmarkTag in ipairs(input.landmarkTags) do
		if not hasString(record.landmarkTags, landmarkTag) then
			return false, "theme_family_landmark_tags_invalid"
		end
	end
	for _, districtTag in ipairs(input.districtTags) do
		if not hasString(record.districtTags, districtTag) then
			return false, "theme_family_district_tags_invalid"
		end
	end
	for _, variantRule in ipairs(input.variantRules) do
		if not hasString(record.variantRules, variantRule) then
			return false, "theme_family_variant_rules_invalid"
		end
	end
	if input.accessibilityProfile.readabilityProfile ~= record.accessibilityDefaults.readabilityProfile then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if input.accessibilityProfile.colorContrastMode ~= record.accessibilityDefaults.colorContrastMode then
		return false, "theme_family_accessibility_defaults_invalid"
	end
	if
		input.accessibilityProfile.requiresAlternativeRoutes ~= record.accessibilityDefaults.requiresAlternativeRoutes
	then
		return false, "theme_family_accessibility_defaults_invalid"
	end

	return true, nil
end

return RealmThemeFamilySchema
