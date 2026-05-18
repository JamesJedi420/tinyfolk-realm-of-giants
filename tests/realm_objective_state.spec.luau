--!strict

local RealmObjectiveState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmObjectiveState")

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

do
	local state = RealmObjectiveState.NewState({
		BaseRequiredCompletions = 1,
		MinimumRequiredCompletions = 1,
	})

	local registerB = RealmObjectiveState.RegisterSite(state, "Site_B", "station", 3)
	assertTrue(registerB.accepted, "register first site accepted")

	local registerA = RealmObjectiveState.RegisterSite(registerB.state, "Site_A", "construction", 3)
	assertTrue(registerA.accepted, "register second site accepted")

	local registerC = RealmObjectiveState.RegisterSite(registerA.state, "Site_C", "shrine", 3)
	assertTrue(registerC.accepted, "register third site accepted")

	local registerD = RealmObjectiveState.RegisterSite(registerC.state, "Site_D", "generic", 3)
	assertTrue(registerD.accepted, "register fourth site accepted")

	local snapshot = RealmObjectiveState.GetSnapshot(registerD.state)
	assertEqual(snapshot.totalSiteCount, 4, "snapshot total site count")
	assertEqual(snapshot.requiredCompletions, 2, "required completions scales at 3 tinyfolk")
	assertEqual(snapshot.siteIds[1], "Site_A", "site ids sorted first")
	assertEqual(snapshot.siteIds[4], "Site_D", "site ids sorted last")

	local duplicate = RealmObjectiveState.RegisterSite(registerD.state, "Site_A", "construction", 3)
	assertFalse(duplicate.accepted, "duplicate site registration rejected")
	assertEqual(duplicate.reason, "site_already_registered", "duplicate site rejection reason")

	local completeUnknown = RealmObjectiveState.RecordCompletion(registerD.state, "Unknown_Site", 2101, 100)
	assertFalse(completeUnknown.accepted, "unknown site completion rejected")
	assertEqual(completeUnknown.reason, "site_not_found", "unknown site rejection reason")

	local completedA = RealmObjectiveState.RecordCompletion(registerD.state, "Site_A", 2101, 101)
	assertTrue(completedA.accepted, "first site completion accepted")
	assertEqual(completedA.alert.kind, "objective_completed", "completion alert kind")
	assertEqual(completedA.alert.siteId, "Site_A", "completion alert site id")
	assertEqual(completedA.alert.completedCount, 1, "completion alert count after first complete")
	assertFalse(completedA.alert.escapeReady, "escape not ready after first complete")

	local completedB = RealmObjectiveState.RecordCompletion(completedA.state, "Site_B", 2102, 102)
	assertTrue(completedB.accepted, "second site completion accepted")
	assertEqual(completedB.alert.completedCount, 2, "completion alert count after second complete")
	assertTrue(completedB.alert.escapeReady, "escape ready when required completions met")

	local completedAgain = RealmObjectiveState.RecordCompletion(completedB.state, "Site_B", 2102, 103)
	assertFalse(completedAgain.accepted, "already completed site rejected")
	assertEqual(completedAgain.reason, "site_already_completed", "already completed rejection reason")

	local recomputed = RealmObjectiveState.RecomputeRequiredCompletions(completedB.state, 1)
	local recomputedSnapshot = RealmObjectiveState.GetSnapshot(recomputed)
	assertEqual(recomputedSnapshot.requiredCompletions, 1, "required completions recompute at 1 tinyfolk")
	assertTrue(recomputedSnapshot.escapeReady, "escape remains ready after required recompute down")
end

print("realm_objective_state: all checks passed")
