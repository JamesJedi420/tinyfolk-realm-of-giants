--!strict

local ContextualTaskProgressLogic = require("../src/ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected %q got %q", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function taskEvent(eventType: string, taskId: string, now: number): any
	return {
		eventType = eventType,
		taskId = taskId,
		now = now,
		durationSeconds = 2,
		regressionPerSecond = 0.5,
		stabilizationThresholdSeconds = 0.4,
		majorRegressionStepSeconds = 0.8,
		majorRegressionMaxEvents = 2,
		regressionWindowSeconds = 2,
	}
end

local state = ContextualTaskProgressLogic.New()

local beginResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("begin", "ConstructionSite_A", 10))
assertTrue(beginResult.accepted, "begin accepted")
assertEqual(beginResult.reason, "began", "begin reason")
assertEqual(beginResult.snapshot.activeTaskId, "ConstructionSite_A", "begin snapshot active task")
assertEqual(beginResult.snapshot.progressRatio, 0, "begin progress starts at zero")
assertEqual(beginResult.snapshot.objectiveState, "progressing", "begin sets progressing objective state")

local earlyComplete = ContextualTaskProgressLogic.Resolve(state, taskEvent("complete", "ConstructionSite_A", 11))
assertTrue(not earlyComplete.accepted, "early complete rejected")
assertEqual(earlyComplete.reason, "not_ready", "early complete reason")
assertEqual(earlyComplete.snapshot.activeTaskId, "ConstructionSite_A", "state remains active after not_ready")

local cancelResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("cancel", "ConstructionSite_A", 11.5))
assertTrue(cancelResult.accepted, "cancel accepted")
assertEqual(cancelResult.reason, "canceled", "cancel reason")
assertTrue(cancelResult.snapshot.activeTaskId == nil, "cancel clears active task")
assertEqual(cancelResult.snapshot.objectiveState, "idle", "cancel returns objective state to idle")

local restartResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("begin", "ConstructionSite_A", 20))
assertTrue(restartResult.accepted, "restart begin accepted")

local completeResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("complete", "ConstructionSite_A", 22.1))
assertTrue(completeResult.accepted, "complete accepted")
assertEqual(completeResult.reason, "completed", "complete reason")
assertTrue(completeResult.snapshot.activeTaskId == nil, "complete clears active task")
assertEqual(completeResult.snapshot.objectiveState, "completed", "complete sets completed objective state")

local blockResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("block", "ConstructionSite_A", 23))
assertTrue(blockResult.accepted, "block accepted")
assertEqual(blockResult.snapshot.objectiveState, "blocked", "block sets blocked objective state")

local beginWhileBlocked = ContextualTaskProgressLogic.Resolve(state, taskEvent("begin", "ConstructionSite_A", 24))
assertTrue(not beginWhileBlocked.accepted, "begin while blocked rejected")
assertEqual(beginWhileBlocked.reason, "blocked", "begin while blocked reason")

local unblockResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("unblock", "ConstructionSite_A", 25))
assertTrue(unblockResult.accepted, "unblock accepted")
assertEqual(unblockResult.snapshot.objectiveState, "idle", "unblock returns objective state to idle")

local beginForDisrupt = ContextualTaskProgressLogic.Resolve(state, taskEvent("begin", "ConstructionSite_A", 26))
assertTrue(beginForDisrupt.accepted, "begin for disrupt accepted")

local disruptResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("disrupt", "ConstructionSite_A", 26.2))
assertTrue(disruptResult.accepted, "disrupt accepted")
assertEqual(disruptResult.snapshot.objectiveState, "regressing", "disrupt sets regressing objective state")
assertTrue(disruptResult.snapshot.activeTaskId == nil, "disrupt clears active task")

local regressionTick = ContextualTaskProgressLogic.Resolve(state, taskEvent("tick", "ConstructionSite_A", 28.3))
assertTrue(regressionTick.accepted, "tick accepted")
assertEqual(regressionTick.snapshot.objectiveState, "contested", "regression tick stabilizes to contested threshold")

local resumeResult = ContextualTaskProgressLogic.Resolve(state, taskEvent("begin", "ConstructionSite_A", 27))
assertTrue(resumeResult.accepted, "resume begin accepted")
assertEqual(resumeResult.reason, "resumed", "resume begin returns resumed reason")

local cappedState = ContextualTaskProgressLogic.New()
assertTrue(
	ContextualTaskProgressLogic.Resolve(cappedState, taskEvent("begin", "ConstructionSite_A", 40)).accepted,
	"cap begin accepted"
)
local firstCappedDisrupt = ContextualTaskProgressLogic.Resolve(cappedState, {
	eventType = "disrupt",
	taskId = "ConstructionSite_A",
	now = 40.6,
	durationSeconds = 2,
	regressionPerSecond = 0.5,
	stabilizationThresholdSeconds = 0.4,
	majorRegressionStepSeconds = 0.8,
	majorRegressionMaxEvents = 1,
	regressionWindowSeconds = 2,
})
assertTrue(firstCappedDisrupt.accepted, "first capped disrupt accepted")
local secondCappedDisrupt = ContextualTaskProgressLogic.Resolve(cappedState, {
	eventType = "disrupt",
	taskId = "ConstructionSite_A",
	now = 41,
	durationSeconds = 2,
	regressionPerSecond = 0.5,
	stabilizationThresholdSeconds = 0.4,
	majorRegressionStepSeconds = 0.8,
	majorRegressionMaxEvents = 1,
	regressionWindowSeconds = 2,
})
assertTrue(not secondCappedDisrupt.accepted, "second capped disrupt rejected")
assertEqual(secondCappedDisrupt.reason, "regression_cap_reached", "regression cap rejection reason")

local invalidTaskResult = ContextualTaskProgressLogic.Resolve(state, {
	eventType = "begin",
	taskId = "",
	now = 30,
	durationSeconds = 2,
})
assertTrue(not invalidTaskResult.accepted, "invalid task id rejected")
assertEqual(invalidTaskResult.reason, "invalid_task_id", "invalid task id reason")

print("contextual_task_progress_logic: all checks passed")
