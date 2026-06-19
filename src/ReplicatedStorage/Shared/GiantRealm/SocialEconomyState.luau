--!strict

local SocialEconomyConfig = require("../Config/SocialEconomyConfig")
local TrophyConfig = require("../Config/TrophyConfig")

local SocialEconomyState = {}

export type SocialEventRecord = {
	operationId: string,
	eventKind: string,
	favorDelta: number,
	controlDelta: number,
	favorAfter: number,
	controlAfter: number,
	awardedAt: number,
}

export type EffectSnapshot = {
	favorComplianceBonus: number,
	controlIntimidationBonus: number,
	dominantAxis: string,
}

export type DyadicRelation = {
	favor: number,
	control: number,
	lastUpdatedAt: number,
}

export type State = {
	favor: number,
	control: number,
	dyadicByUserId: { [string]: DyadicRelation },
	operationIds: { [string]: boolean },
	recentEvents: { SocialEventRecord },
}

local VALID_TROPHY_KINDS = {
	[TrophyConfig.Kinds.CaptureSuccess] = true,
	[TrophyConfig.Kinds.NegotiatedRelease] = true,
	[TrophyConfig.Kinds.ContainmentEscapeFailure] = true,
}

local VALID_EVENT_KINDS = {
	[SocialEconomyConfig.EventKinds.FavorGrant] = true,
	[SocialEconomyConfig.EventKinds.LoyaltyGrant] = true,
	[SocialEconomyConfig.EventKinds.ControlGrant] = true,
	[SocialEconomyConfig.EventKinds.FearGrant] = true,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function cloneEventRecord(record: SocialEventRecord): SocialEventRecord
	return {
		operationId = record.operationId,
		eventKind = record.eventKind,
		favorDelta = record.favorDelta,
		controlDelta = record.controlDelta,
		favorAfter = record.favorAfter,
		controlAfter = record.controlAfter,
		awardedAt = record.awardedAt,
	}
end

local function clampAxis(value: number): number
	return math.clamp(value, SocialEconomyConfig.AxisMin, SocialEconomyConfig.AxisMax)
end

local function resolveBonusCap(rawBonus: number, maxBonus: number): number
	if not isFiniteNumber(maxBonus) or maxBonus <= 1 then
		return rawBonus
	end
	return math.min(rawBonus, maxBonus)
end

local function countRecentEventsByKind(state: State, eventKind: string, at: number, windowSeconds: number): number
	if type(state.recentEvents) ~= "table" or #state.recentEvents == 0 then
		return 0
	end
	if not isFiniteNumber(windowSeconds) or windowSeconds <= 0 then
		return 0
	end

	local count = 0
	for _, record in ipairs(state.recentEvents) do
		if record.eventKind == eventKind and isFiniteNumber(record.awardedAt) then
			if at - record.awardedAt <= windowSeconds then
				count += 1
			end
		end
	end
	return count
end

local function resolveDiminishMultiplier(recentCount: number): number
	local multipliers = SocialEconomyConfig.TrophyDeltaDiminishMultipliers
	if type(multipliers) ~= "table" or #multipliers == 0 then
		return 1
	end
	local index = math.min(recentCount + 1, #multipliers)
	return multipliers[index]
end

local function resolveDeltas(eventKind: string): (number?, number?)
	local trophyDeltas = SocialEconomyConfig.DeltasByTrophyKind[eventKind]
	if type(trophyDeltas) == "table" then
		local favorDelta = if isFiniteNumber(trophyDeltas.favor) then math.floor(trophyDeltas.favor) else 0
		local controlDelta = if isFiniteNumber(trophyDeltas.control) then math.floor(trophyDeltas.control) else 0
		if favorDelta ~= 0 or controlDelta ~= 0 then
			return favorDelta, controlDelta
		end
		return nil
	end

	local eventDeltas = SocialEconomyConfig.DeltasByEventKind[eventKind]
	if type(eventDeltas) ~= "table" then
		return nil
	end
	local favorDelta = if isFiniteNumber(eventDeltas.favor) then math.floor(eventDeltas.favor) else 0
	local controlDelta = if isFiniteNumber(eventDeltas.control) then math.floor(eventDeltas.control) else 0
	if favorDelta == 0 and controlDelta == 0 then
		return nil
	end
	return favorDelta, controlDelta
end

function SocialEconomyState.ApplyAxisDecay(state: State, deltaSeconds: number): State
	if type(state) ~= "table" then
		state = SocialEconomyState.CreateEmptyState()
	end
	if not isFiniteNumber(deltaSeconds) or deltaSeconds <= 0 then
		return state
	end

	local decayRate = SocialEconomyConfig.AxisDecayPerSecond
	if not isFiniteNumber(decayRate) or decayRate <= 0 then
		return state
	end

	local decayAmount = decayRate * deltaSeconds
	local function decayAxis(current: number, defaultValue: number): number
		if current > defaultValue then
			return clampAxis(math.max(defaultValue, current - decayAmount))
		end
		if current < defaultValue then
			return clampAxis(math.min(defaultValue, current + decayAmount))
		end
		return current
	end

	return {
		favor = math.floor(decayAxis(state.favor, SocialEconomyConfig.DefaultFavor)),
		control = math.floor(decayAxis(state.control, SocialEconomyConfig.DefaultControl)),
		dyadicByUserId = if type(state.dyadicByUserId) == "table" then state.dyadicByUserId else {},
		operationIds = state.operationIds,
		recentEvents = state.recentEvents,
	}
end

function SocialEconomyState.ResolveDiminishedTrophyDelta(
	state: State,
	eventKind: string,
	at: number
): (number?, number?)
	local favorDelta, controlDelta = resolveDeltas(eventKind)
	if favorDelta == nil or controlDelta == nil then
		return nil, nil
	end

	if VALID_TROPHY_KINDS[eventKind] ~= true then
		return favorDelta, controlDelta
	end

	local windowSeconds = SocialEconomyConfig.TrophyDeltaDiminishWindowSeconds
	local recentCount = countRecentEventsByKind(state, eventKind, at, windowSeconds)
	local multiplier = resolveDiminishMultiplier(recentCount)
	return math.floor(favorDelta * multiplier), math.floor(controlDelta * multiplier)
end

function SocialEconomyState.CreateEmptyState(): State
	return {
		favor = SocialEconomyConfig.DefaultFavor,
		control = SocialEconomyConfig.DefaultControl,
		dyadicByUserId = {},
		operationIds = {},
		recentEvents = {},
	}
end

function SocialEconomyState.ResolveEffectiveAxes(state: State, targetUserId: number?): (number, number)
	local favor = if type(state) == "table" and isFiniteNumber(state.favor)
		then state.favor
		else SocialEconomyConfig.DefaultFavor
	local control = if type(state) == "table" and isFiniteNumber(state.control)
		then state.control
		else SocialEconomyConfig.DefaultControl

	if not isFiniteNumber(targetUserId) or (targetUserId :: number) <= 0 then
		return favor, control
	end

	local dyadicByUserId = if type(state) == "table" then state.dyadicByUserId else nil
	if type(dyadicByUserId) ~= "table" then
		return favor, control
	end

	local dyadic = dyadicByUserId[tostring(math.floor(targetUserId :: number))]
	if type(dyadic) ~= "table" then
		return favor, control
	end

	local blendWeight = SocialEconomyConfig.DyadicBlendWeight
	if not isFiniteNumber(blendWeight) or blendWeight <= 0 then
		return favor, control
	end
	if blendWeight > 1 then
		blendWeight = 1
	end

	local dyadicFavor = if isFiniteNumber(dyadic.favor) then dyadic.favor else favor
	local dyadicControl = if isFiniteNumber(dyadic.control) then dyadic.control else control
	return favor + (dyadicFavor - favor) * blendWeight, control + (dyadicControl - control) * blendWeight
end

function SocialEconomyState.ResolveDominantAxis(favor: number, control: number): string
	local threshold = SocialEconomyConfig.DominantAxisBalanceThreshold
	if not isFiniteNumber(threshold) or threshold < 0 then
		threshold = 0
	end
	local favorLead = favor - control
	if favorLead > threshold then
		return SocialEconomyConfig.DominantAxes.Favor
	end
	if control - favor > threshold then
		return SocialEconomyConfig.DominantAxes.Control
	end
	return SocialEconomyConfig.DominantAxes.Balanced
end

function SocialEconomyState.ResolveEffectSnapshot(state: State, targetUserId: number?): EffectSnapshot
	local favor, control = SocialEconomyState.ResolveEffectiveAxes(state, targetUserId)

	return {
		favorComplianceBonus = resolveBonusCap(1 + favor / 200, SocialEconomyConfig.MaxComplianceBonus),
		controlIntimidationBonus = resolveBonusCap(1 + control / 200, SocialEconomyConfig.MaxIntimidationBonus),
		dominantAxis = SocialEconomyState.ResolveDominantAxis(favor, control),
	}
end

function SocialEconomyState.ResolveTrophyEventKind(trophyKind: string): string?
	if VALID_TROPHY_KINDS[trophyKind] == true then
		return trophyKind
	end
	return nil
end

function SocialEconomyState.IsValidEventKind(eventKind: string): boolean
	if VALID_TROPHY_KINDS[eventKind] == true then
		return true
	end
	return VALID_EVENT_KINDS[eventKind] == true
end

function SocialEconomyState.ApplySocialEvent(state: State, input: any): any
	if type(state) ~= "table" then
		state = SocialEconomyState.CreateEmptyState()
	end

	local operationId = nonEmptyString(input.operationId)
	if operationId == nil then
		return {
			accepted = false,
			reason = "operation_id_invalid",
			state = state,
			record = nil,
		}
	end

	if state.operationIds[operationId] == true then
		return {
			accepted = false,
			reason = "duplicate",
			state = state,
			record = nil,
		}
	end

	local eventKind = nonEmptyString(input.eventKind)
	if eventKind == nil or SocialEconomyState.IsValidEventKind(eventKind) ~= true then
		return {
			accepted = false,
			reason = "event_kind_invalid",
			state = state,
			record = nil,
		}
	end

	if not isFiniteNumber(input.awardedAt) or input.awardedAt < 0 then
		return {
			accepted = false,
			reason = "awarded_at_invalid",
			state = state,
			record = nil,
		}
	end

	local favorDelta, controlDelta = SocialEconomyState.ResolveDiminishedTrophyDelta(state, eventKind, input.awardedAt)
	if favorDelta == nil or controlDelta == nil then
		return {
			accepted = false,
			reason = "delta_invalid",
			state = state,
			record = nil,
		}
	end
	if favorDelta == 0 and controlDelta == 0 then
		return {
			accepted = false,
			reason = "delta_zero",
			state = state,
			record = nil,
		}
	end

	local nextFavor = clampAxis(state.favor + favorDelta)
	local nextControl = clampAxis(state.control + controlDelta)

	local nextDyadicByUserId: { [string]: DyadicRelation } = {}
	if type(state.dyadicByUserId) == "table" then
		for userIdKey, relation in pairs(state.dyadicByUserId) do
			if type(relation) == "table" then
				nextDyadicByUserId[userIdKey] = {
					favor = relation.favor,
					control = relation.control,
					lastUpdatedAt = relation.lastUpdatedAt,
				}
			end
		end
	end

	if isFiniteNumber(input.targetUserId) and (input.targetUserId :: number) > 0 then
		local userIdKey = tostring(math.floor(input.targetUserId :: number))
		local existingDyadic = nextDyadicByUserId[userIdKey]
		local dyadicFavor = if type(existingDyadic) == "table" and isFiniteNumber(existingDyadic.favor)
			then existingDyadic.favor
			else state.favor
		local dyadicControl = if type(existingDyadic) == "table" and isFiniteNumber(existingDyadic.control)
			then existingDyadic.control
			else state.control
		nextDyadicByUserId[userIdKey] = {
			favor = clampAxis(dyadicFavor + favorDelta),
			control = clampAxis(dyadicControl + controlDelta),
			lastUpdatedAt = input.awardedAt,
		}
	end

	local record: SocialEventRecord = {
		operationId = operationId,
		eventKind = eventKind,
		favorDelta = favorDelta,
		controlDelta = controlDelta,
		favorAfter = nextFavor,
		controlAfter = nextControl,
		awardedAt = input.awardedAt,
	}

	local nextState: State = {
		favor = nextFavor,
		control = nextControl,
		dyadicByUserId = nextDyadicByUserId,
		operationIds = {},
		recentEvents = {},
	}
	for existingOperationId in pairs(state.operationIds) do
		nextState.operationIds[existingOperationId] = true
	end
	nextState.operationIds[operationId] = true

	for _, existing in ipairs(state.recentEvents) do
		table.insert(nextState.recentEvents, cloneEventRecord(existing))
	end
	table.insert(nextState.recentEvents, record)

	while #nextState.recentEvents > SocialEconomyConfig.MaxRetainedRecentEvents do
		table.remove(nextState.recentEvents, 1)
	end

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		record = record,
	}
end

function SocialEconomyState.ValidateEventRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "social_economy_event_invalid"
	end
	if nonEmptyString(record.operationId) == nil then
		return false, "social_economy_operation_id_invalid"
	end
	if SocialEconomyState.IsValidEventKind(record.eventKind) ~= true then
		return false, "social_economy_event_kind_invalid"
	end
	if not isFiniteNumber(record.favorDelta) then
		return false, "social_economy_favor_delta_invalid"
	end
	if not isFiniteNumber(record.controlDelta) then
		return false, "social_economy_control_delta_invalid"
	end
	if not isFiniteNumber(record.favorAfter) or record.favorAfter < SocialEconomyConfig.AxisMin then
		return false, "social_economy_favor_after_invalid"
	end
	if record.favorAfter > SocialEconomyConfig.AxisMax then
		return false, "social_economy_favor_after_invalid"
	end
	if not isFiniteNumber(record.controlAfter) or record.controlAfter < SocialEconomyConfig.AxisMin then
		return false, "social_economy_control_after_invalid"
	end
	if record.controlAfter > SocialEconomyConfig.AxisMax then
		return false, "social_economy_control_after_invalid"
	end
	if not isFiniteNumber(record.awardedAt) or record.awardedAt < 0 then
		return false, "social_economy_awarded_at_invalid"
	end
	return true, nil
end

function SocialEconomyState.SerializePersistenceState(state: State): any
	if type(state) ~= "table" then
		return {
			favor = SocialEconomyConfig.DefaultFavor,
			control = SocialEconomyConfig.DefaultControl,
			recentEvents = {},
			dyadicRelations = {},
		}
	end

	local events = {}
	for _, record in ipairs(state.recentEvents) do
		table.insert(events, cloneEventRecord(record))
	end

	table.sort(events, function(a: SocialEventRecord, b: SocialEventRecord): boolean
		if a.awardedAt ~= b.awardedAt then
			return a.awardedAt < b.awardedAt
		end
		return a.operationId < b.operationId
	end)

	local dyadicEntries: { any } = {}
	if type(state.dyadicByUserId) == "table" then
		for userIdKey, relation in pairs(state.dyadicByUserId) do
			if type(relation) == "table" then
				local userId = tonumber(userIdKey)
				if type(userId) == "number" and userId > 0 then
					table.insert(dyadicEntries, {
						userId = math.floor(userId),
						favor = relation.favor,
						control = relation.control,
						lastUpdatedAt = relation.lastUpdatedAt,
					})
				end
			end
		end
	end

	table.sort(dyadicEntries, function(a: any, b: any): boolean
		local aUpdated = if isFiniteNumber(a.lastUpdatedAt) then a.lastUpdatedAt else 0
		local bUpdated = if isFiniteNumber(b.lastUpdatedAt) then b.lastUpdatedAt else 0
		if aUpdated ~= bUpdated then
			return aUpdated > bUpdated
		end
		return a.userId < b.userId
	end)

	local maxDyadic = SocialEconomyConfig.MaxDyadicRelations
	if isFiniteNumber(maxDyadic) and maxDyadic > 0 then
		while #dyadicEntries > math.floor(maxDyadic) do
			table.remove(dyadicEntries)
		end
	end

	return {
		favor = state.favor,
		control = state.control,
		recentEvents = events,
		dyadicRelations = dyadicEntries,
	}
end

function SocialEconomyState.ApplyPersistenceState(raw: any): any
	if raw == nil then
		return {
			accepted = true,
			reason = "cleared",
			state = SocialEconomyState.CreateEmptyState(),
		}
	end

	if type(raw) ~= "table" then
		return { accepted = false, reason = "persistence_invalid" }
	end
	if not isFiniteNumber(raw.favor) or raw.favor < SocialEconomyConfig.AxisMin then
		return { accepted = false, reason = "social_economy_favor_invalid" }
	end
	if raw.favor > SocialEconomyConfig.AxisMax then
		return { accepted = false, reason = "social_economy_favor_invalid" }
	end
	if not isFiniteNumber(raw.control) or raw.control < SocialEconomyConfig.AxisMin then
		return { accepted = false, reason = "social_economy_control_invalid" }
	end
	if raw.control > SocialEconomyConfig.AxisMax then
		return { accepted = false, reason = "social_economy_control_invalid" }
	end

	local recentEvents: { SocialEventRecord } = {}
	local operationIds: { [string]: boolean } = {}
	if raw.recentEvents ~= nil then
		if type(raw.recentEvents) ~= "table" then
			return { accepted = false, reason = "social_economy_recent_events_invalid" }
		end
		if #raw.recentEvents > SocialEconomyConfig.MaxRetainedRecentEvents then
			return { accepted = false, reason = "social_economy_recent_events_limit_exceeded" }
		end
		for index, record in ipairs(raw.recentEvents) do
			local valid, reason = SocialEconomyState.ValidateEventRecord(record)
			if not valid then
				return {
					accepted = false,
					reason = string.format("%s index=%d", reason or "social_economy_event_invalid", index),
				}
			end
			if operationIds[record.operationId] == true then
				return {
					accepted = false,
					reason = string.format("social_economy_operation_id_duplicate index=%d", index),
				}
			end
			table.insert(recentEvents, cloneEventRecord(record))
			operationIds[record.operationId] = true
		end
	end

	local dyadicByUserId: { [string]: DyadicRelation } = {}
	if raw.dyadicRelations ~= nil then
		if type(raw.dyadicRelations) ~= "table" then
			return { accepted = false, reason = "social_economy_dyadic_relations_invalid" }
		end
		if #raw.dyadicRelations > SocialEconomyConfig.MaxDyadicRelations then
			return { accepted = false, reason = "social_economy_dyadic_relations_limit_exceeded" }
		end
		for index, relation in ipairs(raw.dyadicRelations) do
			if type(relation) ~= "table" then
				return {
					accepted = false,
					reason = string.format("social_economy_dyadic_relation_invalid index=%d", index),
				}
			end
			if not isFiniteNumber(relation.userId) or relation.userId <= 0 then
				return {
					accepted = false,
					reason = string.format("social_economy_dyadic_user_id_invalid index=%d", index),
				}
			end
			if not isFiniteNumber(relation.favor) or relation.favor < SocialEconomyConfig.AxisMin then
				return {
					accepted = false,
					reason = string.format("social_economy_dyadic_favor_invalid index=%d", index),
				}
			end
			if relation.favor > SocialEconomyConfig.AxisMax then
				return {
					accepted = false,
					reason = string.format("social_economy_dyadic_favor_invalid index=%d", index),
				}
			end
			if not isFiniteNumber(relation.control) or relation.control < SocialEconomyConfig.AxisMin then
				return {
					accepted = false,
					reason = string.format("social_economy_dyadic_control_invalid index=%d", index),
				}
			end
			if relation.control > SocialEconomyConfig.AxisMax then
				return {
					accepted = false,
					reason = string.format("social_economy_dyadic_control_invalid index=%d", index),
				}
			end
			local userIdKey = tostring(math.floor(relation.userId))
			dyadicByUserId[userIdKey] = {
				favor = math.floor(relation.favor),
				control = math.floor(relation.control),
				lastUpdatedAt = if isFiniteNumber(relation.lastUpdatedAt) then relation.lastUpdatedAt else 0,
			}
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		state = {
			favor = math.floor(raw.favor),
			control = math.floor(raw.control),
			dyadicByUserId = dyadicByUserId,
			operationIds = operationIds,
			recentEvents = recentEvents,
		},
	}
end

return SocialEconomyState
