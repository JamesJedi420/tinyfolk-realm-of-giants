--!strict

local StationConfig = require("../Config/StationConfig")
local TinyfolkHaulLogisticsConfig = require("../Config/TinyfolkHaulLogisticsConfig")
local TinyfolkJobSchedulingConfig = require("../Config/TinyfolkJobSchedulingConfig")

local TinyfolkHaulLogisticsState = {}

export type Vector3Like = {
	x: number,
	y: number,
	z: number,
}

export type MaterialSnapshot = {
	produced: number?,
	inTransit: number?,
	stored: number?,
}

export type HaulRoute = {
	material: string,
	sourceStationId: string,
	deliveryId: string,
}

export type WorkerSnapshot = {
	userId: number,
	role: string?,
	scheduledJobKind: string?,
	scheduledMaterial: string?,
	scheduledSourceStationId: string?,
	captureActive: boolean?,
	haulInteractionActive: boolean?,
	position: Vector3Like?,
}

export type HaulCooldownContext = {
	lastHaulRequestAt: number?,
	now: number,
	cooldownSeconds: number,
}

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function TinyfolkHaulLogisticsState.ResolveHaulRoute(material: string, sourceStationId: string?): (HaulRoute?, string?)
	if not isNonEmptyString(material) then
		return nil, "material_missing"
	end

	local resolvedSource = sourceStationId
	if not isNonEmptyString(resolvedSource) then
		local fromConfig = TinyfolkJobSchedulingConfig.SourceStationIdByMaterial[material]
		if isNonEmptyString(fromConfig) then
			resolvedSource = fromConfig
		end
	end

	if not isNonEmptyString(resolvedSource) then
		return nil, "source_station_missing"
	end

	local deliveryId = StationConfig.DeliveryPointIdByMaterial[material]
	if not isNonEmptyString(deliveryId) then
		return nil, "delivery_point_missing"
	end

	return {
		material = material,
		sourceStationId = resolvedSource :: string,
		deliveryId = deliveryId :: string,
	},
		nil
end

function TinyfolkHaulLogisticsState.ResolveHaulPhase(materialSnapshot: MaterialSnapshot): string
	local inTransit = if type(materialSnapshot.inTransit) == "number" then materialSnapshot.inTransit else 0
	local produced = if type(materialSnapshot.produced) == "number" then materialSnapshot.produced else 0

	if inTransit > 0 then
		return TinyfolkHaulLogisticsConfig.Phases.Deliver
	end
	if produced > 0 then
		return TinyfolkHaulLogisticsConfig.Phases.Pickup
	end
	return TinyfolkHaulLogisticsConfig.Phases.None
end

function TinyfolkHaulLogisticsState.IsHaulComplete(materialSnapshot: MaterialSnapshot): boolean
	local inTransit = if type(materialSnapshot.inTransit) == "number" then materialSnapshot.inTransit else 0
	local produced = if type(materialSnapshot.produced) == "number" then materialSnapshot.produced else 0
	return produced <= 0 and inTransit <= 0
end

function TinyfolkHaulLogisticsState.IsWorkerEligible(worker: WorkerSnapshot): (boolean, string?)
	if worker.role ~= "Tinyfolk" then
		return false, "worker_not_tinyfolk"
	end
	if worker.captureActive == true then
		return false, "worker_captured"
	end
	if worker.scheduledJobKind ~= TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
		return false, "scheduled_job_not_haul"
	end
	if not isNonEmptyString(worker.scheduledMaterial) then
		return false, "haul_material_missing"
	end
	return true, nil
end

function TinyfolkHaulLogisticsState.ShouldDeferToManualHaul(
	worker: WorkerSnapshot,
	cooldownContext: HaulCooldownContext
): (boolean, string?)
	if worker.haulInteractionActive == true then
		return true, "manual_haul_active"
	end

	if
		isFiniteNumber(cooldownContext.lastHaulRequestAt)
		and isFiniteNumber(cooldownContext.now)
		and isFiniteNumber(cooldownContext.cooldownSeconds)
		and cooldownContext.cooldownSeconds > 0
	then
		local elapsed = cooldownContext.now - (cooldownContext.lastHaulRequestAt :: number)
		if elapsed < cooldownContext.cooldownSeconds then
			return true, "haul_cooldown"
		end
	end

	return false, nil
end

function TinyfolkHaulLogisticsState.IsWithinRange(
	workerPosition: Vector3Like?,
	targetPosition: Vector3Like?,
	maxStuds: number
): boolean
	if workerPosition == nil or targetPosition == nil then
		return false
	end
	if not isFiniteNumber(maxStuds) or maxStuds <= 0 then
		return false
	end

	local dx = workerPosition.x - targetPosition.x
	local dy = workerPosition.y - targetPosition.y
	local dz = workerPosition.z - targetPosition.z
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	return distance <= maxStuds
end

function TinyfolkHaulLogisticsState.ResolvePickupAmount(baseAmount: number, haulYieldMultiplier: number?): number
	local safeBase = if isFiniteNumber(baseAmount) and baseAmount > 0 then baseAmount else 1
	local multiplier = if isFiniteNumber(haulYieldMultiplier) and (haulYieldMultiplier :: number) > 0
		then haulYieldMultiplier :: number
		else 1
	return math.max(1, math.floor(safeBase * multiplier + 0.5))
end

function TinyfolkHaulLogisticsState.ResolveDeliveryAmount(
	material: string,
	inTransitAmount: number,
	perStepByMaterial: { [string]: number }?
): number
	local safeInTransit = if isFiniteNumber(inTransitAmount) and inTransitAmount > 0 then inTransitAmount else 0
	if safeInTransit <= 0 then
		return 0
	end

	local configured = if type(perStepByMaterial) == "table" then perStepByMaterial[material] else nil
	if isFiniteNumber(configured) and (configured :: number) > 0 then
		return math.min(configured :: number, safeInTransit)
	end
	return math.min(2, safeInTransit)
end

function TinyfolkHaulLogisticsState.SortWorkersByUserId(workers: { WorkerSnapshot }): { WorkerSnapshot }
	local sorted = table.clone(workers)
	table.sort(sorted, function(left: WorkerSnapshot, right: WorkerSnapshot)
		return left.userId < right.userId
	end)
	return sorted
end

function TinyfolkHaulLogisticsState.BuildDebugSnapshot(input: {
	workers: { WorkerSnapshot }?,
	actions: { any }?,
	lastTickAt: number?,
	lastReason: string?,
}): any
	return {
		workerCount = if type(input.workers) == "table" then #input.workers else 0,
		actionCount = if type(input.actions) == "table" then #input.actions else 0,
		workers = input.workers,
		actions = input.actions,
		lastTickAt = input.lastTickAt,
		lastReason = input.lastReason,
	}
end

return TinyfolkHaulLogisticsState
