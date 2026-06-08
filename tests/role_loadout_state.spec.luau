--!nocheck

local TraitRegistrySchema = require("../src/ReplicatedStorage/Shared/Config/TraitRegistrySchema")
local RoleLoadoutState = require("../src/ReplicatedStorage/Shared/RoleLoadout/RoleLoadoutState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeProfile(): any
	return {
		schemaVersion = 1,
		userId = 7001,
		reputationState = {
			schemaVersion = 1,
			byTrackId = {},
			recentOutcomeAtByKey = {},
			unlockedCosmeticIds = {},
			unlockedLoadoutTraitIds = {},
		},
		giantTraitState = {
			unlockedTraitIds = { "Giant_Loadout_ControlPulse" },
		},
		roleLoadoutState = {
			selectedByRole = {
				Giant = {},
				Tinyfolk = {},
			},
		},
	}
end

local function makeTrait(overrides: any?): any
	local trait = {
		traitId = "Trait_Default",
		name = "Default Trait",
		description = "Test trait",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		category = TraitRegistrySchema.Categories.Loadout,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
		tier = TraitRegistrySchema.Tiers.Starter,
		unlockSource = TraitRegistrySchema.UnlockSources.Initial,
		unlockOwner = nil,
		unlockTrackId = nil,
		unlockSourceId = nil,
		trigger = TraitRegistrySchema.Triggers.Passive,
		durationType = TraitRegistrySchema.DurationTypes.Persistent,
		durationSeconds = nil,
		cooldownSeconds = 0,
		sharedCooldownKey = nil,
		stacking = TraitRegistrySchema.StackingPolicies.None,
		visibility = TraitRegistrySchema.Visibilities.LoadoutOnly,
		antiAbuseTags = { TraitRegistrySchema.AntiAbuseTags.DuplicateTraitGuard },
		testCoverageHooks = { "role.loadout.test" },
		sourceId = "tin171_role_loadout_test",
		modifiers = nil,
		loadoutPattern = nil,
	}

	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			trait[key] = value
		end
	end

	return trait
end

local registry = {
	makeTrait({
		traitId = "Tinyfolk_Loadout_ScoutStride",
		name = "Scout Stride",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_RescueLink",
		name = "Rescue Link",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		category = TraitRegistrySchema.Categories.Social,
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_TunnelDash",
		name = "Tunnel Dash",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Active,
		loadoutPattern = {
			patternType = "active_channel",
			activeChannel = "mobility",
		},
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_EvasiveDrop",
		name = "Evasive Drop",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		category = TraitRegistrySchema.Categories.Utility,
		loadoutPattern = {
			patternType = "active_channel",
			activeChannel = "mobility",
		},
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_QuietStep",
		name = "Quiet Step",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
		category = TraitRegistrySchema.Categories.Movement,
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_RootSlip",
		name = "Root Slip",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
		category = TraitRegistrySchema.Categories.Traversal,
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_EvasiveMarker",
		name = "Evasive Marker",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		unlockSource = TraitRegistrySchema.UnlockSources.Reputation,
		unlockOwner = TraitRegistrySchema.UnlockOwners and TraitRegistrySchema.UnlockOwners.PlayerProfile
			or "playerProfile",
		unlockTrackId = "Escapist",
		unlockSourceId = nil,
		tier = TraitRegistrySchema.Tiers.Common,
		antiAbuseTags = {
			TraitRegistrySchema.AntiAbuseTags.DuplicateTraitGuard,
			TraitRegistrySchema.AntiAbuseTags.RoleSafeUse,
			TraitRegistrySchema.AntiAbuseTags.ReputationGateGuard,
		},
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_UnsafeRenown",
		name = "Unsafe Renown",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		unlockSource = TraitRegistrySchema.UnlockSources.Reputation,
		unlockOwner = TraitRegistrySchema.UnlockOwners and TraitRegistrySchema.UnlockOwners.PlayerProfile
			or "playerProfile",
		unlockTrackId = "Escapist",
		unlockSourceId = nil,
		tier = TraitRegistrySchema.Tiers.Common,
		antiAbuseTags = {
			TraitRegistrySchema.AntiAbuseTags.DuplicateTraitGuard,
			TraitRegistrySchema.AntiAbuseTags.ReputationGateGuard,
		},
		modifiers = {
			scoreEventMultiplier = 1.1,
		},
	}),
	makeTrait({
		traitId = "Giant_Loadout_StoneHands",
		name = "Stone Hands",
		role = TraitRegistrySchema.Roles.Giant,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
		category = TraitRegistrySchema.Categories.Resource,
	}),
	makeTrait({
		traitId = "Giant_Loadout_ControlPulse",
		name = "Control Pulse",
		role = TraitRegistrySchema.Roles.Giant,
		slotType = TraitRegistrySchema.SlotTypes.Active,
		tier = TraitRegistrySchema.Tiers.Common,
		unlockSource = TraitRegistrySchema.UnlockSources.RoleMastery,
		unlockOwner = TraitRegistrySchema.UnlockOwners and TraitRegistrySchema.UnlockOwners.PlayerProfile
			or "playerProfile",
		unlockTrackId = "giant_role_mastery_track",
		unlockSourceId = "giant_role_mastery_1",
	}),
	makeTrait({
		traitId = "Shared_Loadout_CampSignal",
		name = "Camp Signal",
		role = TraitRegistrySchema.Roles.Shared,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		category = TraitRegistrySchema.Categories.Social,
	}),
}

local validRegistry, registryReason = TraitRegistrySchema.ValidateTraitRegistry(registry)
assertTrue(validRegistry, "role loadout registry validates: " .. tostring(registryReason))

do
	local transition = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Tinyfolk_Loadout_ScoutStride", "Tinyfolk_Loadout_RescueLink" },
	}, registry)
	assertTrue(transition.accepted, "tinyfolk loadout accepted")
	assertEqual(transition.reason, "accepted", "tinyfolk loadout reason")
	assertEqual(transition.selectedBySlot.passive_1, "Tinyfolk_Loadout_ScoutStride", "tinyfolk passive slot assigned")
	assertEqual(transition.selectedBySlot.support, "Tinyfolk_Loadout_RescueLink", "tinyfolk support slot assigned")
end

do
	local transition = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Giant",
		selectedTraitIds = { "Giant_Loadout_StoneHands", "Giant_Loadout_ControlPulse", "Shared_Loadout_CampSignal" },
	}, registry)
	assertTrue(transition.accepted, "giant loadout accepted")
	assertEqual(transition.selectedBySlot.passive_1, "Giant_Loadout_StoneHands", "giant passive slot assigned")
	assertEqual(transition.selectedBySlot.active, "Giant_Loadout_ControlPulse", "giant active slot assigned")
	assertEqual(transition.selectedBySlot.support, "Shared_Loadout_CampSignal", "shared support slot assigned")
end

do
	local invalid = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Missing_Trait" },
	}, registry)
	assertFalse(invalid.accepted, "unknown trait rejected")
	assertEqual(invalid.reason, "trait_missing", "unknown trait reason")
end

do
	local wrongRole = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Giant_Loadout_StoneHands" },
	}, registry)
	assertFalse(wrongRole.accepted, "wrong role trait rejected")
	assertEqual(wrongRole.reason, "trait_not_for_role", "wrong role trait reason")
end

do
	local locked = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Giant_Loadout_ControlPulse" },
	}, registry)
	assertFalse(locked.accepted, "progression trait rejected when not unlocked")
	assertEqual(locked.reason, "trait_not_for_role", "progression wrong role wins before unlock")
end

do
	local lockedGiant = RoleLoadoutState.ResolveSelection({
		schemaVersion = 1,
		userId = 7001,
		giantTraitState = { unlockedTraitIds = {} },
		roleLoadoutState = { selectedByRole = { Giant = {}, Tinyfolk = {} } },
	}, {
		requesterRole = "Giant",
		selectedTraitIds = { "Giant_Loadout_ControlPulse" },
	}, registry)
	assertFalse(lockedGiant.accepted, "giant progression trait rejected when not unlocked")
	assertEqual(lockedGiant.reason, "trait_not_unlocked", "giant progression unlock reason")
end

do
	local duplicate = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Tinyfolk_Loadout_ScoutStride", "Tinyfolk_Loadout_ScoutStride" },
	}, registry)
	assertFalse(duplicate.accepted, "duplicate trait rejected")
	assertEqual(duplicate.reason, "duplicate_trait_selected", "duplicate trait reason")
end

do
	local overCap = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedTraitIds = {
			"Tinyfolk_Loadout_ScoutStride",
			"Tinyfolk_Loadout_QuietStep",
			"Tinyfolk_Loadout_RootSlip",
		},
	}, registry)
	assertFalse(overCap.accepted, "passive slot capacity rejected")
	assertEqual(overCap.reason, "slot_capacity_exceeded", "passive slot capacity reason")
end

do
	local activeChannelConflict = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Tinyfolk_Loadout_TunnelDash", "Tinyfolk_Loadout_EvasiveDrop" },
	}, registry)
	assertFalse(activeChannelConflict.accepted, "active channel conflict rejected")
	assertEqual(activeChannelConflict.reason, "active_channel_conflict", "active channel conflict reason")
end

do
	local invalidRole = RoleLoadoutState.ResolveSelection(makeProfile(), {
		requesterRole = "Builder",
		selectedTraitIds = {},
	}, registry)
	assertFalse(invalidRole.accepted, "invalid role rejected")
	assertEqual(invalidRole.reason, "invalid_role", "invalid role reason")
end

do
	local defaultLoadout = RoleLoadoutState.BuildDefaultLoadout(makeProfile(), "Tinyfolk", registry)
	assertEqual(defaultLoadout.passive_1, "Tinyfolk_Loadout_QuietStep", "default tinyfolk passive assignment")
	assertEqual(defaultLoadout.active, "Tinyfolk_Loadout_TunnelDash", "default tinyfolk active assignment")
	assertEqual(defaultLoadout.support, "Tinyfolk_Loadout_RescueLink", "default tinyfolk support assignment")
end

do
	local profile = makeProfile()
	profile.reputationState.unlockedLoadoutTraitIds = { "Tinyfolk_Loadout_EvasiveMarker" }
	local transition = RoleLoadoutState.ResolveSelection(profile, {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Tinyfolk_Loadout_EvasiveMarker" },
	}, registry)
	assertTrue(transition.accepted, "reputation loadout-safe trait accepted")
	assertEqual(transition.selectedBySlot.support, "Tinyfolk_Loadout_EvasiveMarker", "reputation support slot assigned")
end

do
	local profile = makeProfile()
	profile.reputationState.unlockedLoadoutTraitIds = { "Tinyfolk_Loadout_UnsafeRenown" }
	local transition = RoleLoadoutState.ResolveSelection(profile, {
		requesterRole = "Tinyfolk",
		selectedTraitIds = { "Tinyfolk_Loadout_UnsafeRenown" },
	}, registry)
	assertFalse(transition.accepted, "unsafe reputation trait rejected")
	assertEqual(transition.reason, "trait_not_unlocked", "unsafe reputation trait reason")
end

print("role_loadout_state: all checks passed")
