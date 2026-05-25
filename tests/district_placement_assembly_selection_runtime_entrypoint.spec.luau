--!strict

local DistrictPlacementConfig = require("../src/ReplicatedStorage/Shared/Config/DistrictPlacementConfig")
local RealmChunkAssemblySchema = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema")
local RealmAssemblyPrototypeFixture =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture")
local RealmMetadataRegistry = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmMetadataRegistry")
local RealmThemeFamilySchema = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmThemeFamilySchema")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function run()
	do
		assertTrue(
			type(DistrictPlacementConfig.DefaultRealmTemplateId) == "string"
				and DistrictPlacementConfig.DefaultRealmTemplateId ~= "",
			"config exposes non-empty default realm template"
		)
	end

	do
		local record, reason =
			RealmMetadataRegistry.GetRealmMetadataRecord(DistrictPlacementConfig.DefaultRealmTemplateId)
		assertEqual(reason, nil, "default realm template metadata lookup reason")
		assertTrue(record ~= nil, "default realm template metadata exists")

		local themeRecord, themeReason = RealmThemeFamilySchema.GetThemeFamilyRecord(record and record.themeId or nil)
		assertEqual(themeReason, nil, "default realm template theme family lookup reason")
		assertTrue(themeRecord ~= nil, "default realm template theme family exists")
	end

	do
		local assemblyInput, reason =
			RealmAssemblyPrototypeFixture.GetAssemblyInputForTemplate(DistrictPlacementConfig.DefaultRealmTemplateId)
		assertEqual(reason, nil, "assembly input selection by template reason")
		assertTrue(assemblyInput ~= nil, "assembly input selection by template returns input")

		local defaultRecord =
			RealmMetadataRegistry.GetRealmMetadataRecord(DistrictPlacementConfig.DefaultRealmTemplateId)
		local expectedThemeTag = "ThemeFamily:" .. ((defaultRecord and defaultRecord.themeId) or "")

		local startChunk = assemblyInput and assemblyInput.chunkLibrary["Chunk_Start"] or nil
		assertTrue(startChunk ~= nil, "selected input includes start chunk")
		assertTrue(startChunk ~= nil and #startChunk.tags >= 3, "metadata tag overlay adds realm template tags")
		assertTrue(
			startChunk ~= nil and table.find(startChunk.tags, expectedThemeTag) ~= nil,
			"theme family tag overlay is present"
		)
	end

	do
		local selectedInput, selectedTemplateId = RealmAssemblyPrototypeFixture.SelectAssemblyInputFromMetadata({
			requiredLandmarkTag = "furnace_core",
			requiresAlternativeRoutes = true,
			minimumTraversalDensity = "balanced",
		})
		assertEqual(selectedTemplateId, "FoundryBasin", "metadata selection returns deterministic template")

		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(selectedInput)
		assertTrue(output.integrity.passed == true, "selected assembly output integrity pass")
		assertTrue(#output.descriptor.spawns > 0, "selected assembly output has spawn content")
		assertTrue(#output.resolvedOccupiedSpace > 0, "selected assembly output has occupied space")
	end

	do
		local fallbackInput, fallbackSource = RealmAssemblyPrototypeFixture.SelectAssemblyInputFromMetadata({
			requiredDistrictType = "nonexistent_district_type",
			requiredLandmarkTag = "nonexistent_landmark_tag",
		})
		assertEqual(fallbackSource, "prototype_fallback", "selection falls back when no metadata candidate matches")

		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(fallbackInput)
		assertTrue(output.integrity.passed == true, "fallback assembly output integrity pass")
	end

	print("district_placement_assembly_selection_runtime_entrypoint: all checks passed")
end

run()
