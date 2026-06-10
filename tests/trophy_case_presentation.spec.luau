--!strict

local TrophyConfig = require("../src/ReplicatedStorage/Shared/Config/TrophyConfig")
local TrophyCasePresentation = require("../src/ReplicatedStorage/Shared/GiantRealm/TrophyCasePresentation")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local emptyModel = TrophyCasePresentation.BuildCaseModel({}, {
	score = 0,
	rank = 1,
	rankTitle = "Unknown Giant",
	scoreToNextRank = 50,
})
assertEqual(emptyModel.count, 0, "empty trophy count")
assertEqual(emptyModel.body, "No trophies recorded yet.", "empty trophy body")
assertTrue(string.find(emptyModel.header, "Unknown Giant", 1, true) ~= nil, "empty reputation header")
assertTrue(string.find(emptyModel.header, "Rank 1", 1, true) ~= nil, "empty reputation rank")

local trophies = {
	{
		summary = "Capture Secured (ref-abc123)",
		trophyKind = TrophyConfig.Kinds.CaptureSuccess,
	},
	{
		summary = "Escape Denied (ref-def456, 8s held)",
		trophyKind = TrophyConfig.Kinds.ContainmentEscapeFailure,
	},
}

local filledModel = TrophyCasePresentation.BuildCaseModel(trophies, {
	score = 72,
	rank = 2,
	rankTitle = "Collector",
	scoreToNextRank = 78,
}, 5)
assertEqual(filledModel.count, 2, "filled trophy count")
assertTrue(string.find(filledModel.header, "Collector", 1, true) ~= nil, "filled reputation header")
assertTrue(string.find(filledModel.header, "Rank 2", 1, true) ~= nil, "filled reputation rank")
assertTrue(string.find(filledModel.body, "Escape Denied") ~= nil, "newest trophy listed first")
assertTrue(string.find(filledModel.body, "Capture Secured") ~= nil, "older trophy listed second")

print("trophy_case_presentation.spec.luau: all checks passed")
