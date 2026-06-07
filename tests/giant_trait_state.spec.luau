--!nocheck

local GiantTraitState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantTraitState")

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
		giantTraitState = {
			unlockedTraitIds = {},
		},
	}
end

do
	local transition = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Giant_Builder_WorksiteEfficiency",
		requesterRole = "Giant",
		unlockSource = "initial",
	})
	assertTrue(transition.accepted, "builder trait unlock accepted")
	assertEqual(transition.reason, "accepted", "builder trait unlock reason")
	assertEqual(#GiantTraitState.GetUnlockedTraitIds(transition.profileData), 1, "builder trait unlock count")
	assertEqual(
		GiantTraitState.GetUnlockedTraitIds(transition.profileData)[1],
		"Giant_Builder_WorksiteEfficiency",
		"builder trait unlock id"
	)
end

do
	local first = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Giant_Builder_WorksiteEfficiency",
		requesterRole = "Giant",
		unlockSource = "initial",
	})
	local duplicate = GiantTraitState.ResolveUnlock(first.profileData, {
		traitId = "Giant_Builder_WorksiteEfficiency",
		requesterRole = "Giant",
		unlockSource = "initial",
	})
	assertFalse(duplicate.accepted, "duplicate unlock rejected")
	assertEqual(duplicate.reason, "trait_already_unlocked", "duplicate unlock reason")
end

do
	local unknown = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Giant_Unknown_Trait",
		requesterRole = "Giant",
		unlockSource = "initial",
	})
	assertFalse(unknown.accepted, "unknown trait rejected")
	assertEqual(unknown.reason, "trait_missing", "unknown trait reason")
end

do
	local wrongRole = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Giant_Builder_WorksiteEfficiency",
		requesterRole = "Tinyfolk",
		unlockSource = "initial",
	})
	assertFalse(wrongRole.accepted, "wrong requester role rejected")
	assertEqual(wrongRole.reason, "requester_not_giant", "wrong requester role reason")
end

do
	local nonGiantTrait = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Tinyfolk_PostCrossingBurst",
		requesterRole = "Giant",
		unlockSource = "initial",
	})
	assertFalse(nonGiantTrait.accepted, "tinyfolk trait unlock rejected")
	assertEqual(nonGiantTrait.reason, "trait_not_giant", "tinyfolk trait unlock reason")
end

do
	local unmetSource = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Giant_ControlStationScan",
		requesterRole = "Giant",
		unlockSource = "role_mastery",
	})
	assertFalse(unmetSource.accepted, "non-initial unlock source rejected")
	assertEqual(unmetSource.reason, "trait_unlock_source_unmet", "non-initial unlock reason")
end

do
	local mismatchSource = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Giant_Builder_WorksiteEfficiency",
		requesterRole = "Giant",
		unlockSource = "milestone",
	})
	assertFalse(mismatchSource.accepted, "unlock source mismatch rejected")
	assertEqual(mismatchSource.reason, "trait_unlock_source_mismatch", "unlock source mismatch reason")
end

do
	local baseline = GiantTraitState.ResolveModifierSnapshot(makeProfile())
	assertEqual(baseline.stationProductionMultiplier, 1, "baseline multiplier is neutral")
	assertEqual(baseline.scoreEventMultiplier, 1, "baseline score multiplier is neutral")

	local unlocked = GiantTraitState.ResolveUnlock(makeProfile(), {
		traitId = "Giant_Builder_WorksiteEfficiency",
		requesterRole = "Giant",
		unlockSource = "initial",
	})
	local boosted = GiantTraitState.ResolveModifierSnapshot(unlocked.profileData)
	assertEqual(boosted.stationProductionMultiplier, 1.1, "builder multiplier applied")
	assertEqual(boosted.scoreEventMultiplier, 1.05, "builder score multiplier applied")
end

print("giant_trait_state: all checks passed")
