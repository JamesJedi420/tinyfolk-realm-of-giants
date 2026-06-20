--!nocheck

local TinyfolkJobSchedulingConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local TinyfolkJobSchedulingState = require("../src/ReplicatedStorage/Shared/GiantRealm/TinyfolkJobSchedulingState")

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

local workers = {
	{
		userId = 1,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
	{
		userId = 2,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.Miner,
		assignedStationId = "MiningStation_A",
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
}

local filled = TinyfolkJobSchedulingState.ResolveFilledSpecialistTargets(workers)
assertTrue(filled["MiningStation_A"] == true, "miner assignment fills mining station demand")

local specialistDemands = TinyfolkJobSchedulingState.BuildSpecialistDemands({
	{
		stationId = "WorkStation_A",
		requiredSpecialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
		materialType = "Wood",
	},
	{
		stationId = "MiningStation_A",
		requiredSpecialistRole = SpecialistConfig.SpecialistRoles.Miner,
		materialType = "Stone",
	},
}, {
	{
		shrineId = "Shrine_A",
		requiredSpecialistRole = SpecialistConfig.SpecialistRoles.Worshipper,
	},
}, filled)

assertEqual(#specialistDemands, 2, "unfilled work station and shrine produce demands")
local demandStationIds: { [string]: boolean } = {}
for _, demand in ipairs(specialistDemands) do
	if demand.stationId ~= nil then
		demandStationIds[demand.stationId] = true
	end
	if demand.shrineId ~= nil then
		demandStationIds[demand.shrineId] = true
	end
end
assertTrue(demandStationIds["WorkStation_A"] == true, "work station demand present")
assertTrue(demandStationIds["Shrine_A"] == true, "shrine demand present")

local haulDemands = TinyfolkJobSchedulingState.BuildHaulDemands({
	Wood = { produced = 4, inTransit = 0, stored = 0 },
	Stone = { produced = 0, inTransit = 0, stored = 0 },
}, {})
assertEqual(#haulDemands, 1, "wood produced creates haul demand")
assertEqual(haulDemands[1].material, "Wood", "haul demand material is wood")

local matchWorkers = {
	{
		userId = 1,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
	{
		userId = 2,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
}

local matchResult = TinyfolkJobSchedulingState.SelectAssignments(specialistDemands, matchWorkers)
assertEqual(#matchResult.assignments, 2, "two eligible workers take two specialist demands")
local assignedRoles: { [string]: boolean } = {}
for _, assignment in ipairs(matchResult.assignments) do
	assignedRoles[assignment.specialistRole] = true
end
assertTrue(assignedRoles[SpecialistConfig.SpecialistRoles.Woodcutter] == true, "woodcutter demand assigned")
assertTrue(assignedRoles[SpecialistConfig.SpecialistRoles.Worshipper] == true, "worshipper demand assigned")

local combinedDemands = {}
for _, demand in ipairs(specialistDemands) do
	table.insert(combinedDemands, demand)
end
for _, demand in ipairs(haulDemands) do
	table.insert(combinedDemands, demand)
end

local exclusiveWorkers = {
	{
		userId = 10,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
}
local exclusiveMatch = TinyfolkJobSchedulingState.SelectAssignments(combinedDemands, exclusiveWorkers)
assertEqual(#exclusiveMatch.assignments, 1, "one worker takes highest-priority specialist demand only")
assertEqual(
	exclusiveMatch.assignments[1].kind,
	TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
	"specialist demand wins over haul for single worker"
)
local busyWorkers = {
	{
		userId = 3,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
		captureActive = false,
	},
}
local busyMatch = TinyfolkJobSchedulingState.SelectAssignments(specialistDemands, busyWorkers)
assertEqual(#busyMatch.assignments, 0, "already scheduled worker gets no assignment")

local roleConflictWorkers = {
	{
		userId = 4,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.Farmer,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
}
local canTake, reason =
	TinyfolkJobSchedulingState.CanWorkerTakeSpecialistDemand(roleConflictWorkers[1], specialistDemands[1])
assertTrue(not canTake, "farmer cannot take woodcutter demand")
assertTrue(
	string.find(reason or "", "specialist_role_conflict", 1, true) ~= nil,
	"role conflict reason names specialist_role_conflict"
)

local capturedWorkers = {
	{
		userId = 5,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = true,
	},
}
local capturedEligible = TinyfolkJobSchedulingState.IsWorkerEligible(capturedWorkers[1])
assertTrue(not capturedEligible, "captured worker is ineligible")

local woodcutterDemand = {
	{
		demandId = "specialist:WorkStation_A",
		kind = TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
		stationId = "WorkStation_A",
		shrineId = nil,
		specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
		material = "Wood",
		priority = TinyfolkJobSchedulingConfig.SpecialistDemandPriority,
	},
}

local favorRankWorkers = {
	{
		userId = 100,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
		dyadicFavor = 30,
		dyadicControl = 50,
	},
	{
		userId = 50,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
		dyadicFavor = 80,
		dyadicControl = 50,
	},
}
local favorRankResult = TinyfolkJobSchedulingState.SelectAssignments(woodcutterDemand, favorRankWorkers)
assertEqual(#favorRankResult.assignments, 1, "one woodcutter demand assigns one worker")
assertEqual(favorRankResult.assignments[1].userId, 50, "higher dyadic favor wins over lower userId")

local controlTieWorkers = {
	{
		userId = 100,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
		dyadicFavor = 60,
		dyadicControl = 70,
	},
	{
		userId = 50,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
		dyadicFavor = 60,
		dyadicControl = 40,
	},
}
local controlTieResult = TinyfolkJobSchedulingState.SelectAssignments(woodcutterDemand, controlTieWorkers)
assertEqual(controlTieResult.assignments[1].userId, 50, "equal favor prefers lower control")

local neutralRankWorkers = {
	{
		userId = 100,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
	{
		userId = 50,
		role = "Tinyfolk",
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.None,
		captureActive = false,
	},
}
local neutralRankResult = TinyfolkJobSchedulingState.SelectAssignments(woodcutterDemand, neutralRankWorkers)
assertEqual(neutralRankResult.assignments[1].userId, 50, "missing dyadic attrs tie-break by userId")

local scheduleRank = TinyfolkJobSchedulingState.ResolveWorkerScheduleRank({
	userId = 7,
	role = "Tinyfolk",
	dyadicFavor = 120,
	dyadicControl = -5,
})
assertEqual(scheduleRank.favor, 100, "schedule rank clamps favor to axis max")
assertEqual(scheduleRank.control, 0, "schedule rank clamps control to axis min")

local debugWorker = TinyfolkJobSchedulingState.FormatWorkerForDebug(favorRankWorkers[2])
assertEqual(debugWorker.scheduleRankFavor, 80, "debug worker exposes resolved schedule rank favor")
assertEqual(debugWorker.scheduleRankControl, 50, "debug worker exposes resolved schedule rank control")

local previousDyadicRanking = TinyfolkJobSchedulingConfig.UseDyadicWorkerRanking
TinyfolkJobSchedulingConfig.UseDyadicWorkerRanking = false
local userIdRankResult = TinyfolkJobSchedulingState.SelectAssignments(woodcutterDemand, favorRankWorkers)
TinyfolkJobSchedulingConfig.UseDyadicWorkerRanking = previousDyadicRanking
assertEqual(userIdRankResult.assignments[1].userId, 50, "dyadic ranking disabled falls back to userId order")

print("tinyfolk_job_scheduling_state: all checks passed")
