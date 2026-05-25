--!strict

local RealmThemeFamilySchema = require("./RealmThemeFamilySchema")

local RealmMetadataRegistry: any = {}

export type TraversalDensity = "sparse" | "balanced" | "dense"

export type SizeBudget = {
	maxDistricts: number,
	maxLandmarks: number,
	maxRecurringStructures: number,
}

export type EscapeRequirements = {
	minimumEscapeRoutes: number,
	requiresFallbackEscapeCandidate: boolean,
	requiresFinalExitAnchor: boolean,
}

export type AccessibilityProfile = {
	readabilityProfile: string,
	colorContrastMode: string,
	requiresAlternativeRoutes: boolean,
}

export type LandmarkRules = {
	requiredLandmarkTags: { string },
	minimumLandmarkCount: number,
}

export type RouteVisibilitySignals = {
	sightBlocker: number,
	narrowLane: number,
	giantDetourPressure: number,
	tinyfolkSqueezeRoute: number,
	landmarkOcclusion: number,
	obstacleDensity: number,
	routeTransitionDensity: number,
}

export type RealmMetadataRecord = {
	realmTemplateId: string,
	themeId: string,
	assetPaletteId: string,
	lightingProfileId: string,
	audioProfileId: string,
	allowedDistrictTypes: { string },
	recurringStructureTags: { string },
	landmarkTags: { string },
	districtTags: { string },
	landmarkRules: LandmarkRules,
	sizeBudget: SizeBudget,
	traversalDensity: TraversalDensity,
	escapeRequirements: EscapeRequirements,
	accessibilityProfile: AccessibilityProfile,
	variantRules: { string },
	routeVisibilitySignals: RouteVisibilitySignals,
}

export type SelectionInput = {
	requiredDistrictType: string?,
	requiredLandmarkTag: string?,
	minimumTraversalDensity: TraversalDensity?,
	requiresAlternativeRoutes: boolean?,
}

local DENSITY_RANK: { [TraversalDensity]: number } = {
	sparse = 1,
	balanced = 2,
	dense = 3,
}

local SIGNAL_KEYS = {
	"sightBlocker",
	"narrowLane",
	"giantDetourPressure",
	"tinyfolkSqueezeRoute",
	"landmarkOcclusion",
	"obstacleDensity",
	"routeTransitionDensity",
}

RealmMetadataRegistry.DEFAULT_REALM_METADATA_REGISTRY = {
	{
		realmTemplateId = "FoundryBasin",
		themeId = "industrial_frontier",
		assetPaletteId = "palette_iron_brick",
		lightingProfileId = "lighting_smoky_dawn",
		audioProfileId = "audio_mechanical_wind",
		allowedDistrictTypes = { "workyard", "warehouse", "catwalk", "service_tunnel" },
		recurringStructureTags = { "shack_anchor", "tower_rig", "gantry_bridge" },
		landmarkTags = { "furnace_core", "loading_crane", "smoke_stack" },
		districtTags = { "high_wall", "low_visibility", "vertical_link" },
		landmarkRules = {
			requiredLandmarkTags = { "furnace_core" },
			minimumLandmarkCount = 3,
		},
		sizeBudget = {
			maxDistricts = 24,
			maxLandmarks = 10,
			maxRecurringStructures = 30,
		},
		traversalDensity = "dense",
		escapeRequirements = {
			minimumEscapeRoutes = 3,
			requiresFallbackEscapeCandidate = true,
			requiresFinalExitAnchor = true,
		},
		accessibilityProfile = {
			readabilityProfile = "high",
			colorContrastMode = "high",
			requiresAlternativeRoutes = true,
		},
		variantRules = { "night_shift", "steam_overload", "storm_front" },
		routeVisibilitySignals = {
			sightBlocker = 0.8,
			narrowLane = 0.7,
			giantDetourPressure = 0.6,
			tinyfolkSqueezeRoute = 0.9,
			landmarkOcclusion = 0.75,
			obstacleDensity = 0.8,
			routeTransitionDensity = 0.65,
		},
	},
	{
		realmTemplateId = "SunkenWard",
		themeId = "flooded_settlement",
		assetPaletteId = "palette_moss_stone",
		lightingProfileId = "lighting_foggy_noon",
		audioProfileId = "audio_water_echo",
		allowedDistrictTypes = { "canal", "plaza", "garden", "drainway" },
		recurringStructureTags = { "market_ruin", "watch_post", "water_gate" },
		landmarkTags = { "bell_tower", "collapsed_courtyard", "sluice_hub" },
		districtTags = { "open_sightline", "flooded_lane", "detour_cluster" },
		landmarkRules = {
			requiredLandmarkTags = { "bell_tower" },
			minimumLandmarkCount = 2,
		},
		sizeBudget = {
			maxDistricts = 18,
			maxLandmarks = 8,
			maxRecurringStructures = 22,
		},
		traversalDensity = "balanced",
		escapeRequirements = {
			minimumEscapeRoutes = 2,
			requiresFallbackEscapeCandidate = true,
			requiresFinalExitAnchor = true,
		},
		accessibilityProfile = {
			readabilityProfile = "standard",
			colorContrastMode = "high",
			requiresAlternativeRoutes = true,
		},
		variantRules = { "heavy_rain", "low_tide" },
		routeVisibilitySignals = {
			sightBlocker = 0.5,
			narrowLane = 0.45,
			giantDetourPressure = 0.4,
			tinyfolkSqueezeRoute = 0.55,
			landmarkOcclusion = 0.5,
			obstacleDensity = 0.45,
			routeTransitionDensity = 0.6,
		},
	},
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
	return string.len(value) > 0
end

local function cloneStringArray(source: { string }): { string }
	local result = {}
	for _, value in ipairs(source) do
		table.insert(result, value)
	end
	return result
end

local function cloneRecord(record: RealmMetadataRecord): RealmMetadataRecord
	return {
		realmTemplateId = record.realmTemplateId,
		themeId = record.themeId,
		assetPaletteId = record.assetPaletteId,
		lightingProfileId = record.lightingProfileId,
		audioProfileId = record.audioProfileId,
		allowedDistrictTypes = cloneStringArray(record.allowedDistrictTypes),
		recurringStructureTags = cloneStringArray(record.recurringStructureTags),
		landmarkTags = cloneStringArray(record.landmarkTags),
		districtTags = cloneStringArray(record.districtTags),
		landmarkRules = {
			requiredLandmarkTags = cloneStringArray(record.landmarkRules.requiredLandmarkTags),
			minimumLandmarkCount = record.landmarkRules.minimumLandmarkCount,
		},
		sizeBudget = {
			maxDistricts = record.sizeBudget.maxDistricts,
			maxLandmarks = record.sizeBudget.maxLandmarks,
			maxRecurringStructures = record.sizeBudget.maxRecurringStructures,
		},
		traversalDensity = record.traversalDensity,
		escapeRequirements = {
			minimumEscapeRoutes = record.escapeRequirements.minimumEscapeRoutes,
			requiresFallbackEscapeCandidate = record.escapeRequirements.requiresFallbackEscapeCandidate,
			requiresFinalExitAnchor = record.escapeRequirements.requiresFinalExitAnchor,
		},
		accessibilityProfile = {
			readabilityProfile = record.accessibilityProfile.readabilityProfile,
			colorContrastMode = record.accessibilityProfile.colorContrastMode,
			requiresAlternativeRoutes = record.accessibilityProfile.requiresAlternativeRoutes,
		},
		variantRules = cloneStringArray(record.variantRules),
		routeVisibilitySignals = {
			sightBlocker = record.routeVisibilitySignals.sightBlocker,
			narrowLane = record.routeVisibilitySignals.narrowLane,
			giantDetourPressure = record.routeVisibilitySignals.giantDetourPressure,
			tinyfolkSqueezeRoute = record.routeVisibilitySignals.tinyfolkSqueezeRoute,
			landmarkOcclusion = record.routeVisibilitySignals.landmarkOcclusion,
			obstacleDensity = record.routeVisibilitySignals.obstacleDensity,
			routeTransitionDensity = record.routeVisibilitySignals.routeTransitionDensity,
		},
	}
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

local function validateRouteVisibilitySignals(signals: any): (boolean, string?)
	if type(signals) ~= "table" then
		return false, "route_visibility_signals_invalid"
	end
	for _, key in ipairs(SIGNAL_KEYS) do
		local value = signals[key]
		if not isFiniteNumber(value) or value < 0 or value > 1 then
			return false, "route_visibility_signals_invalid"
		end
	end
	return true, nil
end

function RealmMetadataRegistry.ValidateRealmMetadataRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "realm_metadata_record_invalid"
	end
	if not isNonEmptyString(record.realmTemplateId) then
		return false, "realm_template_id_invalid"
	end
	if not isNonEmptyString(record.themeId) then
		return false, "theme_id_invalid"
	end
	if not isNonEmptyString(record.assetPaletteId) then
		return false, "asset_palette_id_invalid"
	end
	if not isNonEmptyString(record.lightingProfileId) then
		return false, "lighting_profile_id_invalid"
	end
	if not isNonEmptyString(record.audioProfileId) then
		return false, "audio_profile_id_invalid"
	end

	local ok, reason = validateStringArray(record.allowedDistrictTypes, "allowed_district_types_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.recurringStructureTags, "recurring_structure_tags_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.landmarkTags, "landmark_tags_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.districtTags, "district_tags_invalid", 1)
	if not ok then
		return false, reason
	end
	ok, reason = validateStringArray(record.variantRules, "variant_rules_invalid", 1)
	if not ok then
		return false, reason
	end

	if type(record.landmarkRules) ~= "table" then
		return false, "landmark_rules_invalid"
	end
	ok, reason = validateStringArray(record.landmarkRules.requiredLandmarkTags, "landmark_rules_invalid", 1)
	if not ok then
		return false, reason
	end
	if not isPositiveInteger(record.landmarkRules.minimumLandmarkCount) then
		return false, "landmark_rules_invalid"
	end

	if type(record.sizeBudget) ~= "table" then
		return false, "size_budget_invalid"
	end
	if not isPositiveInteger(record.sizeBudget.maxDistricts) then
		return false, "size_budget_invalid"
	end
	if not isPositiveInteger(record.sizeBudget.maxLandmarks) then
		return false, "size_budget_invalid"
	end
	if not isPositiveInteger(record.sizeBudget.maxRecurringStructures) then
		return false, "size_budget_invalid"
	end
	if record.sizeBudget.maxLandmarks > record.sizeBudget.maxRecurringStructures then
		return false, "size_budget_invalid"
	end

	local traversalDensityKey = record.traversalDensity
	if type(traversalDensityKey) ~= "string" or (DENSITY_RANK :: any)[traversalDensityKey] == nil then
		return false, "traversal_density_invalid"
	end

	if type(record.escapeRequirements) ~= "table" then
		return false, "escape_requirements_invalid"
	end
	if not isPositiveInteger(record.escapeRequirements.minimumEscapeRoutes) then
		return false, "escape_requirements_invalid"
	end
	if type(record.escapeRequirements.requiresFallbackEscapeCandidate) ~= "boolean" then
		return false, "escape_requirements_invalid"
	end
	if type(record.escapeRequirements.requiresFinalExitAnchor) ~= "boolean" then
		return false, "escape_requirements_invalid"
	end

	if type(record.accessibilityProfile) ~= "table" then
		return false, "accessibility_profile_invalid"
	end
	if not isNonEmptyString(record.accessibilityProfile.readabilityProfile) then
		return false, "accessibility_profile_invalid"
	end
	if not isNonEmptyString(record.accessibilityProfile.colorContrastMode) then
		return false, "accessibility_profile_invalid"
	end
	if type(record.accessibilityProfile.requiresAlternativeRoutes) ~= "boolean" then
		return false, "accessibility_profile_invalid"
	end

	ok, reason = validateRouteVisibilitySignals(record.routeVisibilitySignals)
	if not ok then
		return false, reason
	end

	return true, nil
end

function RealmMetadataRegistry.ValidateRealmMetadataRegistry(
	registry: any,
	themeFamilyRegistry: any?
): (boolean, string?)
	if type(registry) ~= "table" then
		return false, "realm_metadata_registry_invalid"
	end

	local resolvedThemeRegistry = themeFamilyRegistry
	if resolvedThemeRegistry == nil then
		resolvedThemeRegistry = RealmThemeFamilySchema.DEFAULT_THEME_FAMILY_REGISTRY
	end

	local validThemeRegistry, themeRegistryReason =
		RealmThemeFamilySchema.ValidateThemeFamilyRegistry(resolvedThemeRegistry)
	if not validThemeRegistry then
		return false, themeRegistryReason or "theme_family_registry_invalid"
	end

	local seenTemplateIds = {}
	for index, record in ipairs(registry) do
		local valid, reason = RealmMetadataRegistry.ValidateRealmMetadataRecord(record)
		if not valid then
			return false, string.format("%s index=%d", reason or "realm_metadata_record_invalid", index)
		end

		local themeLinked, themeReason = RealmThemeFamilySchema.ValidateThemeLink(record, resolvedThemeRegistry)
		if not themeLinked then
			return false, string.format("%s index=%d", themeReason or "theme_family_link_invalid", index)
		end

		if seenTemplateIds[record.realmTemplateId] then
			return false, string.format("realm_template_id_duplicate index=%d", index)
		end
		seenTemplateIds[record.realmTemplateId] = true
	end

	return true, nil
end

function RealmMetadataRegistry.GetAllRealmMetadataRecords(registry: any?): { RealmMetadataRecord }
	local source: any = registry
	if source == nil then
		source = RealmMetadataRegistry.DEFAULT_REALM_METADATA_REGISTRY
	end

	local result = {}
	for _, record in ipairs(source :: { any }) do
		table.insert(result, cloneRecord(record))
	end
	table.sort(result, function(a: RealmMetadataRecord, b: RealmMetadataRecord)
		return a.realmTemplateId < b.realmTemplateId
	end)
	return result
end

function RealmMetadataRegistry.GetRealmMetadataRecord(
	realmTemplateId: any,
	registry: any?
): (RealmMetadataRecord?, string?)
	if not isNonEmptyString(realmTemplateId) then
		return nil, "realm_template_id_invalid"
	end

	local source: any = registry
	if source == nil then
		source = RealmMetadataRegistry.DEFAULT_REALM_METADATA_REGISTRY
	end

	for _, record in ipairs(source :: { any }) do
		if record.realmTemplateId == realmTemplateId then
			return cloneRecord(record), nil
		end
	end

	return nil, "realm_metadata_missing"
end

function RealmMetadataRegistry.BuildRealmMetadataSnapshot(registry: any?): { RealmMetadataRecord }
	return RealmMetadataRegistry.GetAllRealmMetadataRecords(registry)
end

local function hasString(values: { string }, expected: string): boolean
	for _, value in ipairs(values) do
		if value == expected then
			return true
		end
	end
	return false
end

function RealmMetadataRegistry.SelectRealmCandidates(input: SelectionInput?, registry: any?): { RealmMetadataRecord }
	local source: any = registry
	if source == nil then
		source = RealmMetadataRegistry.DEFAULT_REALM_METADATA_REGISTRY
	end

	local selectionInput: any = input
	local minimumDensity = nil
	if selectionInput ~= nil and selectionInput.minimumTraversalDensity ~= nil then
		minimumDensity = DENSITY_RANK[selectionInput.minimumTraversalDensity]
	end

	local candidates = {}
	for _, record in ipairs(source :: { any }) do
		local include = true
		if selectionInput ~= nil then
			if
				selectionInput.requiredDistrictType ~= nil
				and not hasString(record.allowedDistrictTypes, selectionInput.requiredDistrictType)
			then
				include = false
			end
			if
				selectionInput.requiredLandmarkTag ~= nil
				and not hasString(record.landmarkTags, selectionInput.requiredLandmarkTag)
			then
				include = false
			end
			if minimumDensity ~= nil and DENSITY_RANK[record.traversalDensity] < minimumDensity then
				include = false
			end
			if
				selectionInput.requiresAlternativeRoutes == true
				and record.accessibilityProfile.requiresAlternativeRoutes ~= true
			then
				include = false
			end
		end

		if include then
			table.insert(candidates, cloneRecord(record))
		end
	end

	table.sort(candidates, function(a: RealmMetadataRecord, b: RealmMetadataRecord)
		return a.realmTemplateId < b.realmTemplateId
	end)
	return candidates
end

return RealmMetadataRegistry
