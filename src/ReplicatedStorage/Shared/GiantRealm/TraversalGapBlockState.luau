--!strict

local TraversalGapBlockState = {}

TraversalGapBlockState.States = {
	Idle = "Idle",
	Startup = "Startup",
	Active = "Active",
	Expired = "Expired",
}

export type BlockConfig = {
	TraversalGapBlockStartupSeconds: number,
	TraversalGapBlockActiveSeconds: number,
}

export type BlockRecord = {
	routeId: string,
	blockedByUserId: number,
	startupStartedAt: number,
	startupEndsAt: number,
	activeStartsAt: number,
	activeEndsAt: number,
	expiresAt: number,
}

export type Snapshot = {
	state: string,
	routeId: string?,
	blockedByUserId: number?,
	startupStartedAt: number?,
	startupEndsAt: number?,
	activeStartsAt: number?,
	activeEndsAt: number?,
	expiresAt: number?,
}

export type CreateResult = {
	accepted: boolean,
	reason: string,
	record: BlockRecord?,
	snapshot: Snapshot,
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

function TraversalGapBlockState.ResolveState(record: BlockRecord?, now: number): string
	if record == nil then
		return TraversalGapBlockState.States.Idle
	end

	if not validNow(now) then
		return TraversalGapBlockState.States.Expired
	end

	if now < record.startupEndsAt then
		return TraversalGapBlockState.States.Startup
	end

	if now < record.activeEndsAt then
		return TraversalGapBlockState.States.Active
	end

	return TraversalGapBlockState.States.Expired
end

function TraversalGapBlockState.Snapshot(record: BlockRecord?, now: number): Snapshot
	local state = TraversalGapBlockState.ResolveState(record, now)
	if record == nil then
		return {
			state = state,
		}
	end

	return {
		state = state,
		routeId = record.routeId,
		blockedByUserId = record.blockedByUserId,
		startupStartedAt = record.startupStartedAt,
		startupEndsAt = record.startupEndsAt,
		activeStartsAt = record.activeStartsAt,
		activeEndsAt = record.activeEndsAt,
		expiresAt = record.expiresAt,
	}
end

function TraversalGapBlockState.CreateBlock(
	config: BlockConfig,
	params: {
		routeId: string?,
		blockedByUserId: number?,
		now: number?,
		existingRecord: BlockRecord?,
	}
): CreateResult
	local now = params.now
	if not validNow(now) then
		return {
			accepted = false,
			reason = "invalid_now",
			record = params.existingRecord,
			snapshot = TraversalGapBlockState.Snapshot(params.existingRecord, 0),
		}
	end

	local existingRecord = params.existingRecord
	local existingState = TraversalGapBlockState.ResolveState(existingRecord, now :: number)
	if existingState == TraversalGapBlockState.States.Startup then
		return {
			accepted = false,
			reason = "block_startup",
			record = existingRecord,
			snapshot = TraversalGapBlockState.Snapshot(existingRecord, now :: number),
		}
	end

	if existingState == TraversalGapBlockState.States.Active then
		return {
			accepted = false,
			reason = "block_active",
			record = existingRecord,
			snapshot = TraversalGapBlockState.Snapshot(existingRecord, now :: number),
		}
	end

	if type(params.routeId) ~= "string" or params.routeId == "" then
		return {
			accepted = false,
			reason = "route_id_invalid",
			record = existingRecord,
			snapshot = TraversalGapBlockState.Snapshot(existingRecord, now :: number),
		}
	end

	if type(params.blockedByUserId) ~= "number" then
		return {
			accepted = false,
			reason = "blocked_by_user_id_invalid",
			record = existingRecord,
			snapshot = TraversalGapBlockState.Snapshot(existingRecord, now :: number),
		}
	end

	local startupDuration = positiveNumber(config.TraversalGapBlockStartupSeconds, 0)
	local activeDuration = positiveNumber(config.TraversalGapBlockActiveSeconds, 0)
	local startupEndsAt = (now :: number) + startupDuration
	local activeEndsAt = startupEndsAt + activeDuration
	local record: BlockRecord = {
		routeId = params.routeId,
		blockedByUserId = params.blockedByUserId,
		startupStartedAt = now :: number,
		startupEndsAt = startupEndsAt,
		activeStartsAt = startupEndsAt,
		activeEndsAt = activeEndsAt,
		expiresAt = activeEndsAt,
	}

	return {
		accepted = true,
		reason = "accepted",
		record = record,
		snapshot = TraversalGapBlockState.Snapshot(record, now :: number),
	}
end

function TraversalGapBlockState.ShouldRejectTraversal(record: BlockRecord?, now: number, exempt: boolean): boolean
	if exempt then
		return false
	end

	return TraversalGapBlockState.ResolveState(record, now) == TraversalGapBlockState.States.Active
end

return TraversalGapBlockState
