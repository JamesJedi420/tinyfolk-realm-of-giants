--!strict

local GrabState: any = {}

GrabState.States = {
	Free = "Free",
	GrabAttempted = "GrabAttempted",
	Carried = "Carried",
	Counterplay = "Counterplay",
	Released = "Released",
}

export type State = {
	state: string,
	grabbedAt: number?,
	carriedByUserId: number?,
	targetUserId: number?,
	cooldownEndsAt: number?,
	counterplayProgress: number,
	counterplayRequired: number,
	counterplayCooldownEndsAt: number?,
	releaseReason: string?,
	lastRejectReason: string?,
	lastAction: string?,
	source: string?,
	lastTransitionAt: number,
}

export type Snapshot = {
	state: string,
	grabbedAt: number?,
	carriedByUserId: number?,
	targetUserId: number?,
	cooldownEndsAt: number?,
	counterplayProgress: number,
	counterplayRequired: number,
	counterplayCooldownEndsAt: number?,
	releaseReason: string?,
	lastRejectReason: string?,
	lastAction: string?,
	source: string?,
	lastTransitionAt: number,
	isCarried: boolean,
}

export type Result = {
	accepted: boolean,
	reason: string,
	snapshot: Snapshot,
}

local function finiteNonNegative(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return fallback
	end
	return value
end

local function positiveInteger(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	local floored = math.floor(value)
	if floored <= 0 then
		return fallback
	end
	return floored
end

local function validUserId(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value % 1 == 0
end

function GrabState.New(now: number?): State
	local at = finiteNonNegative(now, 0)
	return {
		state = GrabState.States.Free,
		grabbedAt = nil,
		carriedByUserId = nil,
		targetUserId = nil,
		cooldownEndsAt = nil,
		counterplayProgress = 0,
		counterplayRequired = 3,
		counterplayCooldownEndsAt = nil,
		releaseReason = nil,
		lastRejectReason = nil,
		lastAction = nil,
		source = nil,
		lastTransitionAt = at,
	}
end

function GrabState.Snapshot(state: State): Snapshot
	local isCarried = state.state == GrabState.States.Carried or state.state == GrabState.States.Counterplay
	return {
		state = state.state,
		grabbedAt = state.grabbedAt,
		carriedByUserId = state.carriedByUserId,
		targetUserId = state.targetUserId,
		cooldownEndsAt = state.cooldownEndsAt,
		counterplayProgress = state.counterplayProgress,
		counterplayRequired = state.counterplayRequired,
		counterplayCooldownEndsAt = state.counterplayCooldownEndsAt,
		releaseReason = state.releaseReason,
		lastRejectReason = state.lastRejectReason,
		lastAction = state.lastAction,
		source = state.source,
		lastTransitionAt = state.lastTransitionAt,
		isCarried = isCarried,
	}
end

function GrabState.IsCarried(state: State): boolean
	return state.state == GrabState.States.Carried or state.state == GrabState.States.Counterplay
end

function GrabState.CanAttemptGrab(state: State, now: number): Result
	local at = finiteNonNegative(now, state.lastTransitionAt)
	if GrabState.IsCarried(state) then
		state.lastRejectReason = "already_carried"
		state.lastAction = "grab_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "already_carried", snapshot = GrabState.Snapshot(state) }
	end

	if type(state.cooldownEndsAt) == "number" and at < (state.cooldownEndsAt :: number) then
		state.lastRejectReason = "request_cooldown"
		state.lastAction = "grab_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "request_cooldown", snapshot = GrabState.Snapshot(state) }
	end

	state.state = GrabState.States.GrabAttempted
	state.lastRejectReason = nil
	state.lastAction = "grab_attempted"
	state.lastTransitionAt = at
	return { accepted = true, reason = "accepted", snapshot = GrabState.Snapshot(state) }
end

function GrabState.EnterCarried(
	state: State,
	params: {
		now: number,
		carriedByUserId: number?,
		targetUserId: number?,
		cooldownSeconds: number?,
		counterplayRequired: number?,
		source: string?,
	}
): Result
	local at = finiteNonNegative(params.now, state.lastTransitionAt)
	if not validUserId(params.carriedByUserId) then
		state.lastRejectReason = "carried_by_user_id_invalid"
		state.lastAction = "grab_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "carried_by_user_id_invalid", snapshot = GrabState.Snapshot(state) }
	end
	if not validUserId(params.targetUserId) then
		state.lastRejectReason = "target_user_id_invalid"
		state.lastAction = "grab_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "target_user_id_invalid", snapshot = GrabState.Snapshot(state) }
	end
	if GrabState.IsCarried(state) then
		state.lastRejectReason = "already_carried"
		state.lastAction = "grab_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "already_carried", snapshot = GrabState.Snapshot(state) }
	end

	local cooldownSeconds = finiteNonNegative(params.cooldownSeconds, 0)
	state.state = GrabState.States.Carried
	state.grabbedAt = at
	state.carriedByUserId = params.carriedByUserId
	state.targetUserId = params.targetUserId
	state.cooldownEndsAt = at + cooldownSeconds
	state.counterplayProgress = 0
	state.counterplayRequired = positiveInteger(params.counterplayRequired, 3)
	state.counterplayCooldownEndsAt = nil
	state.releaseReason = nil
	state.lastRejectReason = nil
	state.lastAction = "grab_accepted"
	state.source = params.source
	state.lastTransitionAt = at

	return { accepted = true, reason = "accepted", snapshot = GrabState.Snapshot(state) }
end

function GrabState.ApplyCounterplay(
	state: State,
	params: {
		now: number,
		progressDelta: number?,
		counterplayCooldownSeconds: number?,
	}
): Result
	local at = finiteNonNegative(params.now, state.lastTransitionAt)
	if not GrabState.IsCarried(state) then
		state.lastRejectReason = "not_carried"
		state.lastAction = "counterplay_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "not_carried", snapshot = GrabState.Snapshot(state) }
	end

	if type(state.counterplayCooldownEndsAt) == "number" and at < (state.counterplayCooldownEndsAt :: number) then
		state.lastRejectReason = "counterplay_cooldown"
		state.lastAction = "counterplay_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "counterplay_cooldown", snapshot = GrabState.Snapshot(state) }
	end

	local delta = finiteNonNegative(params.progressDelta, 1)
	state.counterplayProgress = math.min(state.counterplayProgress + delta, state.counterplayRequired)
	state.counterplayCooldownEndsAt = at + finiteNonNegative(params.counterplayCooldownSeconds, 0)
	state.state = GrabState.States.Counterplay
	state.lastRejectReason = nil
	state.lastAction = "counterplay_progress"
	state.lastTransitionAt = at

	if state.counterplayProgress >= state.counterplayRequired then
		state.state = GrabState.States.Released
		state.releaseReason = "counterplay_completed"
		state.carriedByUserId = nil
		state.targetUserId = nil
		state.lastAction = "released"
	end

	return { accepted = true, reason = "accepted", snapshot = GrabState.Snapshot(state) }
end

function GrabState.Release(
	state: State,
	params: {
		now: number,
		reason: string?,
	}
): Result
	local at = finiteNonNegative(params.now, state.lastTransitionAt)
	if not GrabState.IsCarried(state) then
		state.lastRejectReason = "not_carried"
		state.lastAction = "release_rejected"
		state.lastTransitionAt = at
		return { accepted = false, reason = "not_carried", snapshot = GrabState.Snapshot(state) }
	end

	state.state = GrabState.States.Released
	state.carriedByUserId = nil
	state.targetUserId = nil
	state.releaseReason = if type(params.reason) == "string" and params.reason ~= "" then params.reason else "released"
	state.lastRejectReason = nil
	state.lastAction = "released"
	state.lastTransitionAt = at

	return { accepted = true, reason = "accepted", snapshot = GrabState.Snapshot(state) }
end

function GrabState.CanPerformCarriedInteraction(state: State, interactionName: string): boolean
	if not GrabState.IsCarried(state) then
		return true
	end
	return interactionName == "debugInspect" or interactionName == "carriedCounterplay"
end

return GrabState
