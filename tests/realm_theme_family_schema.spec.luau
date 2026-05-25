--!strict

local RealmThemeFamilySchema = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmThemeFamilySchema")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertValid(valid: boolean, reason: string?, label: string)
	if not valid then
		error(string.format("expected valid [%s] but got reason=%s", label, tostring(reason)))
	end
end

local function assertInvalid(valid: boolean, reason: string?, expectedReason: string, label: string)
	if valid then
		error(string.format("expected invalid [%s]", label))
	end
	assertEqual(reason, expectedReason, label .. " reason")
end

local function run()
	do
		local valid, reason =
			RealmThemeFamilySchema.ValidateThemeFamilyRegistry(RealmThemeFamilySchema.DEFAULT_THEME_FAMILY_REGISTRY)
		assertValid(valid, reason, "default theme family registry validates")
	end

	do
		local snapshotA = RealmThemeFamilySchema.GetAllThemeFamilyRecords()
		local snapshotB = RealmThemeFamilySchema.GetAllThemeFamilyRecords()
		assertEqual(#snapshotA, #snapshotB, "snapshot count stable")
		assertEqual(snapshotA[1].themeId, snapshotB[1].themeId, "snapshot order stable")
		snapshotA[1].themeId = "tampered"
		assertTrue(snapshotB[1].themeId ~= "tampered", "theme snapshot records are immutable copies")
	end

	do
		local record, reason = RealmThemeFamilySchema.GetThemeFamilyRecord("industrial_frontier")
		assertEqual(reason, nil, "industrial theme lookup reason")
		assertTrue(record ~= nil, "industrial theme record exists")
		assertEqual(record and record.themeId or "", "industrial_frontier", "industrial theme id")

		local missing, missingReason = RealmThemeFamilySchema.GetThemeFamilyRecord("unknown_theme")
		assertEqual(missing, nil, "unknown theme returns nil")
		assertEqual(missingReason, "theme_family_missing", "unknown theme reason")
	end

	do
		local duplicateRegistry = RealmThemeFamilySchema.GetAllThemeFamilyRecords()
		table.insert(duplicateRegistry, RealmThemeFamilySchema.GetAllThemeFamilyRecords()[1])
		local valid, reason = RealmThemeFamilySchema.ValidateThemeFamilyRegistry(duplicateRegistry)
		assertInvalid(valid, reason, "theme_family_id_duplicate index=3", "duplicate theme id rejection")
	end

	do
		local themeLinkInput = {
			themeId = "industrial_frontier",
			assetPaletteId = "palette_iron_brick",
			lightingProfileId = "lighting_smoky_dawn",
			audioProfileId = "audio_mechanical_wind",
			allowedDistrictTypes = { "workyard", "warehouse" },
			landmarkTags = { "furnace_core", "smoke_stack" },
			districtTags = { "high_wall" },
			variantRules = { "night_shift" },
			accessibilityProfile = {
				readabilityProfile = "high",
				colorContrastMode = "high",
				requiresAlternativeRoutes = true,
			},
		}
		local valid, reason = RealmThemeFamilySchema.ValidateThemeLink(themeLinkInput)
		assertValid(valid, reason, "theme link validates")
	end

	do
		local invalidLinkInput = {
			themeId = "industrial_frontier",
			assetPaletteId = "palette_invalid",
			lightingProfileId = "lighting_smoky_dawn",
			audioProfileId = "audio_mechanical_wind",
			allowedDistrictTypes = { "workyard" },
			landmarkTags = { "furnace_core" },
			districtTags = { "high_wall" },
			variantRules = { "night_shift" },
			accessibilityProfile = {
				readabilityProfile = "high",
				colorContrastMode = "high",
				requiresAlternativeRoutes = true,
			},
		}
		local valid, reason = RealmThemeFamilySchema.ValidateThemeLink(invalidLinkInput)
		assertInvalid(valid, reason, "theme_family_asset_palette_invalid", "invalid palette link rejected")
	end

	do
		local malformedLinkInput = {
			themeId = "industrial_frontier",
			assetPaletteId = "palette_iron_brick",
			lightingProfileId = "lighting_smoky_dawn",
			audioProfileId = "audio_mechanical_wind",
			allowedDistrictTypes = nil,
			landmarkTags = { "furnace_core" },
			districtTags = { "high_wall" },
			variantRules = { "night_shift" },
			accessibilityProfile = {
				readabilityProfile = "high",
				colorContrastMode = "high",
				requiresAlternativeRoutes = true,
			},
		}
		local valid, reason = RealmThemeFamilySchema.ValidateThemeLink(malformedLinkInput)
		assertInvalid(valid, reason, "theme_family_allowed_district_types_invalid", "malformed theme link rejected")
	end

	print("PASS realm_theme_family_schema")
end

run()
