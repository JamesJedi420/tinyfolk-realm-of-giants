--!strict

local DownedState: any = {}

DownedState.Status = {
	Normal = "Normal",
	Downed = "Downed",
	SelfRecoveryCapped = "SelfRecoveryCapped",
	Recovered = "Recovered",
	SafeResolved = "SafeResolved",
}

local DEFAULT_INTERACTION_MASK = {
	escapeAttempt = false,
	objectiveInteraction = false,
	toolUse = false,
	routeTraversal = false,
	throughGapReach = false,
	rescueAction = false,
	debugInspect = true,
}

export type InteractionMask = {
	[string]: boolean,
}

export type State = {
	status: string,
	downedAt: number?,
	expiresAt: number?,
	selfRecoveryProgress: number,
	selfRecoveryCap: number,
	movementMultiplier: number,
	interactionMask: InteractionMask,
	source: string?,
	reason: string?,
	lastTransitionAt: number,
}

export type Snapshot = {
	status: string,
	downedAt: number?,
	expiresAt: number?,
	selfRecoveryProgress: number,
	selfRecoveryCap: number,
	movementMultiplier: number,
	interactionMask: InteractionMask,
	source: string?,
	reason: string?,
	lastTransitionAt: number,
	isDowned: boolean,
	carryEligibleMarker: boolean,
}

export type EnterParams = {
	now: number,
	durationSeconds: number,
	role: string,
	source: string,
	reason: string?,
	selfRecoveryCap: number,
	movementMultiplier: number,
	interactionMask: InteractionMask?,
	safeZoneProtected: boolean,
	validSources: { [string]: boolean },
}

export type Result = {
	accepted: boolean,
	reason: string,
	snapshot: Snapshot,
}

local function cloneMask(mask: InteractionMask?): InteractionMask
	local output: InteractionMask = table.clone(DEFAULT_INTERACTION_MASK)
	if type(mask) == "table" then
		for key, value in pairs(mask :: InteractionMask) do
			output[key] = value == true
		end
	end
	return output
end

local function finiteNonNegative(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return fallback
	end
	return value
end

local function finiteUnit(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function isTinyfolk(role: string): boolean
	return role == "Tinyfolk"
end

function DownedState.New(now: number?): State
	local at = finiteNonNegative(now, 0)
	return {
		status = DownedState.Status.Normal,
		downedAt = nil,
		expiresAt = nil,
		selfRecoveryProgress = 0,
		selfRecoveryCap = 0.5,
		movementMultiplier = 0.35,
		interactionMask = cloneMask(nil),
		source = nil,
		reason = nil,
		lastTransitionAt = at,
	}
end

function DownedState.Snapshot(state: State): Snapshot
	local status = state.status
	local isDowned = status == DownedState.Status.Downed or status == DownedState.Status.SelfRecoveryCapped
	return {
		status = status,
		downedAt = state.downedAt,
		expiresAt = state.expiresAt,
		selfRecoveryProgress = state.selfRecoveryProgress,
		selfRecoveryCap = state.selfRecoveryCap,
		movementMultiplier = state.movementMultiplier,
		interactionMask = cloneMask(state.interactionMask),
		source = state.source,
		reason = state.reason,
		lastTransitionAt = state.lastTransitionAt,
		isDowned = isDowned,
		carryEligibleMarker = isDowned,
	}
end

function DownedState.IsDowned(state: State): boolean
	return state.status == DownedState.Status.Downed or state.status == DownedState.Status.SelfRecoveryCapped
end

function DownedState.CanPerformInteraction(state: State, interactionName: string): boolean
	if not DownedState.IsDowned(state) then
		return true
	end
	local allowed = state.interactionMask[interactionName]
	return allowed == true
end

function DownedState.Enter(state: State, params: EnterParams): Result
	if not isTinyfolk(params.role) then
		return {
			accepted = false,
			reason = "target_not_tinyfolk",
			snapshot = DownedState.Snapshot(state),
		}
	end

	if type(params.source) ~= "string" or params.source == "" or params.validSources[params.source] ~= true then
		return {
			accepted = false,
			reason = "source_invalid",
			snapshot = DownedState.Snapshot(state),
		}
	end

	if params.safeZoneProtected == true then
		return {
			accepted = false,
			reason = "target_in_safe_zone",
			snapshot = DownedState.Snapshot(state),
		}
	end

	if DownedState.IsDowned(state) then
		return {
			accepted = false,
			reason = "already_downed",
			snapshot = DownedState.Snapshot(state),
		}
	end

	local at = finiteNonNegative(params.now, state.lastTransitionAt)
	local duration = finiteNonNegative(params.durationSeconds, 30)
	state.status = DownedState.Status.Downed
	state.downedAt = at
	state.expiresAt = at + duration
	state.selfRecoveryProgress = 0
	state.selfRecoveryCap = finiteUnit(params.selfRecoveryCap, 0.5)
	state.movementMultiplier = finiteUnit(params.movementMultiplier, 0.35)
	state.interactionMask = cloneMask(params.interactionMask)
	state.source = params.source
	state.reason = params.reason
	state.lastTransitionAt = at

	return {
		accepted = true,
		reason = "accepted",
		snapshot = DownedState.Snapshot(state),
	}
end

function DownedState.SelfRecover(state: State, now: number, progressDelta: number): Result
	if not DownedState.IsDowned(state) then
		return {
			accepted = false,
			reason = "not_downed",
			snapshot = DownedState.Snapshot(state),
		}
	end

	local delta = finiteNonNegative(progressDelta, 0)
	local nextProgress = state.selfRecoveryProgress + delta
	if nextProgress >= state.selfRecoveryCap then
		nextProgress = state.selfRecoveryCap
		state.status = DownedState.Status.SelfRecoveryCapped
	end

	state.selfRecoveryProgress = nextProgress
	state.lastTransitionAt = finiteNonNegative(now, state.lastTransitionAt)

	return {
		accepted = true,
		reason = "accepted",
		snapshot = DownedState.Snapshot(state),
	}
end

function DownedState.Tick(state: State, now: number): Result
	if not DownedState.IsDowned(state) then
		return {
			accepted = false,
			reason = "not_downed",
			snapshot = DownedState.Snapshot(state),
		}
	end

	local at = finiteNonNegative(now, state.lastTransitionAt)
	if state.expiresAt ~= nil and at >= state.expiresAt then
		state.status = DownedState.Status.SafeResolved
		state.lastTransitionAt = at
	end

	return {
		accepted = true,
		reason = "accepted",
		snapshot = DownedState.Snapshot(state),
	}
end

return DownedState
