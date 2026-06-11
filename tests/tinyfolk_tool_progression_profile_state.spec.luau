--!strict

local TinyfolkToolCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/TinyfolkToolCatalogSchema")
local TinyfolkToolProgressionProfileState =
	require("../src/ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolProgressionProfileState")

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
	local catalog = TinyfolkToolCatalogSchema.GetAllToolRecords()
	table.insert(catalog, {
		toolId = "locked_progression_tool",
		displayName = "Locked Progression Tool",
		description = "Locked test tool",
		role = "Tinyfolk",
		categories = { "sabotage" },
		tags = { "locked" },
		unlockSource = "progression",
		availability = "available",
		cooldown = {
			key = "tinyfolk_locked_progression_tool",
			seconds = 20,
		},
		chargesMax = 1,
		sourceId = "tin68_locked_progression_tool",
	})
	table.insert(catalog, {
		toolId = "unavailable_progression_tool",
		displayName = "Unavailable Progression Tool",
		description = "Unavailable progression test tool",
		role = "Tinyfolk",
		categories = { "escape" },
		tags = { "locked" },
		unlockSource = "progression",
		availability = "locked",
		cooldown = {
			key = "tinyfolk_unavailable_progression_tool",
			seconds = 10,
		},
		chargesMax = 1,
		sourceId = "tin68_unavailable_progression_tool",
	})
	return catalog
end

local catalog = buildCatalog()

do
	assertFalse(TinyfolkToolProgressionProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(TinyfolkToolProgressionProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		TinyfolkToolProgressionProfileState.HasPersistedState({
			tinyfolkToolProgressionState = {
				unlockedToolIds = { "locked_progression_tool" },
			},
		}),
		"missing schema version not persisted"
	)
end

do
	local profileData = {
		tinyfolkToolProgressionState = {
			schemaVersion = 1,
			unlockedToolIds = {
				"locked_progression_tool",
				"grappling_hook",
				"locked_progression_tool",
				"unavailable_progression_tool",
				"missing_tool",
				"",
			},
			invalidField = "ignored",
		},
	}
	assertTrue(TinyfolkToolProgressionProfileState.HasPersistedState(profileData), "schema version marks persisted")
	local unlockedIds = TinyfolkToolProgressionProfileState.GetUnlockedToolIds(profileData, catalog)
	assertEqual(#unlockedIds, 1, "normalize keeps one valid progression tool")
	assertEqual(unlockedIds[1], "locked_progression_tool", "normalize keeps valid progression tool")
	assertTrue(
		TinyfolkToolProgressionProfileState.GetUnlockedToolSet(profileData, catalog).locked_progression_tool == true,
		"normalize builds unlocked set"
	)
end

do
	local copied = TinyfolkToolProgressionProfileState.CopyProfileField({
		tinyfolkToolProgressionState = {
			schemaVersion = 1,
			unlockedToolIds = {
				"locked_progression_tool",
				"grappling_hook",
				"invalid",
			},
			invalidField = "ignored",
		},
	}, catalog)
	assertEqual(copied.schemaVersion, 1, "copy keeps schema version")
	assertEqual(#copied.unlockedToolIds, 1, "copy keeps only valid progression ids")
	assertEqual(copied.unlockedToolIds[1], "locked_progression_tool", "copy keeps valid progression id")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")
end

do
	local defaultCopied = TinyfolkToolProgressionProfileState.CopyProfileField(nil)
	assertEqual(defaultCopied.schemaVersion, 1, "nil profile copy defaults schema version")
	assertTrue(type(defaultCopied.unlockedToolIds) == "table", "nil profile copy defaults unlocked ids")
	assertEqual(next(defaultCopied.unlockedToolIds), nil, "nil profile copy defaults empty unlock list")
end

do
	local applied = TinyfolkToolProgressionProfileState.ApplyUnlockedToolIds({}, {
		"locked_progression_tool",
		"grappling_hook",
		"locked_progression_tool",
	}, catalog)
	assertTrue(applied.accepted, "apply accepted")
	assertEqual(applied.profileData.tinyfolkToolProgressionState.schemaVersion, 1, "apply writes schema version")
	assertEqual(#applied.profileData.tinyfolkToolProgressionState.unlockedToolIds, 1, "apply writes filtered ids")
	assertEqual(
		applied.profileData.tinyfolkToolProgressionState.unlockedToolIds[1],
		"locked_progression_tool",
		"apply writes valid progression id"
	)

	local rejected = TinyfolkToolProgressionProfileState.ApplyUnlockedToolIds({}, "not-a-table", catalog)
	assertFalse(rejected.accepted, "invalid apply rejected")
	assertEqual(rejected.reason, "unlocked_tool_ids_invalid", "invalid apply reason")
end

do
	local firstUnlock = TinyfolkToolProgressionProfileState.ResolveUnlock({}, "locked_progression_tool", catalog)
	assertTrue(firstUnlock.accepted, "resolve unlock accepted")
	assertEqual(
		firstUnlock.profileData.tinyfolkToolProgressionState.unlockedToolIds[1],
		"locked_progression_tool",
		"resolve unlock writes tool id"
	)

	local duplicateUnlock =
		TinyfolkToolProgressionProfileState.ResolveUnlock(firstUnlock.profileData, "locked_progression_tool", catalog)
	assertFalse(duplicateUnlock.accepted, "duplicate unlock rejected")
	assertEqual(duplicateUnlock.reason, "tool_already_unlocked", "duplicate unlock reason")

	local starterUnlock = TinyfolkToolProgressionProfileState.ResolveUnlock({}, "grappling_hook", catalog)
	assertFalse(starterUnlock.accepted, "starter tool unlock rejected")
	assertEqual(starterUnlock.reason, "tool_not_progression_unlock", "starter tool unlock reason")
end

print("tinyfolk_tool_progression_profile_state: all checks passed")
