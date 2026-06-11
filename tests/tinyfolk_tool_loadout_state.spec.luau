--!nocheck

local TinyfolkToolCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/TinyfolkToolCatalogSchema")
local TinyfolkToolLoadoutState = require("../src/ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolLoadoutState")

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

local function makeProfile(): any
	return {
		schemaVersion = 1,
		userId = 8101,
		roleLoadoutState = {
			selectedByRole = {
				Giant = {},
				Tinyfolk = {},
			},
		},
		tinyfolkToolLoadoutState = {
			schemaVersion = 1,
			selectedByRole = {
				Tinyfolk = {},
			},
		},
	}
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
		toolId = "locked_availability_tool",
		displayName = "Locked Availability Tool",
		description = "Unavailable test tool",
		role = "Tinyfolk",
		categories = { "escape" },
		tags = { "locked" },
		unlockSource = "starter",
		availability = "locked",
		cooldown = {
			key = "tinyfolk_locked_availability_tool",
			seconds = 10,
		},
		chargesMax = 1,
		sourceId = "tin68_locked_availability_tool",
	})
	table.insert(catalog, {
		toolId = "missing_cooldown_tool",
		displayName = "Missing Cooldown Tool",
		description = "Missing cooldown metadata test",
		role = "Tinyfolk",
		categories = { "stealth" },
		tags = { "starter_tool" },
		unlockSource = "starter",
		availability = "available",
		cooldown = nil,
		chargesMax = 1,
		sourceId = "tin68_missing_cooldown_tool",
	})
	return catalog
end

local catalog = buildCatalog()

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = {},
	}, catalog)
	assertTrue(transition.accepted, "zero tools accepted")
	assertEqual(next(transition.selectedBySlot), nil, "zero tools empty selectedBySlot")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "grappling_hook" },
	}, catalog)
	assertTrue(transition.accepted, "one tool accepted")
	assertEqual(transition.selectedBySlot.tool_1, "grappling_hook", "one tool fills tool_1")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "grappling_hook", "smoke_bomb" },
	}, catalog)
	assertTrue(transition.accepted, "two tools accepted")
	assertEqual(transition.selectedBySlot.tool_1, "grappling_hook", "two tools first slot")
	assertEqual(transition.selectedBySlot.tool_2, "smoke_bomb", "two tools second slot")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "grappling_hook", "smoke_bomb", "decoy" },
	}, catalog)
	assertFalse(transition.accepted, "three tools rejected")
	assertEqual(transition.reason, "slot_capacity_exceeded", "three tools reason")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "grappling_hook", "grappling_hook" },
	}, catalog)
	assertFalse(transition.accepted, "duplicate tool rejected")
	assertEqual(transition.reason, "duplicate_tool_selected", "duplicate tool reason")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Giant",
		selectedToolIds = { "grappling_hook" },
	}, catalog)
	assertFalse(transition.accepted, "non tinyfolk role rejected")
	assertEqual(transition.reason, "tinyfolk_role_required", "non tinyfolk role reason")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "missing_tool" },
	}, catalog)
	assertFalse(transition.accepted, "invalid tool id rejected")
	assertEqual(transition.reason, "tool_missing", "invalid tool id reason")
end

do
	local profile = makeProfile()
	profile.tinyfolkToolProgressionState = {
		schemaVersion = 1,
		unlockedToolIds = { "locked_progression_tool" },
	}
	local transition = TinyfolkToolLoadoutState.ResolveSelection(profile, {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "locked_progression_tool" },
	}, catalog)
	assertTrue(transition.accepted, "unlocked progression tool accepted")
	assertEqual(transition.selectedBySlot.tool_1, "locked_progression_tool", "unlocked progression tool fills slot")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "locked_progression_tool" },
	}, catalog)
	assertFalse(transition.accepted, "locked progression tool rejected")
	assertEqual(transition.reason, "tool_locked_or_unavailable", "locked progression reason")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "locked_availability_tool" },
	}, catalog)
	assertFalse(transition.accepted, "unavailable tool rejected")
	assertEqual(transition.reason, "tool_locked_or_unavailable", "unavailable tool reason")
end

do
	local transition = TinyfolkToolLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedToolIds = { "missing_cooldown_tool" },
	}, catalog)
	assertFalse(transition.accepted, "missing cooldown metadata rejected")
	assertEqual(transition.reason, "tool_cooldown_metadata_missing", "missing cooldown metadata reason")
end

print("tinyfolk_tool_loadout_state: all checks passed")
