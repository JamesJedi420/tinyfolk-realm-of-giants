--!strict

local DefensivePropState = {}

export type Config = {
	Status: { [string]: string },
	BarrierStartupSeconds: number,
	BarrierActiveSeconds: number,
	ObstacleDurationSeconds: number,
	BreakDurationSeconds: number,
	ResetDurationSeconds: number,
	DropRechargeSeconds: number,
	MaxActivePropsPerTinyfolk: number,
	BarrierContactStaggerSeconds: number?,
	BarrierContactCooldownSeconds: number?,
	PropTypes: {
		[string]: {
			displayName: string,
			barrierStartupSeconds: number?,
			barrierActiveSeconds: number?,
			obstacleDurationSeconds: number?,
			breakDurationSeconds: number?,
			barrierContactStaggerSeconds: number?,
		},
	},
}

export type RescueDropContext = {
	hasActiveRescueContract: boolean,
	downedAllyInZone: boolean,
}

export type PropRecord = {
	propId: string,
	propType: string,
	zoneId: string,
	enabled: boolean,
	droppedByUserId: number?,
	droppedAt: number?,
	barrierStartupEndsAt: number?,
	barrierActiveEndsAt: number?,
	obstacleExpiresAt: number?,
	breakStartedAt: number?,
	breakEndsAt: number?,
	brokenByUserId: number?,
	brokenAt: number?,
	resetEndsAt: number?,
	lastDropAt: number?,
}

export type Snapshot = {
	propId: string?,
	propType: string?,
	zoneId: string?,
	state: string,
	enabled: boolean?,
	droppedByUserId: number?,
	droppedAt: number?,
	barrierStartupEndsAt: number?,
	barrierActiveEndsAt: number?,
	obstacleExpiresAt: number?,
	breakStartedAt: number?,
	breakEndsAt: number?,
	brokenByUserId: number?,
	brokenAt: number?,
	resetEndsAt: number?,
	breakInProgress: boolean?,
	blocksGiantMacroRoutes: boolean?,
}

local function positiveNumber(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return fallback
	end
	return value
end

local function validNow(now: any): boolean
	return type(now) == "number" and now == now and now ~= math.huge and now ~= -math.huge and now >= 0
end

local function cloneRecord(record: PropRecord): PropRecord
	return {
		propId = record.propId,
		propType = record.propType,
		zoneId = record.zoneId,
		enabled = record.enabled,
		droppedByUserId = record.droppedByUserId,
		droppedAt = record.droppedAt,
		barrierStartupEndsAt = record.barrierStartupEndsAt,
		barrierActiveEndsAt = record.barrierActiveEndsAt,
		obstacleExpiresAt = record.obstacleExpiresAt,
		breakStartedAt = record.breakStartedAt,
		breakEndsAt = record.breakEndsAt,
		brokenByUserId = record.brokenByUserId,
		brokenAt = record.brokenAt,
		resetEndsAt = record.resetEndsAt,
		lastDropAt = record.lastDropAt,
	}
end

function DefensivePropState.NewRecord(propId: string, propType: string, zoneId: string, enabled: boolean): PropRecord
	return {
		propId = propId,
		propType = propType,
		zoneId = zoneId,
		enabled = enabled,
		droppedByUserId = nil,
		droppedAt = nil,
		barrierStartupEndsAt = nil,
		barrierActiveEndsAt = nil,
		obstacleExpiresAt = nil,
		breakStartedAt = nil,
		breakEndsAt = nil,
		brokenByUserId = nil,
		brokenAt = nil,
		resetEndsAt = nil,
		lastDropAt = nil,
	}
end

function DefensivePropState.ClearObstacleTimestamps(record: PropRecord): PropRecord
	local nextRecord = cloneRecord(record)
	nextRecord.droppedByUserId = nil
	nextRecord.droppedAt = nil
	nextRecord.barrierStartupEndsAt = nil
	nextRecord.barrierActiveEndsAt = nil
	nextRecord.obstacleExpiresAt = nil
	nextRecord.breakStartedAt = nil
	nextRecord.breakEndsAt = nil
	nextRecord.brokenByUserId = nil
	nextRecord.brokenAt = nil
	return nextRecord
end

function DefensivePropState.ResolveStatus(config: Config, record: PropRecord?, now: number): string
	if record == nil then
		return config.Status.Ready
	end
	if not validNow(now) then
		return config.Status.Disabled
	end
	if record.enabled ~= true then
		return config.Status.Disabled
	end
	if record.brokenAt ~= nil and record.resetEndsAt == nil then
		return config.Status.Broken
	end
	if record.resetEndsAt ~= nil and now < record.resetEndsAt then
		return config.Status.Resetting
	end
	if record.droppedAt ~= nil then
		if record.breakStartedAt ~= nil and record.breakEndsAt ~= nil and now < record.breakEndsAt then
			if record.barrierStartupEndsAt ~= nil and now < record.barrierStartupEndsAt then
				return config.Status.Dropped
			end
			return config.Status.Blocked
		end
		if record.barrierStartupEndsAt ~= nil and now < record.barrierStartupEndsAt then
			return config.Status.Dropped
		end
		if record.barrierActiveEndsAt ~= nil and now < record.barrierActiveEndsAt then
			return config.Status.Blocked
		end
		if record.obstacleExpiresAt ~= nil and now < record.obstacleExpiresAt then
			return config.Status.Blocked
		end
	end
	return config.Status.Ready
end

function DefensivePropState.IsBreakInProgress(_config: Config, record: PropRecord?, now: number): boolean
	if record == nil or not validNow(now) then
		return false
	end
	return record.breakStartedAt ~= nil and record.breakEndsAt ~= nil and now < record.breakEndsAt
end

function DefensivePropState.BlocksGiantMacroRoutes(config: Config, record: PropRecord?, now: number): boolean
	return DefensivePropState.ResolveStatus(config, record, now) == config.Status.Blocked
end

function DefensivePropState.IsActiveObstacle(config: Config, record: PropRecord?, now: number): boolean
	local status = DefensivePropState.ResolveStatus(config, record, now)
	return status == config.Status.Dropped
		or status == config.Status.Blocked
		or DefensivePropState.IsBreakInProgress(config, record, now)
end

function DefensivePropState.Snapshot(config: Config, record: PropRecord?, now: number): Snapshot
	local state = DefensivePropState.ResolveStatus(config, record, now)
	if record == nil then
		return { state = state }
	end
	return {
		propId = record.propId,
		propType = record.propType,
		zoneId = record.zoneId,
		state = state,
		enabled = record.enabled,
		droppedByUserId = record.droppedByUserId,
		droppedAt = record.droppedAt,
		barrierStartupEndsAt = record.barrierStartupEndsAt,
		barrierActiveEndsAt = record.barrierActiveEndsAt,
		obstacleExpiresAt = record.obstacleExpiresAt,
		breakStartedAt = record.breakStartedAt,
		breakEndsAt = record.breakEndsAt,
		brokenByUserId = record.brokenByUserId,
		brokenAt = record.brokenAt,
		resetEndsAt = record.resetEndsAt,
		breakInProgress = DefensivePropState.IsBreakInProgress(config, record, now),
		blocksGiantMacroRoutes = DefensivePropState.BlocksGiantMacroRoutes(config, record, now),
	}
end

function DefensivePropState.ResolveLifecycle(config: Config, record: PropRecord?, now: number): (PropRecord?, boolean)
	if record == nil or not validNow(now) then
		return record, false
	end

	local changed = false
	local nextRecord = cloneRecord(record)
	local status = DefensivePropState.ResolveStatus(config, nextRecord, now)

	if
		nextRecord.droppedAt ~= nil
		and nextRecord.obstacleExpiresAt ~= nil
		and now >= nextRecord.obstacleExpiresAt
		and nextRecord.brokenAt == nil
		and nextRecord.resetEndsAt == nil
	then
		nextRecord = DefensivePropState.ClearObstacleTimestamps(nextRecord)
		nextRecord.resetEndsAt = now + positiveNumber(config.ResetDurationSeconds, 0)
		changed = true
	end

	if status == config.Status.Broken and nextRecord.brokenAt ~= nil and nextRecord.resetEndsAt == nil then
		nextRecord.resetEndsAt = now + positiveNumber(config.ResetDurationSeconds, 0)
		changed = true
	end

	if status == config.Status.Resetting and nextRecord.resetEndsAt ~= nil and now >= nextRecord.resetEndsAt then
		nextRecord = DefensivePropState.ClearObstacleTimestamps(nextRecord)
		nextRecord.resetEndsAt = nil
		changed = true
	end

	return nextRecord, changed
end

function DefensivePropState.ValidatePropType(config: Config, propType: any): boolean
	return type(propType) == "string" and type(config.PropTypes[propType]) == "table"
end

function DefensivePropState.ResolvePropTypeNumber(
	config: Config,
	propType: string,
	propTypeFieldName: string,
	configFieldName: string
): number
	local propTypeConfig = config.PropTypes[propType]
	if type(propTypeConfig) == "table" and type(propTypeConfig[propTypeFieldName]) == "number" then
		return positiveNumber(propTypeConfig[propTypeFieldName], 0)
	end
	return positiveNumber(config[configFieldName], 0)
end

function DefensivePropState.EvaluateRescueDropEffect(_config: Config, context: RescueDropContext): any
	if context.hasActiveRescueContract ~= true and context.downedAllyInZone ~= true then
		return {
			granted = false,
			reason = "no_rescue_context",
			effect = nil,
		}
	end
	local reason = if context.hasActiveRescueContract and context.downedAllyInZone
		then "rescue_drop_contract_and_ally"
		elseif context.hasActiveRescueContract then "rescue_drop_active_contract"
		else "rescue_drop_downed_ally_in_zone"
	return {
		granted = true,
		reason = reason,
		effect = "rescue_acceleration",
	}
end

function DefensivePropState.CanDrop(
	config: Config,
	record: PropRecord?,
	droppedByUserId: number,
	now: number,
	activeCountForUser: number
): any
	if record == nil then
		return { accepted = false, reason = "prop_not_found", record = record }
	end
	if not validNow(now) then
		return { accepted = false, reason = "invalid_now", record = record }
	end
	if record.enabled ~= true then
		return { accepted = false, reason = "prop_disabled", record = record }
	end

	local resolvedRecord, _ = DefensivePropState.ResolveLifecycle(config, record, now)
	record = resolvedRecord
	local status = DefensivePropState.ResolveStatus(config, record, now)
	if status ~= config.Status.Ready then
		return {
			accepted = false,
			reason = "prop_not_ready",
			record = record,
			snapshot = DefensivePropState.Snapshot(config, record, now),
		}
	end

	if type(droppedByUserId) ~= "number" then
		return { accepted = false, reason = "user_id_invalid", record = record }
	end

	if record.lastDropAt ~= nil then
		local recharge = positiveNumber(config.DropRechargeSeconds, 0)
		if now - record.lastDropAt < recharge then
			return { accepted = false, reason = "drop_recharge_active", record = record }
		end
	end

	local maxActive = positiveNumber(config.MaxActivePropsPerTinyfolk, 0)
	if maxActive > 0 and activeCountForUser >= maxActive then
		return { accepted = false, reason = "max_active_props_reached", record = record }
	end

	return { accepted = true, reason = "accepted", record = record }
end

function DefensivePropState.CreateDrop(config: Config, record: PropRecord, droppedByUserId: number, now: number): any
	local canDrop = DefensivePropState.CanDrop(config, record, droppedByUserId, now, 0)
	if canDrop.accepted ~= true then
		return canDrop
	end

	local startupSeconds = DefensivePropState.ResolvePropTypeNumber(
		config,
		record.propType,
		"barrierStartupSeconds",
		"BarrierStartupSeconds"
	)
	local activeSeconds = DefensivePropState.ResolvePropTypeNumber(
		config,
		record.propType,
		"barrierActiveSeconds",
		"BarrierActiveSeconds"
	)
	local obstacleSeconds = DefensivePropState.ResolvePropTypeNumber(
		config,
		record.propType,
		"obstacleDurationSeconds",
		"ObstacleDurationSeconds"
	)
	local startupEndsAt = now + startupSeconds
	local activeEndsAt = startupEndsAt + activeSeconds
	local obstacleExpiresAt = now + obstacleSeconds

	local nextRecord = DefensivePropState.ClearObstacleTimestamps(record)
	nextRecord.droppedByUserId = droppedByUserId
	nextRecord.droppedAt = now
	nextRecord.barrierStartupEndsAt = startupEndsAt
	nextRecord.barrierActiveEndsAt = activeEndsAt
	nextRecord.obstacleExpiresAt = obstacleExpiresAt
	nextRecord.lastDropAt = now

	return {
		accepted = true,
		reason = "accepted",
		record = nextRecord,
		snapshot = DefensivePropState.Snapshot(config, nextRecord, now),
	}
end

function DefensivePropState.CanStartBreak(config: Config, record: PropRecord?, brokenByUserId: number, now: number): any
	if record == nil then
		return { accepted = false, reason = "prop_not_found", record = record }
	end
	if not validNow(now) then
		return { accepted = false, reason = "invalid_now", record = record }
	end
	if type(brokenByUserId) ~= "number" then
		return { accepted = false, reason = "user_id_invalid", record = record }
	end

	local resolvedRecord, _ = DefensivePropState.ResolveLifecycle(config, record, now)
	record = resolvedRecord
	local status = DefensivePropState.ResolveStatus(config, record, now)
	if status ~= config.Status.Dropped and status ~= config.Status.Blocked then
		return {
			accepted = false,
			reason = "prop_not_breakable",
			record = record,
			snapshot = DefensivePropState.Snapshot(config, record, now),
		}
	end
	if DefensivePropState.IsBreakInProgress(config, record, now) then
		return { accepted = false, reason = "break_in_progress", record = record }
	end

	return { accepted = true, reason = "accepted", record = record }
end

function DefensivePropState.StartBreak(config: Config, record: PropRecord, brokenByUserId: number, now: number): any
	local canStart = DefensivePropState.CanStartBreak(config, record, brokenByUserId, now)
	if canStart.accepted ~= true then
		return canStart
	end

	local nextRecord = cloneRecord(record)
	local breakDuration = DefensivePropState.ResolvePropTypeNumber(
		config,
		record.propType,
		"breakDurationSeconds",
		"BreakDurationSeconds"
	)
	nextRecord.breakStartedAt = now
	nextRecord.breakEndsAt = now + breakDuration

	return {
		accepted = true,
		reason = "accepted",
		record = nextRecord,
		snapshot = DefensivePropState.Snapshot(config, nextRecord, now),
	}
end

function DefensivePropState.CompleteBreak(config: Config, record: PropRecord?, brokenByUserId: number, now: number): any
	if record == nil then
		return { accepted = false, reason = "prop_not_found", record = record }
	end
	if not validNow(now) then
		return { accepted = false, reason = "invalid_now", record = record }
	end
	if type(brokenByUserId) ~= "number" then
		return { accepted = false, reason = "user_id_invalid", record = record }
	end
	if record.breakStartedAt == nil or record.breakEndsAt == nil then
		return { accepted = false, reason = "break_not_started", record = record }
	end
	if now < record.breakEndsAt then
		return { accepted = false, reason = "break_in_progress", record = record }
	end

	local nextRecord = DefensivePropState.ClearObstacleTimestamps(record)
	nextRecord.brokenByUserId = brokenByUserId
	nextRecord.brokenAt = now
	nextRecord.resetEndsAt = nil

	return {
		accepted = true,
		reason = "accepted",
		record = nextRecord,
		snapshot = DefensivePropState.Snapshot(config, nextRecord, now),
	}
end

function DefensivePropState.CanApplyBarrierContact(
	config: Config,
	record: PropRecord?,
	now: number,
	lastContactAt: number?
): (boolean, string)
	if record == nil then
		return false, "prop_not_found"
	end
	if not validNow(now) then
		return false, "invalid_now"
	end
	if DefensivePropState.ResolveStatus(config, record, now) ~= config.Status.Blocked then
		return false, "barrier_not_active"
	end
	if type(lastContactAt) == "number" then
		local cooldown = positiveNumber(config.BarrierContactCooldownSeconds, 0)
		if cooldown > 0 and (now - lastContactAt) < cooldown then
			return false, "barrier_contact_cooldown"
		end
	end
	return true, "accepted"
end

function DefensivePropState.InterruptBreak(record: PropRecord): (PropRecord, boolean)
	local nextRecord = cloneRecord(record)
	local interrupted = nextRecord.breakStartedAt ~= nil and nextRecord.breakEndsAt ~= nil
	nextRecord.breakStartedAt = nil
	nextRecord.breakEndsAt = nil
	return nextRecord, interrupted
end

function DefensivePropState.ApplyBarrierContact(
	config: Config,
	record: PropRecord,
	now: number,
	lastContactAt: number?
): any
	local canApply, reason = DefensivePropState.CanApplyBarrierContact(config, record, now, lastContactAt)
	if not canApply then
		return {
			accepted = false,
			reason = reason,
			record = record,
			snapshot = DefensivePropState.Snapshot(config, record, now),
			breakInterrupted = false,
			staggerSeconds = 0,
		}
	end

	local nextRecord, breakInterrupted = DefensivePropState.InterruptBreak(record)
	local staggerSeconds = DefensivePropState.ResolvePropTypeNumber(
		config,
		record.propType,
		"barrierContactStaggerSeconds",
		"BarrierContactStaggerSeconds"
	)

	return {
		accepted = true,
		reason = if breakInterrupted then "barrier_contact_break_interrupted" else "barrier_contact_stagger",
		record = nextRecord,
		snapshot = DefensivePropState.Snapshot(config, nextRecord, now),
		breakInterrupted = breakInterrupted,
		staggerSeconds = staggerSeconds,
		staggerUntil = if staggerSeconds > 0 then now + staggerSeconds else now,
	}
end

function DefensivePropState.CountActiveForUser(
	config: Config,
	recordsByPropId: { [string]: PropRecord? },
	userId: number,
	now: number
): number
	local count = 0
	for _, record in pairs(recordsByPropId) do
		if
			record ~= nil
			and record.droppedByUserId == userId
			and DefensivePropState.IsActiveObstacle(config, record, now)
		then
			count += 1
		end
	end
	return count
end

return DefensivePropState
