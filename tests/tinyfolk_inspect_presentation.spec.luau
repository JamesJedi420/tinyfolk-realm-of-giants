--!strict

local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local TinyfolkInspectConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkInspectConfig")
local TinyfolkJobSchedulingConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig")
local TinyfolkInspectPresentation = require("../src/ReplicatedStorage/Shared/GiantRealm/TinyfolkInspectPresentation")

local function assertTrue(value: boolean, label: string)
	if value ~= true then
		error(string.format("FAIL [%s]", label))
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s] expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local model = TinyfolkInspectPresentation.BuildPanelModel({
	displayName = "Scout Alpha",
	role = "Tinyfolk",
	specialistRole = SpecialistConfig.SpecialistRoles.Farmer,
	scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
	scheduledJobStationId = "Farm_A",
	scoreTotal = 120,
	laborTokens = 3,
	movementTraitEnabled = true,
})
assertTrue(model.visible, "panel visible")
assertEqual(model.title, "Scout Alpha", "title uses display name")
assertTrue(string.find(model.summary, "Tinyfolk · Farmer", 1, true) ~= nil, "role in summary")
assertTrue(string.find(model.summary, "Traits:", 1, true) ~= nil, "traits line")
assertTrue(string.find(model.summary, "Loyalty: Unavailable", 1, true) ~= nil, "loyalty unavailable")
assertTrue(string.find(model.summary, "Assignment:", 1, true) ~= nil, "assignment line")
assertTrue(string.find(model.summary, "Value: Score 120 · Tokens 3", 1, true) ~= nil, "value line")
assertEqual(model.tone, TinyfolkInspectConfig.Tones.Neutral, "neutral tone")

local dyadicModel = TinyfolkInspectPresentation.BuildPanelModel({
	displayName = "Loyal One",
	role = "Tinyfolk",
	socialDyadicFavor = 55,
	socialDyadicControl = 60,
})
assertTrue(
	string.find(dyadicModel.summary, "Loyalty: Favor 55 / Control 60", 1, true) ~= nil,
	"dyadic loyalty in summary"
)

local warningModel = TinyfolkInspectPresentation.BuildPanelModel({
	displayName = "Held One",
	role = "Tinyfolk",
	carriedState = "Carried",
})
assertEqual(warningModel.tone, TinyfolkInspectConfig.Tones.Warning, "warning tone")

local criticalModel = TinyfolkInspectPresentation.BuildPanelModel({
	displayName = "Hungry One",
	role = "Tinyfolk",
	captiveStarving = true,
})
assertEqual(criticalModel.tone, TinyfolkInspectConfig.Tones.Critical, "critical tone")

print("tinyfolk_inspect_presentation.spec.luau: all checks passed")
