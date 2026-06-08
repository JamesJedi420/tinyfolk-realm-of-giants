--!nocheck

local TraitRegistrySchema = require("../src/ReplicatedStorage/Shared/Config/TraitRegistrySchema")
local ReputationState = require("../src/ReplicatedStorage/Shared/Reputation/ReputationState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertValid(valid: boolean, reason: string?, label: string)
	if not valid then
		error(string.format("FAIL [%s]: expected valid but got reason=%s", label, tostring(reason)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertInvalid(valid: boolean, reason: string?, expectedReason: string, label: string)
	if valid then
		error(string.format("FAIL [%s]: expected invalid", label))
	end
	assertEqual(reason, expectedReason, label .. " reason")
end

local function makeTrait(overrides: any?): any
	local trait: any = {
		traitId = "tinyfolk_shadow_step",
		name = "Shadow Step",
		description = "Schema-only test trait.",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		category = TraitRegistrySchema.Categories.Movement,
		slotType = TraitRegistrySchema.SlotTypes.Active,
		tier = TraitRegistrySchema.Tiers.Common,
		unlockSource = TraitRegistrySchema.UnlockSources.Initial,
		unlockTrackId = nil,
		unlockSourceId = nil,
		trigger = TraitRegistrySchema.Triggers.RouteCrossing,
		durationType = TraitRegistrySchema.DurationTypes.Timed,
		durationSeconds = 1.5,
		cooldownSeconds = 6,
		stacking = TraitRegistrySchema.StackingPolicies.Refresh,
		visibility = TraitRegistrySchema.Visibilities.RoleSelect,
		antiAbuseTags = { TraitRegistrySchema.AntiAbuseTags.PairFarming },
		testCoverageHooks = { "trait.schema.test_hook" },
		sourceId = "tin172_schema_test",
	}

	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			trait[key] = value
		end
	end

	return trait
end

do
	local valid, reason = TraitRegistrySchema.ValidateTraitRegistry(TraitRegistrySchema.DEFAULT_TRAIT_REGISTRY)
	assertValid(valid, reason, "default registry validates")

	local snapshotA = TraitRegistrySchema.GetAllTraitRecords()
	local snapshotB = TraitRegistrySchema.GetAllTraitRecords()
	assertEqual(#snapshotA, #snapshotB, "snapshot count stable")
	assertEqual(snapshotA[1].traitId, snapshotB[1].traitId, "snapshot order stable")
	snapshotA[1].name = "tampered"
	assertTrue(snapshotB[1].name ~= "tampered", "snapshot records cloned")
end

do
	local record, reason = TraitRegistrySchema.GetTraitRecord("Tinyfolk_PostCrossingBurst")
	assertEqual(reason, nil, "known trait lookup reason")
	assertTrue(record ~= nil, "known trait exists")
	assertEqual(record and record.traitId or "", "Tinyfolk_PostCrossingBurst", "known trait id")

	local missing, missingReason = TraitRegistrySchema.GetTraitRecord("missing_trait")
	assertEqual(missing, nil, "missing trait returns nil")
	assertEqual(missingReason, "trait_missing", "missing trait reason")
end

do
	local builderRecord, reason = TraitRegistrySchema.GetTraitRecord("Giant_Builder_WorksiteEfficiency")
	assertEqual(reason, nil, "builder trait lookup reason")
	assertTrue(builderRecord ~= nil, "builder trait exists")
	assertEqual(
		builderRecord and builderRecord.modifiers and builderRecord.modifiers.stationProductionMultiplier or 0,
		1.1,
		"builder trait station production modifier"
	)
	assertEqual(
		builderRecord and builderRecord.modifiers and builderRecord.modifiers.scoreEventMultiplier or 0,
		1.05,
		"builder trait score event modifier"
	)
end

do
	local reputationRecord, reason = TraitRegistrySchema.GetTraitRecord("Tinyfolk_Loadout_EvasiveMarker")
	assertEqual(reason, nil, "reputation loadout trait lookup reason")
	assertTrue(reputationRecord ~= nil, "reputation loadout trait exists")

	local safe, safeReason = ReputationState.IsLoadoutSafeReputationTraitRecord(reputationRecord)
	assertTrue(safe, "reputation loadout trait is loadout-safe")
	assertEqual(safeReason, nil, "reputation loadout trait safety reason")
end

do
	local patterned = makeTrait({
		loadoutPattern = {
			patternType = "active_channel",
			activeChannel = "mobility",
		},
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(patterned)
	assertValid(valid, reason, "valid active-channel loadout pattern")

	local patternedRecord = TraitRegistrySchema.GetTraitRecord("Tinyfolk_PostCrossingBurst", {
		makeTrait({
			traitId = "Tinyfolk_PostCrossingBurst",
			loadoutPattern = {
				patternType = "token",
				tokenKey = "mobility_charge",
				tokenCapacity = 2,
			},
		}),
	})
	assertTrue(patternedRecord ~= nil, "patterned record exists")
	assertEqual(
		patternedRecord and patternedRecord.loadoutPattern and patternedRecord.loadoutPattern.tokenCapacity or 0,
		2,
		"patterned record clones loadout pattern"
	)
end

do
	local invalidRole = makeTrait({ role = "TinyFolk" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidRole)
	assertInvalid(valid, reason, "trait_role_invalid", "invalid role rejected")
end

do
	local invalidCategory = makeTrait({ category = "combat" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidCategory)
	assertInvalid(valid, reason, "trait_category_invalid", "invalid category rejected")
end

do
	local invalidSlot = makeTrait({ slotType = "ultimate" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidSlot)
	assertInvalid(valid, reason, "trait_slot_type_invalid", "invalid slot rejected")
end

do
	local invalidTier = makeTrait({ tier = "mythic" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidTier)
	assertInvalid(valid, reason, "trait_tier_invalid", "invalid tier rejected")
end

do
	local invalidUnlockSource = makeTrait({ unlockSource = "legacy" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidUnlockSource)
	assertInvalid(valid, reason, "trait_unlock_source_invalid", "invalid unlock source rejected")
end

do
	local invalidAccountMastery = makeTrait({
		unlockSource = TraitRegistrySchema.UnlockSources.AccountMastery,
		unlockTrackId = nil,
		unlockSourceId = nil,
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidAccountMastery)
	assertInvalid(valid, reason, "trait_unlock_track_id_invalid", "account mastery unlock track required")
end

do
	local invalidAchievement = makeTrait({
		unlockSource = TraitRegistrySchema.UnlockSources.Achievement,
		unlockTrackId = nil,
		unlockSourceId = nil,
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidAchievement)
	assertInvalid(valid, reason, "trait_unlock_source_id_invalid", "achievement unlock source id required")
end

do
	local invalidDuration = makeTrait({
		durationType = TraitRegistrySchema.DurationTypes.Timed,
		durationSeconds = 0,
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidDuration)
	assertInvalid(valid, reason, "trait_duration_seconds_invalid", "timed duration requires positive seconds")
end

do
	local invalidCooldown = makeTrait({ cooldownSeconds = -1 })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidCooldown)
	assertInvalid(valid, reason, "trait_cooldown_seconds_invalid", "invalid cooldown rejected")
end

do
	local invalidStacking = makeTrait({ stacking = "stack" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidStacking)
	assertInvalid(valid, reason, "trait_stacking_invalid", "invalid stacking rejected")
end

do
	local invalidVisibility = makeTrait({ visibility = "team_only" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidVisibility)
	assertInvalid(valid, reason, "trait_visibility_invalid", "invalid visibility rejected")
end

do
	local duplicateTags = makeTrait({
		antiAbuseTags = {
			TraitRegistrySchema.AntiAbuseTags.PairFarming,
			TraitRegistrySchema.AntiAbuseTags.PairFarming,
		},
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(duplicateTags)
	assertInvalid(valid, reason, "trait_anti_abuse_tags_duplicate", "duplicate anti-abuse tags rejected")
end

do
	local unknownTag = makeTrait({ antiAbuseTags = { "not_a_real_tag" } })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(unknownTag)
	assertInvalid(valid, reason, "trait_anti_abuse_tag_invalid", "unknown anti-abuse tag rejected")
end

do
	local duplicateRegistry = TraitRegistrySchema.GetAllTraitRecords()
	table.insert(duplicateRegistry, TraitRegistrySchema.GetAllTraitRecords()[1])
	local valid, reason = TraitRegistrySchema.ValidateTraitRegistry(duplicateRegistry)
	assertInvalid(valid, reason, "trait_id_duplicate index=6", "duplicate trait id rejected")
end

do
	local invalidSourceId = makeTrait({ sourceId = "" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidSourceId)
	assertInvalid(valid, reason, "trait_source_id_invalid", "empty source id rejected")
end

do
	local unknownField = makeTrait({ sourceLabel = "unexpected" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(unknownField)
	assertInvalid(valid, reason, "trait_record_unknown_field_invalid", "unknown record field rejected")
end

do
	local invalidModifiers = makeTrait({ modifiers = "bad" })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidModifiers)
	assertInvalid(valid, reason, "trait_modifiers_invalid", "non-table modifiers rejected")
end

do
	local invalidModifierValue = makeTrait({ modifiers = { stationProductionMultiplier = -1 } })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidModifierValue)
	assertInvalid(
		valid,
		reason,
		"trait_modifier_station_production_multiplier_invalid",
		"invalid station production multiplier rejected"
	)
end

do
	local invalidScoreModifierValue = makeTrait({ modifiers = { scoreEventMultiplier = -1 } })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidScoreModifierValue)
	assertInvalid(
		valid,
		reason,
		"trait_modifier_score_event_multiplier_invalid",
		"invalid score event multiplier rejected"
	)
end

do
	local unknownModifierField = makeTrait({ modifiers = { fearExposureMultiplier = 1.2 } })
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(unknownModifierField)
	assertInvalid(valid, reason, "trait_modifiers_unknown_field", "unknown modifier field rejected")
end

do
	local invalidPattern = makeTrait({
		loadoutPattern = {
			patternType = "active_channel",
		},
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidPattern)
	assertInvalid(valid, reason, "trait_loadout_pattern_active_channel_invalid", "missing active channel rejected")
end

do
	local invalidTokenPattern = makeTrait({
		loadoutPattern = {
			patternType = "token",
			tokenKey = "mobility_charge",
		},
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(invalidTokenPattern)
	assertInvalid(valid, reason, "trait_loadout_pattern_token_capacity_invalid", "missing token capacity rejected")
end

do
	local unknownPatternField = makeTrait({
		loadoutPattern = {
			patternType = "cooldown",
			cooldownKey = "mobility",
			budget = 2,
		},
	})
	local valid, reason = TraitRegistrySchema.ValidateTraitRecord(unknownPatternField)
	assertInvalid(valid, reason, "trait_loadout_pattern_unknown_field", "unknown loadout pattern field rejected")
end
