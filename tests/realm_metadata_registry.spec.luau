--!strict

local RealmMetadataRegistry = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmMetadataRegistry")
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
			RealmMetadataRegistry.ValidateRealmMetadataRegistry(RealmMetadataRegistry.DEFAULT_REALM_METADATA_REGISTRY)
		assertValid(valid, reason, "default registry validates")
	end

	do
		local snapshotA = RealmMetadataRegistry.GetAllRealmMetadataRecords()
		local snapshotB = RealmMetadataRegistry.GetAllRealmMetadataRecords()
		assertEqual(#snapshotA, #snapshotB, "snapshot count stable")
		assertEqual(snapshotA[1].realmTemplateId, snapshotB[1].realmTemplateId, "snapshot order stable")
		snapshotA[1].themeId = "tampered"
		assertTrue(snapshotB[1].themeId ~= "tampered", "snapshot records are immutable copies")
	end

	do
		local record, reason = RealmMetadataRegistry.GetRealmMetadataRecord("FoundryBasin")
		assertEqual(reason, nil, "foundry fetch reason")
		assertTrue(record ~= nil, "foundry record returned")
		assertEqual(record and record.themeId or "", "industrial_frontier", "foundry theme id")

		local missing, missingReason = RealmMetadataRegistry.GetRealmMetadataRecord("UnknownRealm")
		assertEqual(missing, nil, "unknown realm returns nil")
		assertEqual(missingReason, "realm_metadata_missing", "unknown realm reason")
	end

	do
		local invalidRecord = RealmMetadataRegistry.GetAllRealmMetadataRecords()[1] :: any
		invalidRecord.accessibilityProfile.requiresAlternativeRoutes = nil :: any
		local valid, reason = RealmMetadataRegistry.ValidateRealmMetadataRecord(invalidRecord)
		assertInvalid(valid, reason, "accessibility_profile_invalid", "accessibility profile validation")
	end

	do
		local duplicateRegistry = RealmMetadataRegistry.GetAllRealmMetadataRecords()
		table.insert(duplicateRegistry, RealmMetadataRegistry.GetAllRealmMetadataRecords()[1])
		local valid, reason = RealmMetadataRegistry.ValidateRealmMetadataRegistry(duplicateRegistry)
		assertInvalid(valid, reason, "realm_template_id_duplicate index=3", "duplicate template ids")
	end

	do
		local invalidThemeMetadata = RealmMetadataRegistry.GetAllRealmMetadataRecords()
		invalidThemeMetadata[1].themeId = "unknown_theme"
		local valid, reason = RealmMetadataRegistry.ValidateRealmMetadataRegistry(invalidThemeMetadata)
		assertInvalid(valid, reason, "theme_family_missing index=1", "missing theme family rejected")
	end

	do
		local invalidPaletteMetadata = RealmMetadataRegistry.GetAllRealmMetadataRecords()
		invalidPaletteMetadata[1].assetPaletteId = "palette_invalid"
		local valid, reason = RealmMetadataRegistry.ValidateRealmMetadataRegistry(invalidPaletteMetadata)
		assertInvalid(valid, reason, "theme_family_asset_palette_invalid index=1", "invalid palette rejected")
	end

	do
		local invalidThemeRegistry = RealmThemeFamilySchema.GetAllThemeFamilyRecords()
		invalidThemeRegistry[1].audioProfileIds = {}
		local valid, reason = RealmMetadataRegistry.ValidateRealmMetadataRegistry(
			RealmMetadataRegistry.GetAllRealmMetadataRecords(),
			invalidThemeRegistry
		)
		assertInvalid(valid, reason, "theme_family_audio_profiles_invalid index=1", "invalid theme registry rejected")
	end

	do
		local candidates = RealmMetadataRegistry.SelectRealmCandidates({
			requiredDistrictType = "service_tunnel",
			requiredLandmarkTag = "furnace_core",
			minimumTraversalDensity = "dense",
			requiresAlternativeRoutes = true,
		})
		assertEqual(#candidates, 1, "selection filters to foundry")
		assertEqual(candidates[1].realmTemplateId, "FoundryBasin", "selected foundry")
	end

	do
		local candidates = RealmMetadataRegistry.SelectRealmCandidates({
			requiredDistrictType = "canal",
			minimumTraversalDensity = "balanced",
		})
		assertEqual(#candidates, 1, "selection filters to sunken")
		assertEqual(candidates[1].realmTemplateId, "SunkenWard", "selected sunken")
	end

	do
		local candidates = RealmMetadataRegistry.SelectRealmCandidates({
			minimumTraversalDensity = "sparse",
		})
		assertEqual(#candidates, 2, "sparse minimum includes all")
		assertEqual(candidates[1].realmTemplateId, "FoundryBasin", "deterministic order first")
		assertEqual(candidates[2].realmTemplateId, "SunkenWard", "deterministic order second")
	end

	do
		local record = RealmMetadataRegistry.GetAllRealmMetadataRecords()[1]
		local signals = record.routeVisibilitySignals
		assertTrue(signals.sightBlocker >= 0 and signals.sightBlocker <= 1, "signal range sight blocker")
		assertTrue(
			signals.routeTransitionDensity >= 0 and signals.routeTransitionDensity <= 1,
			"signal range transition"
		)
	end

	print("PASS realm_metadata_registry")
end

run()
