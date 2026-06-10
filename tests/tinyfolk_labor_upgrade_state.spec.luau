--!strict

local TinyfolkLaborUpgradeConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkLaborUpgradeConfig")
local TinyfolkLaborUpgradeState = require("../src/ReplicatedStorage/Shared/GiantRealm/TinyfolkLaborUpgradeState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local track = TinyfolkLaborUpgradeState.ResolveTrackForBenchId("TinyfolkLaborBench_Haul_A")
	assertEqual(track, TinyfolkLaborUpgradeConfig.Tracks.HaulYield, "haul bench maps to haul_yield track")
	local paceTrack = TinyfolkLaborUpgradeState.ResolveTrackForBenchId("TinyfolkLaborBench_Pace_A")
	assertEqual(paceTrack, TinyfolkLaborUpgradeConfig.Tracks.TaskPace, "pace bench maps to task_pace track")
end

do
	local state = TinyfolkLaborUpgradeState.CreateEmptyPlayerState()
	local rewarded = TinyfolkLaborUpgradeState.GrantWorkActionReward(state)
	assertEqual(rewarded.laborTokens, 1, "work action grants one labor token")
end

do
	local state = { laborTokens = 3, haulYieldLevel = 0, taskPaceLevel = 0 }
	local first = TinyfolkLaborUpgradeState.ResolveUpgrade(state, TinyfolkLaborUpgradeConfig.Tracks.HaulYield)
	assertTrue(first.accepted, "haul_yield level 1 accepted with three tokens")
	assertEqual(first.state.laborTokens, 0, "haul_yield spends three tokens")
	assertEqual(first.state.haulYieldLevel, 1, "haul_yield reaches level 1")
end

do
	local state = { laborTokens = 2, haulYieldLevel = 0, taskPaceLevel = 0 }
	local rejected = TinyfolkLaborUpgradeState.ResolveUpgrade(state, TinyfolkLaborUpgradeConfig.Tracks.HaulYield)
	assertEqual(rejected.reason, "insufficient_labor_tokens", "haul_yield rejects without enough tokens")
end

do
	local state = { laborTokens = 0, haulYieldLevel = 0, taskPaceLevel = 0 }
	local pace = TinyfolkLaborUpgradeState.ResolveUpgrade(state, TinyfolkLaborUpgradeConfig.Tracks.TaskPace)
	assertTrue(pace.accepted, "task_pace resolves before food spend")
	assertEqual(pace.spendKind, "stored_food", "task_pace spends stored food")
	assertEqual(pace.pendingFoodCost, 4, "task_pace level 1 costs four food")
end

do
	assertEqual(TinyfolkLaborUpgradeState.ResolveHaulYieldMultiplier(2), 1.5, "haul_yield level 2 multiplier")
	assertEqual(TinyfolkLaborUpgradeState.ResolveTaskPaceMultiplier(2), 0.7, "task_pace level 2 multiplier")
end

print("tinyfolk_labor_upgrade_state.spec.luau: all checks passed")
