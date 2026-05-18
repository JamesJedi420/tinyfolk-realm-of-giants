--!strict

local ContextualTaskProgressLogic = {}

export type State = {
	activeTaskId: string?,
	startedAt: number?,
	endsAt: number?,
	progressSeconds: number,
	totalDurationSeconds: number,
	lastUpdatedAt: number,
	majorRegressionEvents: number,
	regressingUntil: number?,
	objectiveState: string,
	lastReason: string?,
}

export type Snapshot = {
	isActive: boolean,
	activeTaskId: string?,
	startedAt: number?,
	endsAt: number?,
	progressRatio: number,
	progressSeconds: number,
	totalDurationSeconds: number,
	majorRegressionEvents: number,
	regressingUntil: number?,
	objectiveState: string,
	lastReason: string?,
}

export type Event = {
	eventType: string,
	taskId: string?,
	now: number,
	durationSeconds: number,
	regressionPerSecond: number?,
	stabilizationThresholdSeconds: number?,
	majorRegressionStepSeconds: number?,
	majorRegressionMaxEvents: number?,
	regressionWindowSeconds: number?,
}

export type Result = {
	accepted: boolean,
	reason: string,
	snapshot: Snapshot,
}

local function finite(value: any, fallback: number): number
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end

	return fallback
end

local function finiteNonNegative(value: any, fallback: number): number
	local resolved = finite(value, fallback)
	if resolved < 0 then
		return 0
	end

	return resolved
end

local function resolveProgressRatio(state: State, now: number): number
	local endsAt = state.endsAt
	if endsAt ~= nil and state.activeTaskId ~= nil and now >= endsAt then
		return 1
	end

	local duration = math.max(0.001, state.totalDurationSeconds)
	if state.progressSeconds <= 0 or duration <= 0 then
		return 0
	end

	local ratio = state.progressSeconds / duration
	if ratio < 0 then
		return 0
	end
	if ratio > 1 then
		return 1
	end

	return ratio
end

local function snapshot(state: State, now: number): Snapshot
	return {
		isActive = state.activeTaskId ~= nil,
		activeTaskId = state.activeTaskId,
		startedAt = state.startedAt,
		endsAt = state.endsAt,
		progressRatio = resolveProgressRatio(state, now),
		progressSeconds = state.progressSeconds,
		totalDurationSeconds = state.totalDurationSeconds,
		majorRegressionEvents = state.majorRegressionEvents,
		regressingUntil = state.regressingUntil,
		objectiveState = state.objectiveState,
		lastReason = state.lastReason,
	}
end

local function advanceToNow(
	state: State,
	now: number,
	durationSeconds: number,
	regressionPerSecond: number,
	stabilizationThresholdSeconds: number
)
	local elapsed = math.max(0, now - state.lastUpdatedAt)
	if elapsed <= 0 then
		state.lastUpdatedAt = now
		return
	end

	if state.activeTaskId ~= nil and state.objectiveState == "progressing" then
		state.totalDurationSeconds = durationSeconds
		state.progressSeconds = math.min(durationSeconds, state.progressSeconds + elapsed)
		if state.progressSeconds >= durationSeconds then
			state.endsAt = now
		else
			state.endsAt = now + (durationSeconds - state.progressSeconds)
		end
	end

	if state.objectiveState == "regressing" then
		if state.regressingUntil ~= nil and now >= (state.regressingUntil :: number) then
			state.objectiveState = "contested"
			state.regressingUntil = nil
		else
			local decayed =
				math.max(stabilizationThresholdSeconds, state.progressSeconds - (elapsed * regressionPerSecond))
			state.progressSeconds = decayed
			if decayed <= (stabilizationThresholdSeconds + 1e-6) then
				state.objectiveState = "contested"
				state.regressingUntil = nil
			end
		end
	end

	state.lastUpdatedAt = now
end

function ContextualTaskProgressLogic.New(): State
	return {
		activeTaskId = nil,
		startedAt = nil,
		endsAt = nil,
		progressSeconds = 0,
		totalDurationSeconds = 0,
		lastUpdatedAt = 0,
		majorRegressionEvents = 0,
		regressingUntil = nil,
		objectiveState = "idle",
		lastReason = nil,
	}
end

function ContextualTaskProgressLogic.Resolve(state: State, event: Event): Result
	local now = finite(event.now, 0)
	local durationSeconds = finiteNonNegative(event.durationSeconds, 0)
	local regressionPerSecond = finiteNonNegative(event.regressionPerSecond, 0.4)
	local stabilizationThresholdSeconds = finiteNonNegative(event.stabilizationThresholdSeconds, 0.4)
	local majorRegressionStepSeconds = finiteNonNegative(event.majorRegressionStepSeconds, 0.8)
	local majorRegressionMaxEvents = math.floor(finiteNonNegative(event.majorRegressionMaxEvents, 2))
	local regressionWindowSeconds = finiteNonNegative(event.regressionWindowSeconds, 3)
	local eventType = event.eventType
	local taskId = event.taskId

	advanceToNow(state, now, durationSeconds, regressionPerSecond, stabilizationThresholdSeconds)

	if type(taskId) ~= "string" or taskId == "" then
		state.lastReason = "invalid_task_id"
		return {
			accepted = false,
			reason = "invalid_task_id",
			snapshot = snapshot(state, now),
		}
	end

	if eventType == "begin" then
		if state.objectiveState == "blocked" then
			state.lastReason = "blocked"
			return {
				accepted = false,
				reason = "blocked",
				snapshot = snapshot(state, now),
			}
		end

		if state.activeTaskId ~= nil and state.activeTaskId ~= taskId then
			state.activeTaskId = nil
			state.startedAt = nil
			state.endsAt = nil
			state.objectiveState = "idle"
		end

		if state.activeTaskId == taskId then
			state.lastReason = "already_active"
			return {
				accepted = false,
				reason = "already_active",
				snapshot = snapshot(state, now),
			}
		end

		state.activeTaskId = taskId
		state.startedAt = now
		state.totalDurationSeconds = durationSeconds
		state.endsAt = now + math.max(0, durationSeconds - state.progressSeconds)
		state.objectiveState = "progressing"
		local beginReason = if state.progressSeconds > 0 then "resumed" else "began"
		state.lastReason = beginReason
		return {
			accepted = true,
			reason = beginReason,
			snapshot = snapshot(state, now),
		}
	end

	if eventType == "cancel" then
		if state.activeTaskId == nil or state.activeTaskId ~= taskId then
			state.lastReason = "not_active"
			return {
				accepted = false,
				reason = "not_active",
				snapshot = snapshot(state, now),
			}
		end

		state.activeTaskId = nil
		state.startedAt = nil
		state.endsAt = nil
		if state.objectiveState == "progressing" then
			state.objectiveState = "idle"
		end
		state.lastReason = "canceled"
		return {
			accepted = true,
			reason = "canceled",
			snapshot = snapshot(state, now),
		}
	end

	if eventType == "complete" then
		if state.activeTaskId == nil or state.activeTaskId ~= taskId then
			state.lastReason = "not_active"
			return {
				accepted = false,
				reason = "not_active",
				snapshot = snapshot(state, now),
			}
		end

		if state.endsAt ~= nil and now < state.endsAt then
			state.lastReason = "not_ready"
			return {
				accepted = false,
				reason = "not_ready",
				snapshot = snapshot(state, now),
			}
		end

		state.activeTaskId = nil
		state.startedAt = nil
		state.endsAt = nil
		state.progressSeconds = durationSeconds
		state.totalDurationSeconds = durationSeconds
		state.regressingUntil = nil
		state.objectiveState = "completed"
		state.lastReason = "completed"
		return {
			accepted = true,
			reason = "completed",
			snapshot = snapshot(state, now),
		}
	end

	if eventType == "block" then
		state.activeTaskId = nil
		state.startedAt = nil
		state.endsAt = nil
		state.regressingUntil = nil
		state.objectiveState = "blocked"
		state.lastReason = "blocked"
		return {
			accepted = true,
			reason = "blocked",
			snapshot = snapshot(state, now),
		}
	end

	if eventType == "unblock" then
		if state.objectiveState ~= "blocked" then
			state.lastReason = "not_blocked"
			return {
				accepted = false,
				reason = "not_blocked",
				snapshot = snapshot(state, now),
			}
		end

		state.objectiveState = "idle"
		state.lastReason = "unblocked"
		return {
			accepted = true,
			reason = "unblocked",
			snapshot = snapshot(state, now),
		}
	end

	if eventType == "disrupt" then
		if state.objectiveState == "completed" then
			state.lastReason = "already_completed"
			return {
				accepted = false,
				reason = "already_completed",
				snapshot = snapshot(state, now),
			}
		end

		if state.activeTaskId == nil and state.progressSeconds <= 0 then
			state.lastReason = "not_active"
			return {
				accepted = false,
				reason = "not_active",
				snapshot = snapshot(state, now),
			}
		end

		if state.majorRegressionEvents >= majorRegressionMaxEvents then
			state.lastReason = "regression_cap_reached"
			return {
				accepted = false,
				reason = "regression_cap_reached",
				snapshot = snapshot(state, now),
			}
		end

		state.activeTaskId = nil
		state.startedAt = nil
		state.endsAt = nil
		state.progressSeconds =
			math.max(stabilizationThresholdSeconds, state.progressSeconds - majorRegressionStepSeconds)
		state.regressingUntil = now + regressionWindowSeconds
		state.majorRegressionEvents += 1
		state.objectiveState = "regressing"
		state.lastReason = "disrupted"
		return {
			accepted = true,
			reason = "disrupted",
			snapshot = snapshot(state, now),
		}
	end

	if eventType == "tick" then
		state.lastReason = "tick"
		return {
			accepted = true,
			reason = "tick",
			snapshot = snapshot(state, now),
		}
	end

	state.lastReason = "invalid_event"
	return {
		accepted = false,
		reason = "invalid_event",
		snapshot = snapshot(state, now),
	}
end

return ContextualTaskProgressLogic
