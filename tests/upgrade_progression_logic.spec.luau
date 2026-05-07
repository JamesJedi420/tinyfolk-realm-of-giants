--!strict

local UpgradeProgressionLogic = require("../src/ReplicatedStorage/Shared/UpgradeBoard/UpgradeProgressionLogic")

local function assertEqual<T>(actual: T, expected: T, label: string)
	if actual ~= expected then
		error(string.format("assertEqual failed for %s: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	if not value then
		error(string.format("assertTrue failed for %s", label))
	end
end

local function assertFalse(value: boolean, label: string)
	if value then
		error(string.format("assertFalse failed for %s", label))
	end
end

local function run()
	local kernel = UpgradeProgressionLogic.BuildKernel(
		{
			{ id = "PowerCore", costEssence = 24 },
			{ id = "IronStride", costEssence = 18 },
		},
		{
			PowerCore = { maxHealthBonus = 50, walkSpeedBonus = 0, powerBudgetBonus = 25, movementControlBonus = 0 },
			IronStride = { maxHealthBonus = 0, walkSpeedBonus = 6, powerBudgetBonus = 0, movementControlBonus = 0.25 },
		}
	)

	local emptyState: {[string]: boolean} = {}
	local progress0 = UpgradeProgressionLogic.ResolveProgressionState(kernel, emptyState)
	assertEqual(progress0.completedSteps, 0, "next-step completedSteps at start")
	assertEqual(progress0.totalSteps, 2, "next-step totalSteps")
	assertEqual(progress0.nextUpgradeId, "PowerCore", "next-step nextUpgradeId")
	assertEqual(progress0.status, "InProgress", "next-step status")

	local orderedState = UpgradeProgressionLogic.ApplySelection(emptyState, "PowerCore")
	local progress1 = UpgradeProgressionLogic.ResolveProgressionState(kernel, orderedState)
	assertEqual(progress1.completedSteps, 1, "post-first completedSteps")
	assertEqual(progress1.nextUpgradeId, "IronStride", "post-first nextUpgradeId")

	local allowOutOfOrder, outOfOrderReason = UpgradeProgressionLogic.ValidateSelection(kernel, emptyState, "IronStride", true)
	assertFalse(allowOutOfOrder, "out-of-order rejected")
	assertEqual(outOfOrderReason, "out_of_order expected=PowerCore requested=IronStride", "out-of-order reason")

	local allowAlreadyOwned, alreadyOwnedReason = UpgradeProgressionLogic.ValidateSelection(kernel, orderedState, "PowerCore", true)
	assertFalse(allowAlreadyOwned, "already-owned rejected")
	assertEqual(alreadyOwnedReason, "already_selected", "already-owned reason")

	local fullState = UpgradeProgressionLogic.ApplySelection(orderedState, "IronStride")
	local progressCompleted = UpgradeProgressionLogic.ResolveProgressionState(kernel, fullState)
	assertEqual(progressCompleted.status, "Completed", "completion status")
	assertEqual(progressCompleted.nextUpgradeId, nil, "completion nextUpgradeId")

	local allowCompleted, completedReason = UpgradeProgressionLogic.ValidateSelection(kernel, fullState, "IronStride", true)
	assertFalse(allowCompleted, "completed progression rejects further select")
	assertEqual(completedReason, "already_selected", "completed already-owned precedence")

	local allowInsufficient, insufficientReason, _, requiredCost = UpgradeProgressionLogic.ValidateSelection(kernel, orderedState, "IronStride", false)
	assertFalse(allowInsufficient, "insufficient essence rejected")
	assertEqual(insufficientReason, "insufficient_essence", "insufficient essence reason")
	assertEqual(requiredCost, 18, "insufficient essence required cost")
	assertEqual(orderedState["IronStride"], nil, "insufficient essence no-advance state")

	local malformedKernel = UpgradeProgressionLogic.BuildKernel(
		{
			{ id = "", costEssence = 5 },
			{ id = "PowerCore", costEssence = 10 },
			{ id = "PowerCore", costEssence = 10 },
			{ id = "IronStride", costEssence = -1 },
		},
		{
			PowerCore = { maxHealthBonus = 1, walkSpeedBonus = 1, powerBudgetBonus = 1, movementControlBonus = 1 },
		}
	)
	assertEqual(#malformedKernel.orderedUpgradeIds, 2, "duplicate and malformed ids filtered")
	assertTrue(#malformedKernel.warnings >= 3, "warnings emitted for malformed kernel")
	assertEqual(malformedKernel.upgradeCostById["IronStride"], 0, "invalid cost defaults to zero")

	local emptyKernel = UpgradeProgressionLogic.BuildKernel({}, {})
	local emptyProgress = UpgradeProgressionLogic.ResolveProgressionState(emptyKernel, {})
	assertEqual(emptyProgress.status, "Unavailable", "empty kernel unavailable progression")

	print("upgrade_progression_logic.spec: PASS")
end

run()
