--!nocheck

local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local TinyfolkHaulLogisticsConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkHaulLogisticsConfig")
local TinyfolkJobSchedulingConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig")
local TinyfolkLaborJobHudConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkLaborJobHudConfig")
local TinyfolkLaborJobHudPresentation =
	require("../src/ReplicatedStorage/Shared/GiantRealm/TinyfolkLaborJobHudPresentation")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local baseSnapshot = {
	role = "Tinyfolk",
	scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
	scheduledMaterial = "Wood",
	scheduledSourceStationId = "WorkStation_A",
	haulPhase = TinyfolkHaulLogisticsConfig.Phases.Pickup,
	haulRouteSourceId = "WorkStation_A",
	haulRouteDeliveryId = "Warehouse_A",
	haulMaterial = "Wood",
	haulInteractionActive = false,
	specialistRole = SpecialistConfig.SpecialistRoles.None,
}

local pickupModel = TinyfolkLaborJobHudPresentation.BuildHudModel(baseSnapshot, {
	targetId = "WorkStation_A",
	inRange = false,
	targetFound = true,
})
assertTrue(pickupModel.visible, "haul pickup hud visible")
assertEqual(pickupModel.title, "Haul Job", "haul title")
assertTrue(string.find(pickupModel.instruction, "Pick up Wood", 1, true) ~= nil, "pickup instruction")
assertEqual(pickupModel.billboardTargetId, "WorkStation_A", "pickup billboard target")
assertEqual(pickupModel.tone, TinyfolkLaborJobHudConfig.Tones.Neutral, "pickup neutral tone")

local deliverSnapshot = table.clone(baseSnapshot)
deliverSnapshot.haulPhase = TinyfolkHaulLogisticsConfig.Phases.Deliver
local deliverModel = TinyfolkLaborJobHudPresentation.BuildHudModel(deliverSnapshot, {
	targetId = "Warehouse_A",
	inRange = true,
	targetFound = true,
})
assertTrue(string.find(deliverModel.instruction, "Deliver Wood", 1, true) ~= nil, "deliver instruction")
assertTrue(string.find(deliverModel.instruction, "in range", 1, true) ~= nil, "deliver in range suffix")
assertEqual(deliverModel.billboardTargetId, "Warehouse_A", "deliver billboard target")
assertEqual(deliverModel.tone, TinyfolkLaborJobHudConfig.Tones.Active, "deliver active tone")

local specialistSnapshot = {
	role = "Tinyfolk",
	scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
	scheduledSourceStationId = "WorkStation_A",
	specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
	haulInteractionActive = false,
}
local specialistModel = TinyfolkLaborJobHudPresentation.BuildHudModel(specialistSnapshot, {
	targetId = "WorkStation_A",
	inRange = true,
	targetFound = true,
})
assertEqual(specialistModel.title, "Specialist Job", "specialist title")
assertTrue(string.find(specialistModel.instruction, "Wood Station", 1, true) ~= nil, "specialist station display name")
assertEqual(specialistModel.billboardTargetId, "WorkStation_A", "specialist billboard target")

local manualSnapshot = table.clone(baseSnapshot)
manualSnapshot.haulInteractionActive = true
local manualModel = TinyfolkLaborJobHudPresentation.BuildHudModel(manualSnapshot, {
	targetId = "WorkStation_A",
	inRange = false,
	targetFound = true,
})
assertTrue(string.find(manualModel.instruction, "Manual haul active", 1, true) ~= nil, "manual haul message")
assertEqual(manualModel.showBillboard, false, "manual haul hides billboard")
assertEqual(manualModel.tone, TinyfolkLaborJobHudConfig.Tones.Warning, "manual haul warning tone")

local completeModel = TinyfolkLaborJobHudPresentation.BuildHudModel({
	role = "Tinyfolk",
	completionFlashActive = true,
}, nil)
assertEqual(completeModel.instruction, "Job complete", "completion flash instruction")
assertEqual(completeModel.tone, TinyfolkLaborJobHudConfig.Tones.Complete, "completion tone")
assertEqual(completeModel.showBillboard, false, "completion hides billboard")

local giantModel = TinyfolkLaborJobHudPresentation.BuildHudModel({
	role = "Giant",
	scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
}, nil)
assertEqual(giantModel.visible, false, "giant hides hud")

local missingTargetModel = TinyfolkLaborJobHudPresentation.BuildHudModel(baseSnapshot, {
	targetId = "WorkStation_A",
	inRange = false,
	targetFound = false,
})
assertTrue(string.find(missingTargetModel.instruction, "target not found", 1, true) ~= nil, "missing target message")
assertEqual(missingTargetModel.showBillboard, false, "missing target hides billboard")

assertEqual(
	TinyfolkLaborJobHudPresentation.ResolveBillboardTarget({
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
		haulPhase = TinyfolkHaulLogisticsConfig.Phases.Pickup,
		haulRouteSourceId = "Farm_A",
	}),
	"Farm_A",
	"resolve pickup target"
)
assertEqual(
	TinyfolkLaborJobHudPresentation.ResolveBillboardTarget({
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
		haulPhase = TinyfolkHaulLogisticsConfig.Phases.Deliver,
		haulRouteDeliveryId = "Granary_A",
	}),
	"Granary_A",
	"resolve deliver target"
)

print("tinyfolk_labor_job_hud_presentation: all checks passed")
