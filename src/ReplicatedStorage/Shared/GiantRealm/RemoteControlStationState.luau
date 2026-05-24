--!strict

local RemoteControlStationState = {}

export type Config = {
	MaxEnergy: number,
	InitialEnergy: number,
	PressureEnergyCost: number,
	EnergyRecoverySeconds: number,
	EnergyRecoveryAmount: number,
	SabotageEnergyDrain: number,
	SabotageLockoutSeconds: number,
	BarrierWarningSeconds: number,
	BarrierActiveSeconds: number,
	BarrierState: { [string]: string },
}

export type StationState = {
	stationId: string,
	zoneId: string,
	energy: number,
	lastEnergyRecoveredAt: number,
	activeOperatorUserId: number?,
	lockoutEndsAt: number?,
}

export type BarrierRecord = {
	stationId: string,
	routeId: string,
	createdByUserId: number,
	warningStartedAt: number,
	warningEndsAt: number,
	activeStartsAt: number,
	activeEndsAt: number,
	expiresAt: number,
}

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonNegativeNumber(value: any): boolean
	return finiteNumber(value) and value >= 0
end

local function positiveNumber(value: any, fallback: number): number
	if not finiteNumber(value) or value < 0 then
		return fallback
	end
	return value
end

local function clamp(value: number, minValue: number, maxValue: number): number
	return math.max(minValue, math.min(maxValue, value))
end

function RemoteControlStationState.NewStation(
	config: Config,
	stationId: string,
	zoneId: string,
	now: number
): StationState
	local maxEnergy = positiveNumber(config.MaxEnergy, 0)
	local initialEnergy = clamp(positiveNumber(config.InitialEnergy, maxEnergy), 0, maxEnergy)
	return {
		stationId = stationId,
		zoneId = zoneId,
		energy = initialEnergy,
		lastEnergyRecoveredAt = if nonNegativeNumber(now) then now else 0,
		activeOperatorUserId = nil,
		lockoutEndsAt = nil,
	}
end

function RemoteControlStationState.RecoverEnergy(config: Config, state: StationState, now: number): StationState
	if not nonNegativeNumber(now) then
		return state
	end
	local interval = positiveNumber(config.EnergyRecoverySeconds, 0)
	local amount = positiveNumber(config.EnergyRecoveryAmount, 0)
	local maxEnergy = positiveNumber(config.MaxEnergy, 0)
	if interval <= 0 or amount <= 0 or state.energy >= maxEnergy then
		state.lastEnergyRecoveredAt = now
		return state
	end

	local elapsed = now - state.lastEnergyRecoveredAt
	if elapsed < interval then
		return state
	end

	local steps = math.floor(elapsed / interval)
	state.energy = clamp(state.energy + (steps * amount), 0, maxEnergy)
	state.lastEnergyRecoveredAt += steps * interval
	return state
end

function RemoteControlStationState.Enter(state: StationState, userId: any, now: number): any
	if type(userId) ~= "number" then
		return { accepted = false, reason = "user_id_invalid", state = state }
	end
	if state.lockoutEndsAt ~= nil and nonNegativeNumber(now) and now < state.lockoutEndsAt then
		return { accepted = false, reason = "station_locked_out", state = state }
	end
	if state.activeOperatorUserId ~= nil and state.activeOperatorUserId ~= userId then
		return { accepted = false, reason = "station_occupied", state = state }
	end
	state.activeOperatorUserId = userId
	return { accepted = true, reason = "accepted", state = state }
end

function RemoteControlStationState.Exit(state: StationState, userId: any): any
	if type(userId) ~= "number" then
		return { accepted = false, reason = "user_id_invalid", state = state }
	end
	if state.activeOperatorUserId ~= nil and state.activeOperatorUserId ~= userId then
		return { accepted = false, reason = "station_occupied_by_other", state = state }
	end
	state.activeOperatorUserId = nil
	return { accepted = true, reason = "accepted", state = state }
end

function RemoteControlStationState.ResolveBarrierState(config: Config, record: BarrierRecord?, now: number): string
	if record == nil then
		return config.BarrierState.Idle
	end
	if not nonNegativeNumber(now) then
		return config.BarrierState.Expired
	end
	if now < record.warningEndsAt then
		return config.BarrierState.Warning
	end
	if now < record.activeEndsAt then
		return config.BarrierState.Active
	end
	return config.BarrierState.Expired
end

function RemoteControlStationState.GetBarrierSnapshot(config: Config, record: BarrierRecord?, now: number): any
	local state = RemoteControlStationState.ResolveBarrierState(config, record, now)
	if record == nil then
		return { state = state }
	end
	return {
		state = state,
		stationId = record.stationId,
		routeId = record.routeId,
		createdByUserId = record.createdByUserId,
		warningStartedAt = record.warningStartedAt,
		warningEndsAt = record.warningEndsAt,
		activeStartsAt = record.activeStartsAt,
		activeEndsAt = record.activeEndsAt,
		expiresAt = record.expiresAt,
	}
end

function RemoteControlStationState.CreateBarrier(config: Config, state: StationState, params: any): any
	local now = params.now
	if not nonNegativeNumber(now) then
		return { accepted = false, reason = "invalid_now", state = state, record = params.existingRecord }
	end
	if type(params.routeId) ~= "string" or params.routeId == "" then
		return { accepted = false, reason = "route_id_invalid", state = state, record = params.existingRecord }
	end
	if type(params.createdByUserId) ~= "number" then
		return { accepted = false, reason = "created_by_user_id_invalid", state = state, record = params.existingRecord }
	end
	if state.activeOperatorUserId ~= params.createdByUserId then
		return { accepted = false, reason = "operator_not_active", state = state, record = params.existingRecord }
	end
	if state.lockoutEndsAt ~= nil and now < state.lockoutEndsAt then
		return { accepted = false, reason = "station_locked_out", state = state, record = params.existingRecord }
	end
	local existingState = RemoteControlStationState.ResolveBarrierState(config, params.existingRecord, now)
	if existingState == config.BarrierState.Warning then
		return { accepted = false, reason = "remote_barrier_warning", state = state, record = params.existingRecord }
	end
	if existingState == config.BarrierState.Active then
		return { accepted = false, reason = "remote_barrier_active", state = state, record = params.existingRecord }
	end

	local cost = positiveNumber(config.PressureEnergyCost, 0)
	if state.energy < cost then
		return { accepted = false, reason = "station_energy_empty", state = state, record = params.existingRecord }
	end

	state.energy -= cost
	local warningSeconds = positiveNumber(config.BarrierWarningSeconds, 0)
	local activeSeconds = positiveNumber(config.BarrierActiveSeconds, 0)
	local warningEndsAt = now + warningSeconds
	local activeEndsAt = warningEndsAt + activeSeconds
	local record: BarrierRecord = {
		stationId = state.stationId,
		routeId = params.routeId,
		createdByUserId = params.createdByUserId,
		warningStartedAt = now,
		warningEndsAt = warningEndsAt,
		activeStartsAt = warningEndsAt,
		activeEndsAt = activeEndsAt,
		expiresAt = activeEndsAt,
	}
	return { accepted = true, reason = "accepted", state = state, record = record }
end

function RemoteControlStationState.ApplySabotage(config: Config, state: StationState, userId: any, now: number): any
	if type(userId) ~= "number" then
		return { accepted = false, reason = "user_id_invalid", state = state }
	end
	if not nonNegativeNumber(now) then
		return { accepted = false, reason = "invalid_now", state = state }
	end
	if state.lockoutEndsAt ~= nil and now < state.lockoutEndsAt then
		return { accepted = false, reason = "station_locked_out", state = state }
	end
	state.energy =
		clamp(state.energy - positiveNumber(config.SabotageEnergyDrain, 0), 0, positiveNumber(config.MaxEnergy, 0))
	state.activeOperatorUserId = nil
	state.lockoutEndsAt = now + positiveNumber(config.SabotageLockoutSeconds, 0)
	return { accepted = true, reason = "accepted", state = state }
end

function RemoteControlStationState.GetStationSnapshot(state: StationState): any
	return {
		stationId = state.stationId,
		zoneId = state.zoneId,
		energy = state.energy,
		lastEnergyRecoveredAt = state.lastEnergyRecoveredAt,
		activeOperatorUserId = state.activeOperatorUserId,
		lockoutEndsAt = state.lockoutEndsAt,
	}
end

return RemoteControlStationState
