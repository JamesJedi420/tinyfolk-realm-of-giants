--!strict

local SkillCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/SkillCatalogSchema")
local SkillProgressionConfig = require("../src/ReplicatedStorage/Shared/Config/SkillProgressionConfig")
local SkillXpAwardPolicy = require("../src/ReplicatedStorage/Shared/Skills/SkillXpAwardPolicy")
local SkillsProfileState = require("../src/ReplicatedStorage/Shared/Skills/SkillsProfileState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function buildCatalog(): any
	local catalog = SkillCatalogSchema.GetAllSkillRecords()
	table.insert(catalog, {
		skillId = "starter_skill",
		displayName = "Starter Skill",
		unlockSource = "starter",
		availability = "available",
		sourceId = "tin67_starter_skill",
	})
	table.insert(catalog, {
		skillId = "locked_progression_skill",
		displayName = "Locked Progression Skill",
		unlockSource = "progression",
		availability = "available",
		sourceId = "tin67_locked_progression_skill",
	})
	table.insert(catalog, {
		skillId = "unavailable_progression_skill",
		displayName = "Unavailable Progression Skill",
		unlockSource = "progression",
		availability = "locked",
		sourceId = "tin67_unavailable_progression_skill",
	})
	return catalog
end

local catalog = buildCatalog()

do
	assertFalse(SkillsProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(SkillsProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		SkillsProfileState.HasPersistedState({
			skillsProfileState = {
				unlockedSkillIds = { "locked_progression_skill" },
			},
		}),
		"missing schema version not persisted"
	)
end

do
	local profileData = {
		skillsProfileState = {
			schemaVersion = 1,
			unlockedSkillIds = {
				"locked_progression_skill",
				"starter_skill",
				"locked_progression_skill",
				"unavailable_progression_skill",
				"missing_skill",
				"",
			},
			invalidField = "ignored",
		},
	}
	assertTrue(SkillsProfileState.HasPersistedState(profileData), "schema version marks persisted")
	local unlockedIds = SkillsProfileState.GetUnlockedSkillIds(profileData, catalog)
	assertEqual(#unlockedIds, 1, "normalize keeps one valid progression skill")
	assertEqual(unlockedIds[1], "locked_progression_skill", "normalize keeps valid progression skill")
end

do
	local copied = SkillsProfileState.CopyProfileField({
		skillsProfileState = {
			schemaVersion = 1,
			unlockedSkillIds = {
				"locked_progression_skill",
				"starter_skill",
				"invalid",
			},
			invalidField = "ignored",
		},
	}, catalog)
	assertEqual(copied.schemaVersion, 2, "copy keeps schema version")
	assertEqual(#copied.unlockedSkillIds, 1, "copy keeps only valid progression ids")
	assertEqual(copied.unlockedSkillIds[1], "locked_progression_skill", "copy keeps valid progression id")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")
end

do
	local defaultCopied = SkillsProfileState.CopyProfileField(nil)
	assertEqual(defaultCopied.schemaVersion, 2, "nil profile copy defaults schema version")
	assertTrue(type(defaultCopied.unlockedSkillIds) == "table", "nil profile copy defaults unlocked ids")
	assertEqual(next(defaultCopied.unlockedSkillIds), nil, "nil profile copy defaults empty unlock list")
end

do
	local applied = SkillsProfileState.ApplyUnlockedSkillIds({}, {
		"locked_progression_skill",
		"starter_skill",
		"locked_progression_skill",
	}, catalog)
	assertTrue(applied.accepted, "apply accepted")
	assertEqual(applied.profileData.skillsProfileState.schemaVersion, 2, "apply writes schema version")
	assertEqual(#applied.profileData.skillsProfileState.unlockedSkillIds, 1, "apply writes filtered ids")
	assertEqual(
		applied.profileData.skillsProfileState.unlockedSkillIds[1],
		"locked_progression_skill",
		"apply writes valid progression id"
	)

	local rejected = SkillsProfileState.ApplyUnlockedSkillIds({}, "not-a-table", catalog)
	assertFalse(rejected.accepted, "invalid apply rejected")
	assertEqual(rejected.reason, "unlocked_skill_ids_invalid", "invalid apply reason")
end

do
	local firstUnlock = SkillsProfileState.ResolveUnlock({}, "locked_progression_skill", catalog)
	assertTrue(firstUnlock.accepted, "resolve unlock accepted")
	assertEqual(
		firstUnlock.profileData.skillsProfileState.unlockedSkillIds[1],
		"locked_progression_skill",
		"resolve unlock writes skill id"
	)

	local duplicateUnlock =
		SkillsProfileState.ResolveUnlock(firstUnlock.profileData, "locked_progression_skill", catalog)
	assertFalse(duplicateUnlock.accepted, "duplicate unlock rejected")
	assertEqual(duplicateUnlock.reason, "skill_already_unlocked", "duplicate unlock reason")

	local starterUnlock = SkillsProfileState.ResolveUnlock({}, "starter_skill", catalog)
	assertFalse(starterUnlock.accepted, "starter skill unlock rejected")
	assertEqual(starterUnlock.reason, "skill_not_progression_unlock", "starter skill unlock reason")

	local seededProgress = firstUnlock.profileData.skillsProfileState.skillProgressById.locked_progression_skill
	assertTrue(type(seededProgress) == "table", "unlock seeds progress entry")
	assertEqual(seededProgress.level, 1, "unlock seeds level one")
	assertEqual(seededProgress.xp, 0, "unlock seeds zero xp")
	assertTrue(seededProgress.cooldownEndsAt == nil, "unlock seeds nil cooldown")
end

do
	local migrated = SkillsProfileState.CopyProfileField({
		skillsProfileState = {
			schemaVersion = 1,
			unlockedSkillIds = { "locked_progression_skill" },
			skillProgressById = {
				locked_progression_skill = {
					level = 99,
					xp = 99999,
					cooldownEndsAt = -1,
				},
				starter_skill = {
					level = 2,
					xp = 50,
				},
			},
			invalidField = "ignored",
		},
	}, catalog)
	assertEqual(migrated.schemaVersion, 2, "v1 profile migrates to schema version two")
	assertEqual(#migrated.unlockedSkillIds, 1, "v1 migration keeps valid unlock ids")
	local progress = migrated.skillProgressById.locked_progression_skill
	assertTrue(type(progress) == "table", "v1 migration keeps unlocked progress")
	assertEqual(progress.level, 5, "v1 migration clamps xp-driven level to max")
	assertEqual(progress.xp, 1000, "v1 migration clamps xp to max threshold")
	assertTrue(progress.cooldownEndsAt == nil, "v1 migration drops invalid cooldown")
	assertTrue(migrated.skillProgressById.starter_skill == nil, "v1 migration drops non-unlocked progress")
	assertTrue(migrated.invalidField == nil, "v1 migration drops invalid fields")
end

do
	local unlockedProfile = SkillsProfileState.ResolveUnlock({}, "locked_progression_skill", catalog).profileData
	local awarded = SkillsProfileState.ResolveAwardXp(unlockedProfile, "locked_progression_skill", 150, catalog)
	assertTrue(awarded.accepted, "award xp accepted")
	assertEqual(awarded.progress.level, 2, "award xp resolves level two")
	assertEqual(awarded.progress.xp, 150, "award xp writes total xp")

	local lockedAward = SkillsProfileState.ResolveAwardXp({}, "locked_progression_skill", 10, catalog)
	assertFalse(lockedAward.accepted, "award xp rejected when locked")
	assertEqual(lockedAward.reason, "skill_not_unlocked", "award xp locked reason")

	local invalidAward = SkillsProfileState.ResolveAwardXp(unlockedProfile, "locked_progression_skill", 0, catalog)
	assertFalse(invalidAward.accepted, "zero xp rejected")
	assertEqual(invalidAward.reason, "xp_amount_invalid", "zero xp reason")
end

do
	local unlockedProfile = SkillsProfileState.ResolveUnlock({}, "locked_progression_skill", catalog).profileData
	local cooldownSet =
		SkillsProfileState.ResolveSetCooldown(unlockedProfile, "locked_progression_skill", 120.5, catalog)
	assertTrue(cooldownSet.accepted, "set cooldown accepted")
	assertEqual(cooldownSet.progress.cooldownEndsAt, 120.5, "set cooldown writes ends at")

	local cleared =
		SkillsProfileState.ResolveSetCooldown(cooldownSet.profileData, "locked_progression_skill", nil, catalog)
	assertTrue(cleared.accepted, "clear cooldown accepted")
	assertTrue(cleared.progress.cooldownEndsAt == nil, "clear cooldown writes nil")

	local invalidCooldown =
		SkillsProfileState.ResolveSetCooldown(unlockedProfile, "locked_progression_skill", -1, catalog)
	assertFalse(invalidCooldown.accepted, "invalid cooldown rejected")
	assertEqual(invalidCooldown.reason, "cooldown_ends_at_invalid", "invalid cooldown reason")
end

do
	local unlocked = SkillsProfileState.ApplyUnlockedSkillIds({}, { "locked_progression_skill" }, catalog)
	local applied = SkillsProfileState.ApplySkillProgressById(unlocked.profileData, {
		locked_progression_skill = {
			level = 3,
			xp = 300,
			cooldownEndsAt = 50,
		},
		starter_skill = {
			level = 2,
			xp = 100,
		},
	}, catalog)
	assertTrue(applied.accepted, "apply progress accepted")
	local progress = applied.profileData.skillsProfileState.skillProgressById.locked_progression_skill
	assertEqual(progress.level, 3, "apply progress keeps normalized level")
	assertEqual(progress.xp, 300, "apply progress keeps normalized xp")
	assertEqual(progress.cooldownEndsAt, 50, "apply progress keeps normalized cooldown")
	assertTrue(
		applied.profileData.skillsProfileState.skillProgressById.starter_skill == nil,
		"apply progress drops non-unlocked skill entries"
	)
end

do
	local award, reason = SkillXpAwardPolicy.ResolveXpAward(SkillProgressionConfig.OutcomeKinds.ObjectiveQteSuccess)
	assertTrue(type(award) == "table", "objective qte xp award resolves")
	if award == nil then
		error("objective qte xp award missing after resolve")
	end
	assertEqual(award.skillId, "objective_craft", "objective qte xp award skill id")
	assertEqual(award.xpAmount, 25, "objective qte xp award amount")
	assertTrue(reason == nil, "objective qte xp award has no reason")

	local missingAward, missingReason = SkillXpAwardPolicy.ResolveXpAward("missing_outcome")
	assertTrue(missingAward == nil, "missing outcome has no award")
	assertEqual(missingReason, "xp_award_unconfigured", "missing outcome reason")
end

print("skills_profile_state: all checks passed")
