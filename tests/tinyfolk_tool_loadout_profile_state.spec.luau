--!strict

local TinyfolkToolLoadoutProfileState =
	require("../src/ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolLoadoutProfileState")

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

do
	assertFalse(TinyfolkToolLoadoutProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(TinyfolkToolLoadoutProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		TinyfolkToolLoadoutProfileState.HasPersistedState({
			tinyfolkToolLoadoutState = {
				selectedByRole = {
					Tinyfolk = { tool_1 = "grappling_hook" },
				},
			},
		}),
		"missing schema version not persisted"
	)
end

do
	local profileData = {
		tinyfolkToolLoadoutState = {
			schemaVersion = 1,
			selectedByRole = {
				Tinyfolk = {
					tool_1 = "grappling_hook",
					tool_2 = "smoke_bomb",
					invalid_slot = "decoy",
					tool_3 = "",
				},
			},
			invalidField = "ignored",
		},
	}
	assertTrue(TinyfolkToolLoadoutProfileState.HasPersistedState(profileData), "schema version marks persisted")
	local selected = TinyfolkToolLoadoutProfileState.GetSelectedLoadout(profileData, "Tinyfolk")
	assertEqual(selected.tool_1, "grappling_hook", "canonical first slot preserved")
	assertEqual(selected.tool_2, "smoke_bomb", "canonical second slot preserved")
	assertEqual(selected.invalid_slot, nil, "unknown slot filtered")
	assertEqual(selected.tool_3, nil, "empty tool id filtered")
end

do
	local copied = TinyfolkToolLoadoutProfileState.CopyProfileField({
		tinyfolkToolLoadoutState = {
			schemaVersion = 1,
			selectedByRole = {
				Tinyfolk = {
					tool_1 = "grappling_hook",
					invalid_slot = "decoy",
				},
			},
			invalidField = "ignored",
		},
	})
	assertEqual(copied.schemaVersion, 1, "copy keeps schema version")
	assertEqual(copied.selectedByRole.Tinyfolk.tool_1, "grappling_hook", "copy keeps valid slot")
	assertEqual(copied.selectedByRole.Tinyfolk.invalid_slot, nil, "copy drops invalid slot")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")
end

do
	local defaultCopied = TinyfolkToolLoadoutProfileState.CopyProfileField(nil)
	assertEqual(defaultCopied.schemaVersion, 1, "nil profile copy defaults schema version")
	assertTrue(type(defaultCopied.selectedByRole.Tinyfolk) == "table", "nil profile copy defaults tinyfolk slots")
	assertEqual(next(defaultCopied.selectedByRole.Tinyfolk), nil, "nil profile copy defaults empty selection")
end

do
	local applied = TinyfolkToolLoadoutProfileState.ApplySelectedLoadout({}, "Tinyfolk", {
		tool_1 = "grappling_hook",
		tool_2 = "smoke_bomb",
		invalid_slot = "decoy",
	})
	assertTrue(applied.accepted, "apply accepted")
	assertEqual(applied.profileData.tinyfolkToolLoadoutState.schemaVersion, 1, "apply writes schema version")
	assertEqual(
		applied.profileData.tinyfolkToolLoadoutState.selectedByRole.Tinyfolk.tool_1,
		"grappling_hook",
		"apply writes first slot"
	)
	assertEqual(
		applied.profileData.tinyfolkToolLoadoutState.selectedByRole.Tinyfolk.tool_2,
		"smoke_bomb",
		"apply writes second slot"
	)
	assertEqual(
		applied.profileData.tinyfolkToolLoadoutState.selectedByRole.Tinyfolk.invalid_slot,
		nil,
		"apply drops invalid slot"
	)

	local rejectedRole = TinyfolkToolLoadoutProfileState.ApplySelectedLoadout(
		{},
		"Giant",
		{ tool_1 = "grappling_hook" }
	)
	assertFalse(rejectedRole.accepted, "non-tinyfolk role rejected")
	assertEqual(rejectedRole.reason, "tinyfolk_role_required", "non-tinyfolk role reason")

	local rejectedSelection = TinyfolkToolLoadoutProfileState.ApplySelectedLoadout({}, "Tinyfolk", "not-a-table")
	assertFalse(rejectedSelection.accepted, "invalid selection rejected")
	assertEqual(rejectedSelection.reason, "tool_loadout_selection_invalid", "invalid selection reason")
end

print("tinyfolk_tool_loadout_profile_state: all checks passed")
