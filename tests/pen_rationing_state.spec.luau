--!strict

local PenRationingState = require("../src/ReplicatedStorage/Shared/GiantRealm/PenRationingState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

assertEqual(PenRationingState.ComputeFoodCostForInterval(0, 1), 0, "zero captives costs zero food")
assertEqual(PenRationingState.ComputeFoodCostForInterval(2, 1), 2, "two captives cost two food")
assertEqual(PenRationingState.ComputeFoodCostForInterval(3, 2), 6, "three captives at two food each")

local dueTicks, nextAccumulator = PenRationingState.CountDueTicks(0, 0.5, 1)
assertEqual(dueTicks, 0, "half interval yields no tick")
assertEqual(nextAccumulator, 0.5, "half interval accumulates")

dueTicks, nextAccumulator = PenRationingState.CountDueTicks(0.5, 0.5, 1)
assertEqual(dueTicks, 1, "full interval yields one tick")
assertEqual(nextAccumulator, 0, "full interval clears accumulator")

dueTicks, nextAccumulator = PenRationingState.CountDueTicks(0, 2.5, 1)
assertEqual(dueTicks, 2, "2.5 seconds yields two ticks")
assertEqual(nextAccumulator, 0.5, "remainder preserved after multi-tick")

assertEqual(PenRationingState.ComputeFoodCostForInterval(2, 1, 0.75), 2, "pen upgrade multiplier rounds food cost")
assertEqual(PenRationingState.ComputeFoodCostForInterval(2, 1, 0.5), 1, "high pen level reduces food cost")

assertEqual(PenRationingState.ApplyMoraleDelta(100, -12, 0, 100), 88, "morale loss clamps within bounds")
assertEqual(PenRationingState.ShouldForceStarvationRelease(3, 3), true, "threshold reached")
assertEqual(PenRationingState.ShouldForceStarvationRelease(2, 3), false, "threshold not reached")

local releaseTarget = PenRationingState.SelectStarvationReleaseTarget({
	{ custodianUserId = 1, targetUserId = 202, startedAt = 12 },
	{ custodianUserId = 1, targetUserId = 201, startedAt = 10 },
})
assertEqual(releaseTarget, 201, "oldest captive selected for starvation release")

assertEqual(PenRationingState.ComputeCaptureReadinessPercent(100, 50), 100, "full morale readiness")
assertEqual(PenRationingState.ComputeCaptureReadinessPercent(25, 50), 50, "half morale readiness")
assertEqual(PenRationingState.ComputeCaptureReadinessPercent(0, 50), 0, "zero morale readiness")

local depleted = PenRationingState.ResolveCaptureMoraleCheck(0, 9001, 9101, 60, 50)
assertEqual(depleted.allowed, false, "zero morale blocks capture")
assertEqual(depleted.reason, "custodian_morale_depleted", "zero morale reason")

local sure = PenRationingState.ResolveCaptureMoraleCheck(50, 9001, 9101, 60, 50)
assertEqual(sure.allowed, true, "sure threshold morale always captures")

local shaken = PenRationingState.ResolveCaptureMoraleCheck(48, 9001, 9101, 60, 50)
assertEqual(shaken.allowed, false, "low morale deterministic fail")
assertEqual(shaken.reason, "custodian_morale_shaken", "shaken morale reason")

local intimidated = PenRationingState.ResolveCaptureMoraleCheck(48, 9001, 9101, 60, 50, 1.5)
assertEqual(intimidated.allowed, true, "intimidation bonus enables shaken morale capture")

local depletedWithBonus = PenRationingState.ResolveCaptureMoraleCheck(0, 9001, 9101, 60, 50, 1.5)
assertEqual(depletedWithBonus.allowed, false, "intimidation bonus does not bypass depleted morale")

local recovered = PenRationingState.ResolveCaptureMoraleCheck(49, 9001, 9101, 60, 50)
assertEqual(recovered.allowed, true, "low morale deterministic pass")

assertEqual(PenRationingState.ApplyCaptiveShortfallStreak(0, true), 1, "captive shortfall increments")
assertEqual(PenRationingState.ApplyCaptiveShortfallStreak(2, false), 0, "captive shortfall resets")
assertEqual(PenRationingState.IsCaptiveStarving(1, 2), false, "one shortfall not starving")
assertEqual(PenRationingState.IsCaptiveStarving(2, 2), true, "two shortfalls starving")

print("pen_rationing_state.spec.luau: all checks passed")
