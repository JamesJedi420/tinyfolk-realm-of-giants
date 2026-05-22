--!strict

local RescueContractState = {}

export type RescueContract = {
	rescuerUserId: number,
	targetUserId: number,
	targetRealmOwnerUserId: number,
	entryRouteId: string,
	entryRouteKind: string,
	startedAt: number,
	expiresAt: number,
	isAccelerated: boolean,
}

export type State = {
	contractsByRescuer: { [number]: RescueContract? },
	rescuerByTarget: { [number]: number? },
	lastReason: string?,
}

export type RequestInput = {
	now: number,
	rescuerUserId: number,
	targetUserId: number,
	rescuerRole: string?,
	targetRole: string?,
	rescuerAlive: boolean,
	targetDowned: boolean,
	targetCarried: boolean,
	targetProtected: boolean,
	inRange: boolean,
	targetRealmOwnerUserId: number?,
	entryRouteId: string?,
	entryRouteKind: string?,
	rescueWindowSeconds: number,
	accelerationActive: boolean?,
	accelerationWindowBonusSeconds: number?,
}

export type CompleteInput = {
	now: number,
	rescuerUserId: number,
	targetUserId: number,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	state: State,
	contract: RescueContract?,
}

local function validNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function validNow(now: any): boolean
	if not validNumber(now) then
		return false
	end
	return now >= 0
end

local function validPositiveInteger(value: any): boolean
	if not validNumber(value) then
		return false
	end
	return value > 0 and value % 1 == 0
end

local function validNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function cloneState(state: State): State
	local contractsByRescuer: { [number]: RescueContract? } = {}
	for rescuerUserId, contract in pairs(state.contractsByRescuer) do
		if contract ~= nil then
			contractsByRescuer[rescuerUserId] = {
				rescuerUserId = contract.rescuerUserId,
				targetUserId = contract.targetUserId,
				targetRealmOwnerUserId = contract.targetRealmOwnerUserId,
				entryRouteId = contract.entryRouteId,
				entryRouteKind = contract.entryRouteKind,
				startedAt = contract.startedAt,
				expiresAt = contract.expiresAt,
				isAccelerated = contract.isAccelerated,
			}
		end
	end

	local rescuerByTarget: { [number]: number? } = table.clone(state.rescuerByTarget)

	return {
		contractsByRescuer = contractsByRescuer,
		rescuerByTarget = rescuerByTarget,
		lastReason = state.lastReason,
	}
end

function RescueContractState.NewState(): State
	return {
		contractsByRescuer = {},
		rescuerByTarget = {},
		lastReason = nil,
	}
end

local function pruneExpiredInPlace(nextState: State, now: number)
	local expiredRescuers: { number } = {}

	for rescuerUserId, contract in pairs(nextState.contractsByRescuer) do
		if contract ~= nil then
			if contract.expiresAt <= now then
				table.insert(expiredRescuers, rescuerUserId)
			end
		end
	end

	for _, rescuerUserId in ipairs(expiredRescuers) do
		local contract = nextState.contractsByRescuer[rescuerUserId]
		if contract ~= nil then
			nextState.rescuerByTarget[contract.targetUserId] = nil
			nextState.contractsByRescuer[rescuerUserId] = nil
		end
	end
end

function RescueContractState.PruneExpired(state: State, now: number): State
	if not validNow(now) then
		return cloneState(state)
	end

	local nextState = cloneState(state)
	pruneExpiredInPlace(nextState, now)
	return nextState
end

function RescueContractState.ResolveRequest(state: State, input: RequestInput): TransitionResult
	local nextState = cloneState(state)

	if not validNow(input.now) then
		nextState.lastReason = "invalid_now"
		return { accepted = false, reason = "invalid_now", state = nextState, contract = nil }
	end

	pruneExpiredInPlace(nextState, input.now)

	if input.rescuerRole ~= "Tinyfolk" then
		nextState.lastReason = "rescuer_not_tinyfolk"
		return { accepted = false, reason = "rescuer_not_tinyfolk", state = nextState, contract = nil }
	end

	if input.targetRole ~= "Tinyfolk" then
		nextState.lastReason = "target_not_tinyfolk"
		return { accepted = false, reason = "target_not_tinyfolk", state = nextState, contract = nil }
	end

	if input.rescuerAlive ~= true then
		nextState.lastReason = "rescuer_not_alive"
		return { accepted = false, reason = "rescuer_not_alive", state = nextState, contract = nil }
	end

	if input.rescuerUserId == input.targetUserId then
		nextState.lastReason = "self_rescue_not_allowed"
		return { accepted = false, reason = "self_rescue_not_allowed", state = nextState, contract = nil }
	end

	if input.targetDowned ~= true then
		nextState.lastReason = "target_not_downed"
		return { accepted = false, reason = "target_not_downed", state = nextState, contract = nil }
	end

	if input.targetCarried == true then
		nextState.lastReason = "target_carried"
		return { accepted = false, reason = "target_carried", state = nextState, contract = nil }
	end

	if input.targetProtected == true then
		nextState.lastReason = "target_safe_zone_protected"
		return { accepted = false, reason = "target_safe_zone_protected", state = nextState, contract = nil }
	end

	if input.inRange ~= true then
		nextState.lastReason = "target_out_of_range"
		return { accepted = false, reason = "target_out_of_range", state = nextState, contract = nil }
	end

	if not validPositiveInteger(input.targetRealmOwnerUserId) then
		nextState.lastReason = "target_realm_owner_user_id_invalid"
		return { accepted = false, reason = "target_realm_owner_user_id_invalid", state = nextState, contract = nil }
	end

	if not validNonEmptyString(input.entryRouteId) then
		nextState.lastReason = "rescue_entry_route_id_invalid"
		return { accepted = false, reason = "rescue_entry_route_id_invalid", state = nextState, contract = nil }
	end

	if not validNonEmptyString(input.entryRouteKind) then
		nextState.lastReason = "rescue_entry_route_kind_invalid"
		return { accepted = false, reason = "rescue_entry_route_kind_invalid", state = nextState, contract = nil }
	end

	if nextState.contractsByRescuer[input.rescuerUserId] ~= nil then
		nextState.lastReason = "rescuer_contract_active"
		return { accepted = false, reason = "rescuer_contract_active", state = nextState, contract = nil }
	end

	if nextState.rescuerByTarget[input.targetUserId] ~= nil then
		nextState.lastReason = "target_contract_active"
		return { accepted = false, reason = "target_contract_active", state = nextState, contract = nil }
	end

	if nextState.rescuerByTarget[input.rescuerUserId] ~= nil then
		nextState.lastReason = "participant_contract_active"
		return { accepted = false, reason = "participant_contract_active", state = nextState, contract = nil }
	end

	if nextState.contractsByRescuer[input.targetUserId] ~= nil then
		nextState.lastReason = "participant_contract_active"
		return { accepted = false, reason = "participant_contract_active", state = nextState, contract = nil }
	end

	local rescueWindowSeconds: number = if validNumber(input.rescueWindowSeconds)
			and input.rescueWindowSeconds > 0
		then input.rescueWindowSeconds
		else 0
	if rescueWindowSeconds <= 0 then
		nextState.lastReason = "rescue_window_invalid"
		return { accepted = false, reason = "rescue_window_invalid", state = nextState, contract = nil }
	end

	local accelerationBonusSeconds = 0
	local bonusInput = input.accelerationWindowBonusSeconds
	if type(bonusInput) == "number" and validNumber(bonusInput) and bonusInput > 0 then
		accelerationBonusSeconds = bonusInput
	end

	local isAccelerated = false
	if input.accelerationActive == true and accelerationBonusSeconds > 0 then
		isAccelerated = true
	end
	if isAccelerated then
		rescueWindowSeconds = rescueWindowSeconds + accelerationBonusSeconds
	end

	local contract: RescueContract = {
		rescuerUserId = input.rescuerUserId,
		targetUserId = input.targetUserId,
		targetRealmOwnerUserId = input.targetRealmOwnerUserId :: number,
		entryRouteId = input.entryRouteId :: string,
		entryRouteKind = input.entryRouteKind :: string,
		startedAt = input.now,
		expiresAt = input.now + rescueWindowSeconds,
		isAccelerated = isAccelerated,
	}

	nextState.contractsByRescuer[input.rescuerUserId] = contract
	nextState.rescuerByTarget[input.targetUserId] = input.rescuerUserId
	nextState.lastReason = "accepted"

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		contract = contract,
	}
end

function RescueContractState.ResolveComplete(state: State, input: CompleteInput): TransitionResult
	local nextState = cloneState(state)

	if not validNow(input.now) then
		nextState.lastReason = "invalid_now"
		return { accepted = false, reason = "invalid_now", state = nextState, contract = nil }
	end

	pruneExpiredInPlace(nextState, input.now)

	local contract = nextState.contractsByRescuer[input.rescuerUserId]
	if contract == nil then
		nextState.lastReason = "rescuer_contract_missing"
		return { accepted = false, reason = "rescuer_contract_missing", state = nextState, contract = nil }
	end

	if contract.targetUserId ~= input.targetUserId then
		nextState.lastReason = "target_mismatch"
		return { accepted = false, reason = "target_mismatch", state = nextState, contract = nil }
	end

	nextState.contractsByRescuer[input.rescuerUserId] = nil
	nextState.rescuerByTarget[input.targetUserId] = nil
	nextState.lastReason = "rescued"

	return {
		accepted = true,
		reason = "rescued",
		state = nextState,
		contract = contract,
	}
end

function RescueContractState.GetRescuerContract(state: State, rescuerUserId: number): RescueContract?
	return state.contractsByRescuer[rescuerUserId]
end

function RescueContractState.GetContracts(state: State): { RescueContract }
	local contracts: { RescueContract } = {}
	for _, contract in pairs(state.contractsByRescuer) do
		if contract ~= nil then
			table.insert(contracts, {
				rescuerUserId = contract.rescuerUserId,
				targetUserId = contract.targetUserId,
				targetRealmOwnerUserId = contract.targetRealmOwnerUserId,
				entryRouteId = contract.entryRouteId,
				entryRouteKind = contract.entryRouteKind,
				startedAt = contract.startedAt,
				expiresAt = contract.expiresAt,
				isAccelerated = contract.isAccelerated,
			})
		end
	end

	table.sort(contracts, function(a: RescueContract, b: RescueContract)
		if a.rescuerUserId == b.rescuerUserId then
			return a.targetUserId < b.targetUserId
		end
		return a.rescuerUserId < b.rescuerUserId
	end)

	return contracts
end

function RescueContractState.RemovePlayer(state: State, userId: number): State
	local nextState = cloneState(state)

	local removedTargetIds: { [number]: boolean } = {}
	for rescuerUserId, contract in pairs(nextState.contractsByRescuer) do
		if contract ~= nil then
			if rescuerUserId == userId or contract.targetUserId == userId then
				removedTargetIds[contract.targetUserId] = true
				nextState.contractsByRescuer[rescuerUserId] = nil
			end
		end
	end

	for targetUserId, rescuerUserId in pairs(nextState.rescuerByTarget) do
		if targetUserId == userId or rescuerUserId == userId or removedTargetIds[targetUserId] == true then
			nextState.rescuerByTarget[targetUserId] = nil
		end
	end

	return nextState
end

return RescueContractState
