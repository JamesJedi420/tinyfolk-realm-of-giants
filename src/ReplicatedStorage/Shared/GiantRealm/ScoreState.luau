--!strict

local ScoreConfig = require("../Config/ScoreConfig")

local ScoreState = {}

export type EventRecord = {
	sequence: number,
	userId: number,
	eventId: string,
	category: string,
	awardedPoints: number,
	now: number,
	metadata: any?,
}

export type PlayerScore = {
	total: number,
	categories: { [string]: number },
}

export type RepeatState = {
	count: number,
	lastAt: number,
}

export type State = {
	playerScores: { [number]: PlayerScore? },
	globalCategoryTotals: { [string]: number },
	repeatByActorEvent: { [string]: RepeatState? },
	recentEvents: { EventRecord },
	sequence: number,
	lastReason: string?,
}

export type ResolveInput = {
	now: number,
	userId: number,
	eventId: string,
	actorRole: string?,
	metadata: any?,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	state: State,
	record: EventRecord?,
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

local function validUserId(userId: any): boolean
	if not validNumber(userId) then
		return false
	end
	if userId <= 0 then
		return false
	end
	return userId == math.floor(userId)
end

local function clonePlayerScore(score: PlayerScore?): PlayerScore
	local categories: { [string]: number } = {}
	local total = 0
	if score ~= nil then
		total = score.total
		for categoryName, categoryPoints in pairs(score.categories) do
			categories[categoryName] = categoryPoints
		end
	end

	return {
		total = total,
		categories = categories,
	}
end

local function cloneState(state: State): State
	local playerScores: { [number]: PlayerScore? } = {}
	for userId, score in pairs(state.playerScores) do
		if score ~= nil then
			playerScores[userId] = clonePlayerScore(score)
		end
	end

	local globalCategoryTotals: { [string]: number } = {}
	for categoryName, points in pairs(state.globalCategoryTotals) do
		globalCategoryTotals[categoryName] = points
	end

	local repeatByActorEvent: { [string]: RepeatState? } = {}
	for key, repeatState in pairs(state.repeatByActorEvent) do
		if repeatState ~= nil then
			repeatByActorEvent[key] = {
				count = repeatState.count,
				lastAt = repeatState.lastAt,
			}
		end
	end

	local recentEvents: { EventRecord } = {}
	for _, record in ipairs(state.recentEvents) do
		table.insert(recentEvents, {
			sequence = record.sequence,
			userId = record.userId,
			eventId = record.eventId,
			category = record.category,
			awardedPoints = record.awardedPoints,
			now = record.now,
			metadata = record.metadata,
		})
	end

	return {
		playerScores = playerScores,
		globalCategoryTotals = globalCategoryTotals,
		repeatByActorEvent = repeatByActorEvent,
		recentEvents = recentEvents,
		sequence = state.sequence,
		lastReason = state.lastReason,
	}
end

local function getEventDefinition(eventId: string): any?
	return (ScoreConfig.EventDefinitions :: any)[eventId]
end

local function getCategoryCap(categoryName: string): number
	local caps = ScoreConfig.CategoryPointCaps :: any
	local value = caps[categoryName]
	if type(value) == "number" and value > 0 then
		return value
	end
	return math.huge
end

local function clampMultiplier(multiplier: number, minMultiplier: number): number
	if multiplier < minMultiplier then
		return minMultiplier
	end
	return multiplier
end

local function getRepeatKey(userId: number, eventId: string): string
	return string.format("%d|%s", userId, eventId)
end

function ScoreState.NewState(): State
	return {
		playerScores = {},
		globalCategoryTotals = {},
		repeatByActorEvent = {},
		recentEvents = {},
		sequence = 0,
		lastReason = nil,
	}
end

function ScoreState.ResolveScoreEvent(state: State, input: ResolveInput): TransitionResult
	local nextState = cloneState(state)

	if not validNow(input.now) then
		nextState.lastReason = "invalid_now"
		return { accepted = false, reason = "invalid_now", state = nextState, record = nil }
	end

	if not validUserId(input.userId) then
		nextState.lastReason = "invalid_user_id"
		return { accepted = false, reason = "invalid_user_id", state = nextState, record = nil }
	end

	if type(input.eventId) ~= "string" or input.eventId == "" then
		nextState.lastReason = "invalid_event_id"
		return { accepted = false, reason = "invalid_event_id", state = nextState, record = nil }
	end

	local eventDefinition = getEventDefinition(input.eventId)
	if type(eventDefinition) ~= "table" then
		nextState.lastReason = "event_unknown"
		return { accepted = false, reason = "event_unknown", state = nextState, record = nil }
	end

	if type(eventDefinition.actorRole) == "string" and input.actorRole ~= eventDefinition.actorRole then
		nextState.lastReason = "actor_role_mismatch"
		return { accepted = false, reason = "actor_role_mismatch", state = nextState, record = nil }
	end

	local repeatKey = getRepeatKey(input.userId, input.eventId)
	local repeatState = nextState.repeatByActorEvent[repeatKey]
	local previousCount = 0
	if repeatState ~= nil then
		if (input.now - repeatState.lastAt) <= eventDefinition.decayWindowSeconds then
			previousCount = repeatState.count
		end
	end

	local nextCount = previousCount + 1
	if nextCount > eventDefinition.repeatCap then
		nextState.lastReason = "event_cap_reached"
		return { accepted = false, reason = "event_cap_reached", state = nextState, record = nil }
	end

	local decayPower = nextCount - 1
	local rawMultiplier = eventDefinition.decayMultiplier ^ decayPower
	local multiplier = clampMultiplier(rawMultiplier, eventDefinition.minMultiplier)
	local pointsFloat = eventDefinition.basePoints * multiplier
	local points = math.floor(pointsFloat + 0.5)

	local categoryName = eventDefinition.category
	local playerScore = clonePlayerScore(nextState.playerScores[input.userId])
	local currentPlayerCategoryTotal = playerScore.categories[categoryName] or 0
	local currentGlobalCategoryTotal = nextState.globalCategoryTotals[categoryName] or 0
	local categoryCap = getCategoryCap(categoryName)
	local globalRemaining = categoryCap - currentGlobalCategoryTotal
	local globalAwardedPoints = math.min(points, math.max(globalRemaining, 0))
	if globalAwardedPoints <= 0 then
		nextState.lastReason = "category_cap_reached"
		return { accepted = false, reason = "category_cap_reached", state = nextState, record = nil }
	end

	playerScore.categories[categoryName] = currentPlayerCategoryTotal + globalAwardedPoints
	playerScore.total += globalAwardedPoints
	nextState.playerScores[input.userId] = playerScore
	nextState.globalCategoryTotals[categoryName] = currentGlobalCategoryTotal + globalAwardedPoints
	nextState.repeatByActorEvent[repeatKey] = {
		count = nextCount,
		lastAt = input.now,
	}

	nextState.sequence += 1
	local record: EventRecord = {
		sequence = nextState.sequence,
		userId = input.userId,
		eventId = input.eventId,
		category = categoryName,
		awardedPoints = globalAwardedPoints,
		now = input.now,
		metadata = input.metadata,
	}
	table.insert(nextState.recentEvents, record)

	while #nextState.recentEvents > ScoreConfig.MaxRecentEvents do
		table.remove(nextState.recentEvents, 1)
	end

	nextState.lastReason = "accepted"
	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		record = record,
	}
end

function ScoreState.GetPlayerSnapshot(state: State, userId: number): PlayerScore
	return clonePlayerScore(state.playerScores[userId])
end

function ScoreState.GetCategoryTotals(state: State): { [string]: number }
	local totals: { [string]: number } = {}
	for categoryName, points in pairs(state.globalCategoryTotals) do
		totals[categoryName] = points
	end
	return totals
end

function ScoreState.GetRecentEvents(state: State, limit: number?): { EventRecord }
	local size = #state.recentEvents
	local maxItems = if type(limit) == "number" and limit > 0 then math.floor(limit) else size
	if maxItems > size then
		maxItems = size
	end

	local startIndex = size - maxItems + 1
	local output: { EventRecord } = {}
	for index = startIndex, size do
		local record = state.recentEvents[index]
		table.insert(output, {
			sequence = record.sequence,
			userId = record.userId,
			eventId = record.eventId,
			category = record.category,
			awardedPoints = record.awardedPoints,
			now = record.now,
			metadata = record.metadata,
		})
	end
	return output
end

return ScoreState
