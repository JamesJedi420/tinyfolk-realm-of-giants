--!strict

local SocialEconomyConfig = require("../Config/SocialEconomyConfig")
local TinyfolkJobSchedulingConfig = require("../Config/TinyfolkJobSchedulingConfig")
local SpecialistConfig = require("../Config/SpecialistConfig")

local TinyfolkJobSchedulingState = {}

export type StationDemandSnapshot = {
	stationId: string,
	requiredSpecialistRole: string,
	materialType: string?,
	isActive: boolean?,
	activatedByUserId: number?,
}

export type ShrineDemandSnapshot = {
	shrineId: string,
	requiredSpecialistRole: string,
}

export type FlowMaterialSnapshot = {
	produced: number,
	inTransit: number?,
	stored: number?,
}

export type FlowSnapshot = {
	Wood: FlowMaterialSnapshot?,
	Stone: FlowMaterialSnapshot?,
	Food: FlowMaterialSnapshot?,
	Metal: FlowMaterialSnapshot?,
}

export type WorkerSnapshot = {
	userId: number,
	role: string?,
	specialistRole: string?,
	assignedStationId: string?,
	scheduledJobKind: string?,
	captureActive: boolean?,
	dyadicFavor: number?,
	dyadicControl: number?,
}

export type WorkerScheduleRank = {
	favor: number,
	control: number,
	userId: number,
}

export type JobDemand = {
	demandId: string,
	kind: string,
	stationId: string?,
	shrineId: string?,
	specialistRole: string?,
	material: string?,
	priority: number,
}

export type PlannedAssignment = {
	userId: number,
	demandId: string,
	kind: string,
	stationId: string?,
	shrineId: string?,
	specialistRole: string?,
	material: string?,
}

export type PlannedRejection = {
	demandId: string,
	userId: number?,
	reason: string,
}

export type MatchResult = {
	assignments: { PlannedAssignment },
	rejections: { PlannedRejection },
}

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sortDemands(demands: { JobDemand })
	table.sort(demands, function(left: JobDemand, right: JobDemand)
		if left.priority ~= right.priority then
			return left.priority > right.priority
		end
		return left.demandId < right.demandId
	end)
end

local function resolveAxisValue(value: any, defaultValue: number): number
	if isFiniteNumber(value) then
		return math.clamp(value :: number, SocialEconomyConfig.AxisMin, SocialEconomyConfig.AxisMax)
	end
	return defaultValue
end

function TinyfolkJobSchedulingState.ResolveWorkerScheduleRank(worker: WorkerSnapshot): WorkerScheduleRank
	return {
		favor = resolveAxisValue(worker.dyadicFavor, SocialEconomyConfig.DefaultFavor),
		control = resolveAxisValue(worker.dyadicControl, SocialEconomyConfig.DefaultControl),
		userId = worker.userId,
	}
end

local function compareWorkersForSchedule(left: WorkerSnapshot, right: WorkerSnapshot): boolean
	local leftRank = TinyfolkJobSchedulingState.ResolveWorkerScheduleRank(left)
	local rightRank = TinyfolkJobSchedulingState.ResolveWorkerScheduleRank(right)
	if leftRank.favor ~= rightRank.favor then
		return leftRank.favor > rightRank.favor
	end
	if leftRank.control ~= rightRank.control then
		return leftRank.control < rightRank.control
	end
	return leftRank.userId < rightRank.userId
end

local function sortWorkers(workers: { WorkerSnapshot })
	table.sort(workers, function(left: WorkerSnapshot, right: WorkerSnapshot)
		if TinyfolkJobSchedulingConfig.UseDyadicWorkerRanking == true then
			return compareWorkersForSchedule(left, right)
		end
		return left.userId < right.userId
	end)
end

function TinyfolkJobSchedulingState.ResolveFilledSpecialistTargets(workers: { WorkerSnapshot }): { [string]: boolean }
	local filled: { [string]: boolean } = {}
	for _, worker in ipairs(workers) do
		if
			isNonEmptyString(worker.specialistRole)
			and worker.specialistRole ~= SpecialistConfig.SpecialistRoles.None
			and isNonEmptyString(worker.assignedStationId)
		then
			local stationId = worker.assignedStationId :: string
			filled[stationId] = true
			if string.sub(stationId, 1, 6) == "Shrine" then
				filled[string.format("shrine:%s", stationId)] = true
			end
		end
	end
	return filled
end

function TinyfolkJobSchedulingState.BuildSpecialistDemands(
	stationSnapshots: { StationDemandSnapshot },
	shrineSnapshots: { ShrineDemandSnapshot },
	filledTargets: { [string]: boolean }
): { JobDemand }
	local demands: { JobDemand } = {}

	for _, station in ipairs(stationSnapshots) do
		if not isNonEmptyString(station.stationId) or not isNonEmptyString(station.requiredSpecialistRole) then
			continue
		end
		if filledTargets[station.stationId] == true then
			continue
		end

		table.insert(demands, {
			demandId = string.format("specialist:%s", station.stationId),
			kind = TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
			stationId = station.stationId,
			shrineId = nil,
			specialistRole = station.requiredSpecialistRole,
			material = station.materialType,
			priority = TinyfolkJobSchedulingConfig.SpecialistDemandPriority,
		})
	end

	for _, shrine in ipairs(shrineSnapshots) do
		if not isNonEmptyString(shrine.shrineId) or not isNonEmptyString(shrine.requiredSpecialistRole) then
			continue
		end
		local shrineKey = string.format("shrine:%s", shrine.shrineId)
		if filledTargets[shrineKey] == true or filledTargets[shrine.shrineId] == true then
			continue
		end

		table.insert(demands, {
			demandId = string.format("specialist:%s", shrine.shrineId),
			kind = TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction,
			stationId = shrine.shrineId,
			shrineId = shrine.shrineId,
			specialistRole = shrine.requiredSpecialistRole,
			material = nil,
			priority = TinyfolkJobSchedulingConfig.SpecialistDemandPriority,
		})
	end

	sortDemands(demands)
	return demands
end

function TinyfolkJobSchedulingState.BuildHaulDemands(
	flowSnapshot: FlowSnapshot?,
	scheduledHaulMaterials: { [string]: boolean }
): { JobDemand }
	local demands: { JobDemand } = {}
	if type(flowSnapshot) ~= "table" then
		return demands
	end

	for _, material in ipairs(TinyfolkJobSchedulingConfig.HaulMaterials) do
		local materialSnapshot = flowSnapshot[material :: "Wood" | "Stone" | "Food" | "Metal"]
		local produced = if type(materialSnapshot) == "table" then materialSnapshot.produced else 0
		if not isFiniteNumber(produced) or produced <= 0 then
			continue
		end
		if scheduledHaulMaterials[material] == true then
			continue
		end

		local sourceStationId = TinyfolkJobSchedulingConfig.SourceStationIdByMaterial[material]
		table.insert(demands, {
			demandId = string.format("haul:%s", material),
			kind = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
			stationId = sourceStationId,
			shrineId = nil,
			specialistRole = nil,
			material = material,
			priority = TinyfolkJobSchedulingConfig.HaulDemandPriority,
		})
	end

	sortDemands(demands)
	return demands
end

function TinyfolkJobSchedulingState.IsWorkerEligible(worker: WorkerSnapshot): (boolean, string?)
	if worker.role ~= "Tinyfolk" then
		return false, "worker_not_tinyfolk"
	end
	if worker.captureActive == true then
		return false, "worker_captured"
	end
	if
		isNonEmptyString(worker.scheduledJobKind)
		and worker.scheduledJobKind ~= TinyfolkJobSchedulingConfig.JobKinds.None
	then
		return false, "worker_already_scheduled"
	end
	return true, nil
end

function TinyfolkJobSchedulingState.CanWorkerTakeSpecialistDemand(
	worker: WorkerSnapshot,
	demand: JobDemand
): (boolean, string?)
	local eligible, reason = TinyfolkJobSchedulingState.IsWorkerEligible(worker)
	if not eligible then
		return false, reason or "worker_ineligible"
	end
	if demand.kind ~= TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction then
		return false, "demand_kind_mismatch"
	end
	if not isNonEmptyString(demand.specialistRole) then
		return false, "specialist_role_missing"
	end
	local requiredSpecialistRole = demand.specialistRole :: string

	local specialistRole = worker.specialistRole or SpecialistConfig.SpecialistRoles.None
	if specialistRole ~= SpecialistConfig.SpecialistRoles.None and specialistRole ~= requiredSpecialistRole then
		return false,
			string.format("specialist_role_conflict required=%s actual=%s", requiredSpecialistRole, specialistRole)
	end

	return true, nil
end

function TinyfolkJobSchedulingState.CanWorkerTakeHaulDemand(
	worker: WorkerSnapshot,
	demand: JobDemand
): (boolean, string?)
	local eligible, reason = TinyfolkJobSchedulingState.IsWorkerEligible(worker)
	if not eligible then
		return false, reason or "worker_ineligible"
	end
	if demand.kind ~= TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
		return false, "demand_kind_mismatch"
	end
	if not isNonEmptyString(demand.material) then
		return false, "haul_material_missing"
	end
	return true, nil
end

function TinyfolkJobSchedulingState.SelectAssignments(
	demands: { JobDemand },
	workers: { WorkerSnapshot },
	maxAssignments: number?
): MatchResult
	local assignments: { PlannedAssignment } = {}
	local rejections: { PlannedRejection } = {}
	local assignedUserIds: { [number]: boolean } = {}
	local limit = if type(maxAssignments) == "number" and maxAssignments > 0
		then math.floor(maxAssignments)
		else TinyfolkJobSchedulingConfig.MaxAssignmentsPerTick

	local sortedDemands = table.clone(demands)
	sortDemands(sortedDemands)
	local sortedWorkers = table.clone(workers)
	sortWorkers(sortedWorkers)

	for _, demand in ipairs(sortedDemands) do
		if #assignments >= limit then
			table.insert(rejections, {
				demandId = demand.demandId,
				userId = nil,
				reason = "assignment_limit_reached",
			})
			continue
		end

		local matched = false
		for _, worker in ipairs(sortedWorkers) do
			if assignedUserIds[worker.userId] == true then
				continue
			end

			local canTake = false
			local rejectReason: string? = "no_eligible_worker"
			if demand.kind == TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction then
				canTake, rejectReason = TinyfolkJobSchedulingState.CanWorkerTakeSpecialistDemand(worker, demand)
			elseif demand.kind == TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
				canTake, rejectReason = TinyfolkJobSchedulingState.CanWorkerTakeHaulDemand(worker, demand)
			else
				rejectReason = "unsupported_demand_kind"
			end

			if canTake then
				table.insert(assignments, {
					userId = worker.userId,
					demandId = demand.demandId,
					kind = demand.kind,
					stationId = demand.stationId,
					shrineId = demand.shrineId,
					specialistRole = demand.specialistRole,
					material = demand.material,
				})
				assignedUserIds[worker.userId] = true
				matched = true
				break
			end

			if rejectReason ~= nil and rejectReason ~= "no_eligible_worker" then
				table.insert(rejections, {
					demandId = demand.demandId,
					userId = worker.userId,
					reason = rejectReason :: string,
				})
			end
		end

		if not matched then
			table.insert(rejections, {
				demandId = demand.demandId,
				userId = nil,
				reason = "no_eligible_worker",
			})
		end
	end

	return {
		assignments = assignments,
		rejections = rejections,
	}
end

function TinyfolkJobSchedulingState.FormatWorkerForDebug(worker: WorkerSnapshot): any
	local scheduleRank = TinyfolkJobSchedulingState.ResolveWorkerScheduleRank(worker)
	return {
		userId = worker.userId,
		role = worker.role,
		specialistRole = worker.specialistRole,
		assignedStationId = worker.assignedStationId,
		scheduledJobKind = worker.scheduledJobKind,
		captureActive = worker.captureActive,
		dyadicFavor = worker.dyadicFavor,
		dyadicControl = worker.dyadicControl,
		scheduleRankFavor = scheduleRank.favor,
		scheduleRankControl = scheduleRank.control,
	}
end

function TinyfolkJobSchedulingState.BuildDebugSnapshot(input: {
	demands: { JobDemand }?,
	assignments: { PlannedAssignment }?,
	rejections: { PlannedRejection }?,
	workers: { WorkerSnapshot }?,
	lastTickAt: number?,
	lastReason: string?,
}): any
	local debugWorkers: { any }? = nil
	if type(input.workers) == "table" then
		local formattedWorkers: { any } = {}
		for _, worker in ipairs(input.workers) do
			table.insert(formattedWorkers, TinyfolkJobSchedulingState.FormatWorkerForDebug(worker))
		end
		debugWorkers = formattedWorkers
	end

	return {
		demandCount = if type(input.demands) == "table" then #input.demands else 0,
		assignmentCount = if type(input.assignments) == "table" then #input.assignments else 0,
		rejectionCount = if type(input.rejections) == "table" then #input.rejections else 0,
		workerCount = if type(input.workers) == "table" then #input.workers else 0,
		demands = input.demands,
		assignments = input.assignments,
		rejections = input.rejections,
		workers = debugWorkers,
		lastTickAt = input.lastTickAt,
		lastReason = input.lastReason,
	}
end

return TinyfolkJobSchedulingState
