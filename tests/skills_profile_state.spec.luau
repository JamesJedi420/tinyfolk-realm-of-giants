--!strict

local SkillCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/SkillCatalogSchema")
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
	assertEqual(copied.schemaVersion, 1, "copy keeps schema version")
	assertEqual(#copied.unlockedSkillIds, 1, "copy keeps only valid progression ids")
	assertEqual(copied.unlockedSkillIds[1], "locked_progression_skill", "copy keeps valid progression id")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")
end

do
	local defaultCopied = SkillsProfileState.CopyProfileField(nil)
	assertEqual(defaultCopied.schemaVersion, 1, "nil profile copy defaults schema version")
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
	assertEqual(applied.profileData.skillsProfileState.schemaVersion, 1, "apply writes schema version")
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
end

print("skills_profile_state: all checks passed")
