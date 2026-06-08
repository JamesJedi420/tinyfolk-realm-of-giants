--!nocheck

local ReputationState = require("../src/ReplicatedStorage/Shared/Reputation/ReputationState")
local TraitRegistrySchema = require("../src/ReplicatedStorage/Shared/Config/TraitRegistrySchema")

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
		userId = 9991,
	}
end

local function makeReputationTrait(traitId: string, safe: boolean): any
	local antiAbuseTags = {
		TraitRegistrySchema.AntiAbuseTags.DuplicateTraitGuard,
		TraitRegistrySchema.AntiAbuseTags.ReputationGateGuard,
	}
	if safe then
		table.insert(antiAbuseTags, TraitRegistrySchema.AntiAbuseTags.RoleSafeUse)
	end

	return {
		traitId = traitId,
		name = traitId,
		description = "test",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		category = TraitRegistrySchema.Categories.Loadout,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		tier = TraitRegistrySchema.Tiers.Common,
		unlockSource = TraitRegistrySchema.UnlockSources.Reputation,
		unlockOwner = "playerProfile",
		unlockTrackId = "Escapist",
		unlockSourceId = nil,
		trigger = TraitRegistrySchema.Triggers.Passive,
		durationType = TraitRegistrySchema.DurationTypes.Persistent,
		durationSeconds = nil,
		cooldownSeconds = 0,
		sharedCooldownKey = nil,
		stacking = TraitRegistrySchema.StackingPolicies.None,
		visibility = TraitRegistrySchema.Visibilities.LoadoutOnly,
		antiAbuseTags = antiAbuseTags,
		testCoverageHooks = { "reputation.state.test" },
		sourceId = "tin69_reputation_state_test",
		modifiers = if safe then nil else { scoreEventMultiplier = 1.1 },
		loadoutPattern = nil,
	}
end

do
	local result = ReputationState.ApplyOutcome(makeProfile(), {
		outcomeKind = ReputationState.OutcomeKinds.EscapeSuccess,
		now = 100,
		operationId = "op-1",
		sourceKind = "escape",
		sourceId = "Route_A",
		difficulty = 2,
		lootValue = 3,
	})
	assertTrue(result.accepted, "escape outcome accepted")

	local escapistUpdate = nil
	local scoutUpdate = nil
	local thiefUpdate = nil
	for _, update in ipairs(result.trackUpdates) do
		if update.trackId == ReputationState.Tracks.Escapist then
			escapistUpdate = update
		elseif update.trackId == ReputationState.Tracks.Scout then
			scoutUpdate = update
		elseif update.trackId == ReputationState.Tracks.Thief then
			thiefUpdate = update
		end
	end
	assertTrue(escapistUpdate ~= nil and escapistUpdate.accepted, "escape grants escapist")
	assertTrue(scoutUpdate ~= nil and scoutUpdate.accepted, "escape grants scout")
	assertTrue(thiefUpdate ~= nil and thiefUpdate.accepted, "escape grants thief")
end

do
	local profile = makeProfile()
	local first = ReputationState.ApplyOutcome(profile, {
		outcomeKind = ReputationState.OutcomeKinds.EscapeSuccess,
		now = 1000,
		operationId = "op-repeat-1",
		sourceKind = "escape",
		sourceId = "Route_B",
		difficulty = 1,
		lootValue = 0,
	})
	local second = ReputationState.ApplyOutcome(first.profileData, {
		outcomeKind = ReputationState.OutcomeKinds.EscapeSuccess,
		now = 1010,
		operationId = "op-repeat-2",
		sourceKind = "escape",
		sourceId = "Route_B",
		difficulty = 1,
		lootValue = 0,
	})

	local blockedCount = 0
	for _, update in ipairs(second.trackUpdates) do
		if update.accepted ~= true then
			blockedCount += 1
		end
	end
	assertTrue(blockedCount >= 1, "repeat window blocks at least one track")
end

do
	local profile = makeProfile()
	local first = ReputationState.ApplyOutcome(profile, {
		outcomeKind = ReputationState.OutcomeKinds.EscapeSuccess,
		now = 2000,
		operationId = "op-cooldown-1",
		sourceKind = "escape",
		sourceId = "Route_Cooldown_A",
		difficulty = 1,
		lootValue = 0,
	})
	local second = ReputationState.ApplyOutcome(first.profileData, {
		outcomeKind = ReputationState.OutcomeKinds.EscapeSuccess,
		now = 2010,
		operationId = "op-cooldown-2",
		sourceKind = "escape",
		sourceId = "Route_Cooldown_B",
		difficulty = 1,
		lootValue = 0,
	})

	local sawCooldown = false
	for _, update in ipairs(second.trackUpdates) do
		if update.reason == "cooldown_active" then
			sawCooldown = true
		end
	end
	assertTrue(sawCooldown, "cooldown blocks repeated awards")
end

do
	local profile = makeProfile()
	local currentData = profile
	local lastResult = nil

	for index = 1, 16 do
		lastResult = ReputationState.ApplyOutcome(currentData, {
			outcomeKind = ReputationState.OutcomeKinds.EscapeSuccess,
			now = 10000 + (index * 100),
			operationId = string.format("op-daily-cap-%d", index),
			sourceKind = "escape",
			sourceId = string.format("Route_Daily_%d", index),
			difficulty = 1,
			lootValue = 0,
		})
		currentData = lastResult.profileData
	end

	local scoutDailyCapBlocked = false
	for _, update in ipairs(lastResult.trackUpdates) do
		if update.trackId == ReputationState.Tracks.Scout and update.reason == "daily_cap_reached" then
			scoutDailyCapBlocked = true
		end
	end
	assertTrue(scoutDailyCapBlocked, "daily cap blocks scout track awards")
end

do
	local safeTrait = makeReputationTrait("Tinyfolk_Loadout_EvasiveMarker", true)
	local unsafeTrait = makeReputationTrait("Tinyfolk_Loadout_EvasiveMarker", false)

	local safeCheck, _ = ReputationState.IsLoadoutSafeReputationTraitRecord(safeTrait)
	local unsafeCheck, _ = ReputationState.IsLoadoutSafeReputationTraitRecord(unsafeTrait)
	assertTrue(safeCheck, "safe reputation trait accepted by guard")
	assertFalse(unsafeCheck, "unsafe reputation trait rejected by guard")
end

do
	local profile = makeProfile()
	profile.reputationState = {
		schemaVersion = 1,
		byTrackId = {
			Escapist = {
				trackId = "Escapist",
				points = 59,
				lastGrantedAt = nil,
				cooldownReadyAt = nil,
				dayIndex = 0,
				awardedInDay = 0,
			},
		},
		recentOutcomeAtByKey = {},
		unlockedCosmeticIds = {},
		unlockedLoadoutTraitIds = {},
	}

	local result = ReputationState.ApplyOutcome(profile, {
		outcomeKind = ReputationState.OutcomeKinds.EscapeSuccess,
		now = 5000,
		operationId = "op-unlock",
		sourceKind = "escape",
		sourceId = "Route_C",
		difficulty = 1,
		lootValue = 0,
	}, {
		makeReputationTrait("Tinyfolk_Loadout_EvasiveMarker", true),
	})

	local foundUnlock = false
	for _, unlock in ipairs(result.unlockUpdates) do
		if unlock.unlockId == "Tinyfolk_Loadout_EvasiveMarker" and unlock.accepted == true then
			foundUnlock = true
		end
	end
	assertTrue(foundUnlock, "loadout-safe reputation trait unlock awarded at threshold")

	local unlockedSet = ReputationState.GetUnlockedLoadoutTraitSet(result.profileData)
	assertTrue(unlockedSet["Tinyfolk_Loadout_EvasiveMarker"] == true, "unlocked loadout trait persisted")
end

print("reputation_state: all checks passed")
