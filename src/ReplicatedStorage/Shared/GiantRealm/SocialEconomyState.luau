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

export type State = {
	favor: number,
	control: number,
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

function SocialEconomyState.CreateEmptyState(): State
	return {
		favor = SocialEconomyConfig.DefaultFavor,
		control = SocialEconomyConfig.DefaultControl,
		operationIds = {},
		recentEvents = {},
	}
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

function SocialEconomyState.ResolveEffectSnapshot(state: State): EffectSnapshot
	local favor = if type(state) == "table" and isFiniteNumber(state.favor)
		then state.favor
		else SocialEconomyConfig.DefaultFavor
	local control = if type(state) == "table" and isFiniteNumber(state.control)
		then state.control
		else SocialEconomyConfig.DefaultControl

	return {
		favorComplianceBonus = 1 + favor / 200,
		controlIntimidationBonus = 1 + control / 200,
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

	local favorDelta, controlDelta = resolveDeltas(eventKind)
	if favorDelta == nil or controlDelta == nil then
		return {
			accepted = false,
			reason = "delta_invalid",
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

	local nextFavor = clampAxis(state.favor + favorDelta)
	local nextControl = clampAxis(state.control + controlDelta)

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

	return {
		favor = state.favor,
		control = state.control,
		recentEvents = events,
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

	return {
		accepted = true,
		reason = "accepted",
		state = {
			favor = math.floor(raw.favor),
			control = math.floor(raw.control),
			operationIds = operationIds,
			recentEvents = recentEvents,
		},
	}
end

return SocialEconomyState
