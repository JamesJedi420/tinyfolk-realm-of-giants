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

print("pen_rationing_state.spec.luau: all checks passed")
