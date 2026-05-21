--!nocheck

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

local function expectAlertCompletedCount(value: any?, label: string): number
	if type(value) ~= "table" then
		error(string.format("FAIL [%s]: expected table value", label))
	end
	local alert: any = value
	if type(alert.completedCount) ~= "number" then
		error(string.format("FAIL [%s]: expected completedCount number", label))
	end
	return alert.completedCount
end

do
	local state = RealmObjectiveState.NewState({
		BaseRequiredCompletions = 1,
		MinimumRequiredCompletions = 1,
		CompletionProgress = 100,
		DisruptionDamage = 25,
		RegressionPerSecond = 10,
		StabilizationProgress = 20,
		MajorRegressionMaxEvents = 2,
		DefaultBlockDurationSeconds = 4,
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
	completedA.alert.completedCount = 999
	local completedASnapshot = RealmObjectiveState.GetSnapshot(completedA.state)
	assertEqual(completedASnapshot.lastReason, "accepted", "completion alert mutation does not affect state reason")
	local completedCount =
		expectAlertCompletedCount(completedASnapshot.lastAlert, "completion alert mutation does not leak into state")
	assertEqual(completedCount, 1, "completion alert mutation does not leak into state")

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

do
	local state = RealmObjectiveState.NewState({
		CompletionProgress = 100,
		DisruptionDamage = 30,
		RegressionPerSecond = 10,
		StabilizationProgress = 25,
		MajorRegressionMaxEvents = 2,
		DefaultBlockDurationSeconds = 3,
	})

	local registered = RealmObjectiveState.RegisterSite(state, "Stateful_A", "construction", 2)
	assertTrue(registered.accepted, "stateful site registered")

	local began = RealmObjectiveState.BeginProgress(registered.state, "Stateful_A", 7001, 10)
	assertTrue(began.accepted, "begin progress accepted")
	assertEqual(began.reason, "progress_began", "begin progress reason")
	assertEqual(began.alert.objectiveState, "progressing", "begin alert state")

	local progressed = RealmObjectiveState.ApplyProgress(began.state, "Stateful_A", 60, 7001, 11)
	assertTrue(progressed.accepted, "partial progress accepted")
	local progressSnapshot = RealmObjectiveState.GetSnapshot(progressed.state)
	assertEqual(progressSnapshot.sitesById.Stateful_A.objectiveState, "progressing", "partial progress state")
	assertEqual(progressSnapshot.sitesById.Stateful_A.progress, 60, "partial progress preserved")

	local canceled = RealmObjectiveState.CancelProgress(progressed.state, "Stateful_A", 12)
	assertTrue(canceled.accepted, "cancel progress accepted")
	local canceledSnapshot = RealmObjectiveState.GetSnapshot(canceled.state)
	assertEqual(canceledSnapshot.sitesById.Stateful_A.objectiveState, "contested", "retreat preserves partial progress")
	assertEqual(canceledSnapshot.sitesById.Stateful_A.progress, 60, "retreat does not erase progress")

	local disrupted = RealmObjectiveState.DisruptProgress(canceled.state, "Stateful_A", 8001, 13, 3)
	assertTrue(disrupted.accepted, "disruption accepted")
	local disruptedSnapshot = RealmObjectiveState.GetSnapshot(disrupted.state)
	assertEqual(disruptedSnapshot.sitesById.Stateful_A.objectiveState, "regressing", "disruption starts regression")
	assertEqual(disruptedSnapshot.sitesById.Stateful_A.progress, 30, "disruption damages partial progress")
	assertEqual(disruptedSnapshot.sitesById.Stateful_A.regressionEventsUsed, 1, "disruption count increments")

	local ticked = RealmObjectiveState.TickRegression(disrupted.state, "Stateful_A", 14)
	assertTrue(ticked.accepted, "regression tick accepted")
	local tickedSnapshot = RealmObjectiveState.GetSnapshot(ticked.state)
	assertEqual(tickedSnapshot.sitesById.Stateful_A.progress, 25, "regression stabilizes at threshold")
	assertEqual(tickedSnapshot.sitesById.Stateful_A.objectiveState, "contested", "regression stabilizes to contested")

	local disruptedAgain = RealmObjectiveState.DisruptProgress(ticked.state, "Stateful_A", 8001, 15, 3)
	assertTrue(disruptedAgain.accepted, "second disruption accepted")
	local capped = RealmObjectiveState.DisruptProgress(disruptedAgain.state, "Stateful_A", 8001, 16, 3)
	assertFalse(capped.accepted, "major regression cap prevents indefinite stall")
	assertEqual(capped.reason, "regression_cap_reached", "major regression cap reason")
end

do
	local state = RealmObjectiveState.NewState({
		CompletionProgress = 100,
		DefaultBlockDurationSeconds = 5,
	})
	local registered = RealmObjectiveState.RegisterSite(state, "Gate_A", "station", 1)
	local blocked = RealmObjectiveState.BlockObjective(registered.state, "Gate_A", 9001, 10, 5)
	assertTrue(blocked.accepted, "temporary block accepted")
	assertEqual(blocked.alert.objectiveState, "blocked", "block alert state")

	local blockedProgress = RealmObjectiveState.BeginProgress(blocked.state, "Gate_A", 7001, 11)
	assertFalse(blockedProgress.accepted, "blocked objective rejects progress")
	assertEqual(blockedProgress.reason, "blocked", "blocked objective rejection reason")

	local tickAfterBlock = RealmObjectiveState.TickRegression(blocked.state, "Gate_A", 16)
	local afterBlockSnapshot = RealmObjectiveState.GetSnapshot(tickAfterBlock.state)
	assertEqual(afterBlockSnapshot.sitesById.Gate_A.objectiveState, "idle", "temporary block expires back to idle")

	local ruleLocked = RealmObjectiveState.SetRuleLocked(tickAfterBlock.state, "Gate_A", true, 17)
	assertTrue(ruleLocked.accepted, "rule lock accepted")
	local lockedProgress = RealmObjectiveState.BeginProgress(ruleLocked.state, "Gate_A", 7001, 18)
	assertFalse(lockedProgress.accepted, "rule-locked objective rejects progress")
	assertEqual(lockedProgress.reason, "rule_locked", "rule-locked rejection reason")

	local unlocked = RealmObjectiveState.UnlockObjective(ruleLocked.state, "Gate_A", 19)
	assertTrue(unlocked.accepted, "unlock accepted")
	local completed = RealmObjectiveState.ApplyProgress(unlocked.state, "Gate_A", 100, 7001, 20)
	assertTrue(completed.accepted, "progress completion accepted")
	assertEqual(completed.reason, "completed", "progress completion reason")
	assertEqual(completed.alert.kind, "objective_completed", "progress completion alert")

	local registeredZero = RealmObjectiveState.RegisterSite(state, "Gate_B", "station", 1)
	local zeroDurationBlock = RealmObjectiveState.BlockObjective(registeredZero.state, "Gate_B", 9001, 30, 0)
	assertTrue(zeroDurationBlock.accepted, "zero-duration block falls back to configured duration")
	assertEqual(zeroDurationBlock.alert.blockedUntil, 35, "zero-duration block uses configured duration")
end

do
	local state = RealmObjectiveState.NewState()
	local registered = RealmObjectiveState.RegisterSite(state, "Edge_A", "generic", 1)

	local nilSite = RealmObjectiveState.BeginProgress(registered.state, nil :: any, 7001, 1)
	assertFalse(nilSite.accepted, "nil site id rejected")
	assertEqual(nilSite.reason, "site_id_invalid", "nil site id rejection reason")

	local emptySite = RealmObjectiveState.ApplyProgress(registered.state, "", 10, 7001, 1)
	assertFalse(emptySite.accepted, "empty site id rejected")
	assertEqual(emptySite.reason, "site_id_invalid", "empty site id rejection reason")

	local badProgress = RealmObjectiveState.ApplyProgress(registered.state, "Edge_A", -5, 7001, 1)
	assertFalse(badProgress.accepted, "negative progress rejected")
	assertEqual(badProgress.reason, "invalid_progress", "negative progress rejection reason")
end

print("realm_objective_state: all checks passed")
