--!strict

local GiantReputationConfig = require("../Config/GiantReputationConfig")
local TrophyConfig = require("../Config/TrophyConfig")

local GiantReputationState = {}

export type ScoreEventRecord = {
	operationId: string,
	trophyKind: string,
	scoreAwarded: number,
	awardedAt: number,
}

export type State = {
	score: number,
	rank: number,
	operationIds: { [string]: boolean },
	recentEvents: { ScoreEventRecord },
}

local VALID_TROPHY_KINDS = {
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

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function cloneEventRecord(record: ScoreEventRecord): ScoreEventRecord
	return {
		operationId = record.operationId,
		trophyKind = record.trophyKind,
		scoreAwarded = record.scoreAwarded,
		awardedAt = record.awardedAt,
	}
end

function GiantReputationState.GetMaxRank(): number
	return #GiantReputationConfig.RankThresholds
end

function GiantReputationState.ResolveRankTitle(rank: number): string
	local titles = GiantReputationConfig.RankTitlesByIndex
	if type(titles) ~= "table" then
		return "Unknown Giant"
	end
	local index = math.clamp(math.floor(rank), 1, #titles)
	return titles[index] or "Unknown Giant"
end

function GiantReputationState.ResolveRankFromScore(score: number): number
	local thresholds = GiantReputationConfig.RankThresholds
	local resolvedRank = 1
	for index = #thresholds, 2, -1 do
		if score >= thresholds[index] then
			resolvedRank = index
			break
		end
	end
	return resolvedRank
end

function GiantReputationState.ResolveScoreToNextRank(score: number, rank: number): number
	local thresholds = GiantReputationConfig.RankThresholds
	local maxRank = #thresholds
	if rank >= maxRank then
		return 0
	end
	local nextThreshold = thresholds[rank + 1]
	if type(nextThreshold) ~= "number" then
		return 0
	end
	return math.max(0, nextThreshold - score)
end

function GiantReputationState.ResolveScoreAward(trophyKind: string): number?
	local award = GiantReputationConfig.ScoreAwardsByTrophyKind[trophyKind]
	if type(award) == "number" and award > 0 then
		return math.floor(award)
	end
	return nil
end

function GiantReputationState.CreateEmptyState(): State
	return {
		score = 0,
		rank = 1,
		operationIds = {},
		recentEvents = {},
	}
end

function GiantReputationState.ValidateEventRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "giant_reputation_event_invalid"
	end
	if nonEmptyString(record.operationId) == nil then
		return false, "giant_reputation_operation_id_invalid"
	end
	if VALID_TROPHY_KINDS[record.trophyKind] ~= true then
		return false, "giant_reputation_trophy_kind_invalid"
	end
	if not isFiniteNumber(record.scoreAwarded) or record.scoreAwarded <= 0 then
		return false, "giant_reputation_score_awarded_invalid"
	end
	if not isFiniteNumber(record.awardedAt) or record.awardedAt < 0 then
		return false, "giant_reputation_awarded_at_invalid"
	end
	return true, nil
end

function GiantReputationState.ApplyScoreEvent(state: State, input: any): any
	if type(state) ~= "table" then
		state = GiantReputationState.CreateEmptyState()
	end

	local operationId = nonEmptyString(input.operationId)
	if operationId == nil then
		return {
			accepted = false,
			reason = "operation_id_invalid",
			state = state,
			record = nil,
			rankedUp = false,
			previousRank = state.rank,
			newRank = state.rank,
		}
	end

	if state.operationIds[operationId] == true then
		return {
			accepted = false,
			reason = "duplicate",
			state = state,
			record = nil,
			rankedUp = false,
			previousRank = state.rank,
			newRank = state.rank,
		}
	end

	local trophyKind = nonEmptyString(input.trophyKind)
	if trophyKind == nil or VALID_TROPHY_KINDS[trophyKind] ~= true then
		return {
			accepted = false,
			reason = "trophy_kind_invalid",
			state = state,
			record = nil,
			rankedUp = false,
			previousRank = state.rank,
			newRank = state.rank,
		}
	end

	local scoreAward = GiantReputationState.ResolveScoreAward(trophyKind)
	if scoreAward == nil then
		return {
			accepted = false,
			reason = "score_award_invalid",
			state = state,
			record = nil,
			rankedUp = false,
			previousRank = state.rank,
			newRank = state.rank,
		}
	end

	if not isFiniteNumber(input.awardedAt) or input.awardedAt < 0 then
		return {
			accepted = false,
			reason = "awarded_at_invalid",
			state = state,
			record = nil,
			rankedUp = false,
			previousRank = state.rank,
			newRank = state.rank,
		}
	end

	local previousRank = state.rank
	local nextScore = state.score + scoreAward
	local nextRank = GiantReputationState.ResolveRankFromScore(nextScore)

	local record: ScoreEventRecord = {
		operationId = operationId,
		trophyKind = trophyKind,
		scoreAwarded = scoreAward,
		awardedAt = input.awardedAt,
	}

	local nextState: State = {
		score = nextScore,
		rank = nextRank,
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

	while #nextState.recentEvents > GiantReputationConfig.MaxRetainedRecentEvents do
		table.remove(nextState.recentEvents, 1)
	end

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		record = record,
		rankedUp = nextRank > previousRank,
		previousRank = previousRank,
		newRank = nextRank,
	}
end

function GiantReputationState.SerializePersistenceState(state: State): any
	if type(state) ~= "table" then
		return { score = 0, rank = 1, recentEvents = {} }
	end

	local events = {}
	for _, record in ipairs(state.recentEvents) do
		table.insert(events, cloneEventRecord(record))
	end

	table.sort(events, function(a: ScoreEventRecord, b: ScoreEventRecord): boolean
		if a.awardedAt ~= b.awardedAt then
			return a.awardedAt < b.awardedAt
		end
		return a.operationId < b.operationId
	end)

	return {
		score = state.score,
		rank = state.rank,
		recentEvents = events,
	}
end

function GiantReputationState.ApplyPersistenceState(raw: any): any
	if raw == nil then
		return {
			accepted = true,
			reason = "cleared",
			state = GiantReputationState.CreateEmptyState(),
		}
	end

	if type(raw) ~= "table" then
		return { accepted = false, reason = "persistence_invalid" }
	end
	if not isFiniteNumber(raw.score) or raw.score < 0 then
		return { accepted = false, reason = "giant_reputation_score_invalid" }
	end
	if not isFiniteNumber(raw.rank) or raw.rank < 1 then
		return { accepted = false, reason = "giant_reputation_rank_invalid" }
	end

	local resolvedRank = GiantReputationState.ResolveRankFromScore(raw.score)
	if math.floor(raw.rank) ~= resolvedRank then
		return { accepted = false, reason = "giant_reputation_rank_score_mismatch" }
	end

	local recentEvents: { ScoreEventRecord } = {}
	local operationIds: { [string]: boolean } = {}
	if raw.recentEvents ~= nil then
		if type(raw.recentEvents) ~= "table" then
			return { accepted = false, reason = "giant_reputation_recent_events_invalid" }
		end
		for index, record in ipairs(raw.recentEvents) do
			local valid, reason = GiantReputationState.ValidateEventRecord(record)
			if not valid then
				return {
					accepted = false,
					reason = string.format("%s index=%d", reason or "giant_reputation_event_invalid", index),
				}
			end
			if operationIds[record.operationId] == true then
				return {
					accepted = false,
					reason = string.format("giant_reputation_operation_id_duplicate index=%d", index),
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
			score = math.floor(raw.score),
			rank = resolvedRank,
			operationIds = operationIds,
			recentEvents = recentEvents,
		},
	}
end

return GiantReputationState
