--!strict

local TrophyConfig = require("../Config/TrophyConfig")

local TrophyState = {}

export type TrophyRecord = {
	operationId: string,
	trophyKind: string,
	awardedAt: number,
	custodianUserId: number,
	targetDisplayToken: string,
	endReason: string?,
	heldSeconds: number?,
	summary: string,
}

export type State = {
	trophies: { TrophyRecord },
	operationIds: { [string]: boolean },
}

local VALID_KINDS = {
	[TrophyConfig.Kinds.CaptureSuccess] = true,
	[TrophyConfig.Kinds.ContainmentHeld] = true,
	[TrophyConfig.Kinds.ContainmentStarvation] = true,
	[TrophyConfig.Kinds.ContainmentEscapeFailure] = true,
	[TrophyConfig.Kinds.RaidDefenseWin] = true,
	[TrophyConfig.Kinds.NegotiatedRelease] = true,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value % 1 == 0
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function cloneRecord(record: TrophyRecord): TrophyRecord
	return {
		operationId = record.operationId,
		trophyKind = record.trophyKind,
		awardedAt = record.awardedAt,
		custodianUserId = record.custodianUserId,
		targetDisplayToken = record.targetDisplayToken,
		endReason = record.endReason,
		heldSeconds = record.heldSeconds,
		summary = record.summary,
	}
end

function TrophyState.ComputeTargetDisplayToken(targetUserId: number): string
	if not isPositiveInteger(targetUserId) then
		return "ref-unknown"
	end
	local hash = (math.floor(targetUserId) * 2654435761) % 0x100000000
	return string.format("ref-%08x", hash)
end

function TrophyState.ResolveKindFromContainmentEnd(endReason: string): string?
	if endReason == "starvation" then
		return TrophyConfig.Kinds.ContainmentStarvation
	end
	if endReason == "escaped" then
		return TrophyConfig.Kinds.ContainmentEscapeFailure
	end
	if endReason == "released" then
		return TrophyConfig.Kinds.NegotiatedRelease
	end
	if endReason == "timeout" then
		return TrophyConfig.Kinds.ContainmentHeld
	end
	return nil
end

function TrophyState.BuildSummary(trophyKind: string, targetDisplayToken: string, heldSeconds: number?): string
	local title = TrophyConfig.DisplayTitlesByKind[trophyKind] or "Realm Event"
	if type(heldSeconds) == "number" and heldSeconds >= 0 then
		return string.format("%s (%s, %ds held)", title, targetDisplayToken, math.floor(heldSeconds))
	end
	return string.format("%s (%s)", title, targetDisplayToken)
end

function TrophyState.CreateEmptyState(): State
	return {
		trophies = {},
		operationIds = {},
	}
end

function TrophyState.ValidateRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "trophy_record_invalid"
	end
	if nonEmptyString(record.operationId) == nil then
		return false, "trophy_operation_id_invalid"
	end
	if VALID_KINDS[record.trophyKind] ~= true then
		return false, "trophy_kind_invalid"
	end
	if not isFiniteNumber(record.awardedAt) then
		return false, "trophy_awarded_at_invalid"
	end
	if not isPositiveInteger(record.custodianUserId) then
		return false, "trophy_custodian_user_id_invalid"
	end
	if nonEmptyString(record.targetDisplayToken) == nil then
		return false, "trophy_target_display_token_invalid"
	end
	if nonEmptyString(record.summary) == nil then
		return false, "trophy_summary_invalid"
	end
	if record.endReason ~= nil and nonEmptyString(record.endReason) == nil then
		return false, "trophy_end_reason_invalid"
	end
	if record.heldSeconds ~= nil and not isFiniteNumber(record.heldSeconds) then
		return false, "trophy_held_seconds_invalid"
	end
	return true, nil
end

function TrophyState.ApplyEvent(state: State, input: any): any
	if type(state) ~= "table" then
		state = TrophyState.CreateEmptyState()
	end

	local operationId = nonEmptyString(input.operationId)
	if operationId == nil then
		return { accepted = false, reason = "operation_id_invalid", state = state, record = nil }
	end

	if state.operationIds[operationId] == true then
		return { accepted = false, reason = "duplicate", state = state, record = nil }
	end

	local trophyKind = nonEmptyString(input.trophyKind)
	if trophyKind == nil or VALID_KINDS[trophyKind] ~= true then
		return { accepted = false, reason = "trophy_kind_invalid", state = state, record = nil }
	end

	if not isFiniteNumber(input.awardedAt) then
		return { accepted = false, reason = "awarded_at_invalid", state = state, record = nil }
	end
	if not isPositiveInteger(input.custodianUserId) then
		return { accepted = false, reason = "custodian_user_id_invalid", state = state, record = nil }
	end
	if not isPositiveInteger(input.targetUserId) then
		return { accepted = false, reason = "target_user_id_invalid", state = state, record = nil }
	end

	local targetDisplayToken = TrophyState.ComputeTargetDisplayToken(input.targetUserId)
	local heldSeconds = if isFiniteNumber(input.heldSeconds) then input.heldSeconds else nil
	local endReason = nonEmptyString(input.endReason)
	local summary = nonEmptyString(input.summary)
		or TrophyState.BuildSummary(trophyKind, targetDisplayToken, heldSeconds)

	local record: TrophyRecord = {
		operationId = operationId,
		trophyKind = trophyKind,
		awardedAt = input.awardedAt,
		custodianUserId = math.floor(input.custodianUserId),
		targetDisplayToken = targetDisplayToken,
		endReason = endReason,
		heldSeconds = heldSeconds,
		summary = summary,
	}

	local nextState: State = {
		trophies = {},
		operationIds = {},
	}
	for _, existing in ipairs(state.trophies) do
		table.insert(nextState.trophies, cloneRecord(existing))
		nextState.operationIds[existing.operationId] = true
	end

	table.insert(nextState.trophies, record)
	nextState.operationIds[operationId] = true

	while #nextState.trophies > TrophyConfig.MaxRetainedTrophies do
		local removed = table.remove(nextState.trophies, 1)
		if removed ~= nil then
			nextState.operationIds[removed.operationId] = nil
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		record = record,
	}
end

function TrophyState.SerializePersistenceState(state: State): any
	if type(state) ~= "table" or type(state.trophies) ~= "table" then
		return { trophies = {} }
	end

	local records = {}
	for _, record in ipairs(state.trophies) do
		table.insert(records, cloneRecord(record))
	end

	table.sort(records, function(a: TrophyRecord, b: TrophyRecord): boolean
		if a.awardedAt ~= b.awardedAt then
			return a.awardedAt < b.awardedAt
		end
		return a.operationId < b.operationId
	end)

	return { trophies = records }
end

function TrophyState.ApplyPersistenceState(raw: any): any
	if raw == nil then
		return {
			accepted = true,
			reason = "cleared",
			state = TrophyState.CreateEmptyState(),
		}
	end

	if type(raw) ~= "table" or type(raw.trophies) ~= "table" then
		return { accepted = false, reason = "persistence_invalid" }
	end

	local trophies: { TrophyRecord } = {}
	local operationIds: { [string]: boolean } = {}
	for index, record in ipairs(raw.trophies) do
		local valid, reason = TrophyState.ValidateRecord(record)
		if not valid then
			return {
				accepted = false,
				reason = string.format("%s index=%d", reason or "trophy_record_invalid", index),
			}
		end
		if operationIds[record.operationId] == true then
			return { accepted = false, reason = string.format("trophy_operation_id_duplicate index=%d", index) }
		end
		table.insert(trophies, cloneRecord(record))
		operationIds[record.operationId] = true
	end

	return {
		accepted = true,
		reason = "accepted",
		state = {
			trophies = trophies,
			operationIds = operationIds,
		},
	}
end

function TrophyState.GetLatestRecord(state: State): TrophyRecord?
	if type(state) ~= "table" or type(state.trophies) ~= "table" or #state.trophies == 0 then
		return nil
	end
	return state.trophies[#state.trophies]
end

return TrophyState
