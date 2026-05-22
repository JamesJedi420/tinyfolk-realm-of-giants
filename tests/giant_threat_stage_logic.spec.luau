--!nocheck
local Config = require("../src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local Logic = require("../src/ReplicatedStorage/Shared/TinyfolkStatus/GiantThreatStageLogic")

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

local state = Logic.NewState()

local nextState, snapshot = Logic.ResolveTick(state, Config, { now = 10, warningLevel = "none" })
assertEqual(snapshot.stage, "calm", "calm stage is default")
assertEqual(snapshot.warningLevel, "none", "default warning level is preserved")

nextState, snapshot = Logic.ResolveTick(nextState, Config, { now = 11, warningLevel = "watch" })
assertEqual(snapshot.stage, "watch", "watch warning promotes to watch stage")

nextState, snapshot = Logic.ResolveTick(nextState, Config, { now = 12, warningLevel = "danger" })
assertEqual(snapshot.stage, "critical", "danger warning promotes to critical stage")

nextState, snapshot = Logic.ResolveTick(nextState, Config, { now = 13, warningLevel = "none" })
assertEqual(snapshot.stage, "critical", "critical stage holds before decay")

nextState, snapshot = Logic.ResolveTick(nextState, Config, { now = 24, warningLevel = "none" })
assertEqual(snapshot.stage, "pressure", "critical stage decays by one step after hold")

nextState, snapshot = Logic.ResolveTick(nextState, Config, { now = 35, warningLevel = "none" })
assertEqual(snapshot.stage, "watch", "pressure stage decays by one step after hold")

nextState, snapshot = Logic.ResolveTick(nextState, Config, { now = 46, warningLevel = "none" })
assertEqual(snapshot.stage, "calm", "watch stage eventually decays to calm")

assertTrue(type(nextState.stageEnteredAt) == "number", "stage state tracks entry time")
