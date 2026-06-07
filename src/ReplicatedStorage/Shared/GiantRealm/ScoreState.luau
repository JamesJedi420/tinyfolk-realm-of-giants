--!nocheck
local ScoreConfig = require("../Config/ScoreConfig")

local ScoreState = {}

export type EventRecord = {
	sequence: number,
	userId: number,
	eventId: string,
	category: string,
	bucket: string,
	rawPoints: number,
	awardedPoints: number,
	contributionRatio: number,
	categoryCapReached: boolean,
	feedbackKey: string?,
	now: number,
	metadata: any?,
}

export type BucketScore = {
	total: number,
	categories: { [string]: number },
}

export type PlayerScore = {
	total: number,
	categories: { [string]: number },
	buckets: { [string]: BucketScore? },
}

export type RepeatState = {
	count: number,
	lastAt: number,
}

export type State = {
	playerScores: { [number]: PlayerScore? },
	globalCategoryTotals: { [string]: number },
	globalBucketTotals: { [string]: BucketScore? },
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
	categoryCapReached: boolean?,
	feedbackKey: string?,
}

local cloneMetadataValue: (value: any, seen: { [any]: any }?) -> any
local getEventBucket: (eventDefinition: any) -> string

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
	local buckets: { [string]: BucketScore? } = {}
	local total = 0
	if score ~= nil then
		if validNumber((score :: any).total) then
			total = (score :: any).total
		end
		if type((score :: any).categories) == "table" then
			for categoryName, categoryPoints in pairs((score :: any).categories) do
				if type(categoryName) == "string" and validNumber(categoryPoints) then
					categories[categoryName] = categoryPoints
				end
			end
		end
		if type((score :: any).buckets) == "table" then
			for bucketName, bucketScore in pairs((score :: any).buckets) do
				if bucketScore ~= nil then
					local bucketCategories: { [string]: number } = {}
					if type((bucketScore :: any).categories) == "table" then
						for categoryName, categoryPoints in pairs((bucketScore :: any).categories) do
							if type(categoryName) == "string" and validNumber(categoryPoints) then
								bucketCategories[categoryName] = categoryPoints
							end
						end
					end
					buckets[bucketName] = {
						total = if validNumber((bucketScore :: any).total) then (bucketScore :: any).total else 0,
						categories = bucketCategories,
					}
				end
			end
		end
	end

	return {
		total = total,
		categories = categories,
		buckets = buckets,
	}
end

local function cloneBucketScore(score: BucketScore?): BucketScore
	local categories: { [string]: number } = {}
	local total = 0
	if score ~= nil then
		if validNumber((score :: any).total) then
			total = (score :: any).total
		end
		if type((score :: any).categories) == "table" then
			for categoryName, categoryPoints in pairs((score :: any).categories) do
				if type(categoryName) == "string" and validNumber(categoryPoints) then
					categories[categoryName] = categoryPoints
				end
			end
		end
	end

	return {
		total = total,
		categories = categories,
	}
end

local function cloneState(state: State): State
	local playerScores: { [number]: PlayerScore? } = {}
	if type((state :: any).playerScores) == "table" then
		for userId, score in pairs((state :: any).playerScores) do
			if type(userId) == "number" and score ~= nil then
				playerScores[userId] = clonePlayerScore(score)
			end
		end
	end

	local globalCategoryTotals: { [string]: number } = {}
	if type((state :: any).globalCategoryTotals) == "table" then
		for categoryName, points in pairs((state :: any).globalCategoryTotals) do
			if type(categoryName) == "string" and validNumber(points) then
				globalCategoryTotals[categoryName] = points
			end
		end
	end

	local globalBucketTotals: { [string]: BucketScore? } = {}
	if type((state :: any).globalBucketTotals) == "table" then
		for bucketName, bucketScore in pairs((state :: any).globalBucketTotals) do
			if type(bucketName) == "string" and bucketScore ~= nil then
				globalBucketTotals[bucketName] = cloneBucketScore(bucketScore)
			end
		end
	end

	local repeatByActorEvent: { [string]: RepeatState? } = {}
	if type((state :: any).repeatByActorEvent) == "table" then
		for key, repeatState in pairs((state :: any).repeatByActorEvent) do
			if
				type(key) == "string"
				and type(repeatState) == "table"
				and validNumber((repeatState :: any).count)
				and validNumber((repeatState :: any).lastAt)
			then
				repeatByActorEvent[key] = {
					count = (repeatState :: any).count,
					lastAt = (repeatState :: any).lastAt,
				}
			end
		end
	end

	local recentEvents: { EventRecord } = {}
	if type((state :: any).recentEvents) == "table" then
		for _, record in ipairs((state :: any).recentEvents) do
			if type(record) == "table" then
				local awardedPoints = if validNumber((record :: any).awardedPoints)
					then (record :: any).awardedPoints
					else 0
				table.insert(recentEvents, {
					sequence = if validNumber((record :: any).sequence) then (record :: any).sequence else 0,
					userId = if validNumber((record :: any).userId) then (record :: any).userId else 0,
					eventId = if type((record :: any).eventId) == "string" then (record :: any).eventId else "",
					category = if type((record :: any).category) == "string" then (record :: any).category else "",
					bucket = if type((record :: any).bucket) == "string" then (record :: any).bucket else "normal",
					rawPoints = if validNumber((record :: any).rawPoints)
						then (record :: any).rawPoints
						else awardedPoints,
					awardedPoints = awardedPoints,
					contributionRatio = if validNumber((record :: any).contributionRatio)
						then (record :: any).contributionRatio
						else 1,
					categoryCapReached = (record :: any).categoryCapReached == true,
					feedbackKey = if type((record :: any).feedbackKey) == "string"
						then (record :: any).feedbackKey
						else nil,
					now = if validNumber((record :: any).now) then (record :: any).now else 0,
					metadata = cloneMetadataValue((record :: any).metadata),
				})
			end
		end
	end

	return {
		playerScores = playerScores,
		globalCategoryTotals = globalCategoryTotals,
		globalBucketTotals = globalBucketTotals,
		repeatByActorEvent = repeatByActorEvent,
		recentEvents = recentEvents,
		sequence = if validNumber((state :: any).sequence) then (state :: any).sequence else 0,
		lastReason = if type((state :: any).lastReason) == "string" then (state :: any).lastReason else nil,
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

local function isRewardBucketKnown(bucketName: string): boolean
	local buckets = ScoreConfig.RewardBuckets :: any
	for _, value in pairs(buckets) do
		if value == bucketName then
			return true
		end
	end
	return false
end

local function isRoleAllowedForCategory(categoryName: string, actorRole: string?): boolean
	local category = (ScoreConfig.ScoreCategories :: any)[categoryName]
	if type(category) ~= "table" or type(category.roles) ~= "table" then
		return true
	end
	if type(actorRole) ~= "string" then
		return false
	end
	for _, allowedRole in ipairs(category.roles) do
		if allowedRole == actorRole then
			return true
		end
	end
	return false
end

local function validateEventDefinition(eventDefinition: any): string?
	if type(eventDefinition.category) ~= "string" or eventDefinition.category == "" then
		return "invalid_score_category"
	end
	if type((ScoreConfig.ScoreCategories :: any)[eventDefinition.category]) ~= "table" then
		return "invalid_score_category"
	end

	local bucketName = getEventBucket(eventDefinition)
	if not isRewardBucketKnown(bucketName) then
		return "invalid_reward_bucket"
	end

	if not validNumber(eventDefinition.basePoints) or eventDefinition.basePoints <= 0 then
		return "invalid_base_points"
	end

	local valueRule = eventDefinition.valueRule
	if valueRule ~= nil and valueRule ~= "fixed" and valueRule ~= "proportional" then
		return "invalid_value_rule"
	end

	if not validNumber(eventDefinition.decayWindowSeconds) or eventDefinition.decayWindowSeconds < 0 then
		return "invalid_decay_window"
	end
	if
		not validNumber(eventDefinition.decayMultiplier)
		or eventDefinition.decayMultiplier < 0
		or eventDefinition.decayMultiplier > 1
	then
		return "invalid_decay_multiplier"
	end
	if
		not validNumber(eventDefinition.minMultiplier)
		or eventDefinition.minMultiplier < 0
		or eventDefinition.minMultiplier > 1
	then
		return "invalid_min_multiplier"
	end
	if
		not validNumber(eventDefinition.repeatCap)
		or eventDefinition.repeatCap < 1
		or eventDefinition.repeatCap ~= math.floor(eventDefinition.repeatCap)
	then
		return "invalid_repeat_cap"
	end
	if type(eventDefinition.actorRole) ~= "string" or eventDefinition.actorRole == "" then
		return "invalid_actor_role"
	end
	if not isRoleAllowedForCategory(eventDefinition.category, eventDefinition.actorRole) then
		return "invalid_category_role"
	end

	return nil
end

getEventBucket = function(eventDefinition: any): string
	if type(eventDefinition.bucket) == "string" and eventDefinition.bucket ~= "" then
		return eventDefinition.bucket
	end
	return "normal"
end

local function getFeedbackKey(eventDefinition: any): string?
	if type(eventDefinition.feedbackKey) == "string" and eventDefinition.feedbackKey ~= "" then
		return eventDefinition.feedbackKey
	end
	return nil
end

local function shouldApplyCategoryCap(bucketName: string): boolean
	return bucketName == "normal"
end

local function clampValue(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function resolveContributionRatio(eventDefinition: any, metadata: any?): (boolean, string?, number)
	if eventDefinition.valueRule ~= "proportional" then
		return true, nil, 1
	end

	local key = eventDefinition.contributionMetadataKey
	if type(key) ~= "string" or key == "" then
		return false, "invalid_contribution_metadata_key", 0
	end

	if type(metadata) ~= "table" then
		return false, "missing_contribution", 0
	end

	local rawContribution = metadata[key]
	if not validNumber(rawContribution) then
		return false, "missing_contribution", 0
	end

	local minContribution = 0
	if validNumber(eventDefinition.minContribution) then
		minContribution = eventDefinition.minContribution
	end

	local maxContribution = 1
	if validNumber(eventDefinition.maxContribution) then
		maxContribution = eventDefinition.maxContribution
	end

	if maxContribution < minContribution then
		return false, "invalid_contribution_bounds", 0
	end

	return true, nil, clampValue(rawContribution, minContribution, maxContribution)
end

local function clampMultiplier(multiplier: number, minMultiplier: number): number
	if multiplier < minMultiplier then
		return minMultiplier
	end
	return multiplier
end

local function resolveEconomyMultiplier(metadata: any?): number
	if type(metadata) ~= "table" then
		return 1
	end

	local value = metadata.traitEconomyMultiplier
	if not validNumber(value) then
		return 1
	end
	if value <= 0 then
		return 1
	end

	return value
end

local function getRepeatKey(userId: number, eventId: string): string
	return string.format("%d|%s", userId, eventId)
end

cloneMetadataValue = function(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end

	local activeSeen = seen
	if activeSeen == nil then
		activeSeen = {}
	end

	if activeSeen[value] ~= nil then
		return activeSeen[value]
	end

	local copy = {}
	activeSeen[value] = copy
	for key, nestedValue in pairs(value) do
		copy[cloneMetadataValue(key, activeSeen)] = cloneMetadataValue(nestedValue, activeSeen)
	end

	return copy
end

function ScoreState.NewState(): State
	return {
		playerScores = {},
		globalCategoryTotals = {},
		globalBucketTotals = {},
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

	local definitionError = validateEventDefinition(eventDefinition)
	if definitionError ~= nil then
		nextState.lastReason = definitionError
		return {
			accepted = false,
			reason = definitionError,
			state = nextState,
			record = nil,
			feedbackKey = getFeedbackKey(eventDefinition),
		}
	end

	if type(eventDefinition.actorRole) == "string" and input.actorRole ~= eventDefinition.actorRole then
		nextState.lastReason = "actor_role_mismatch"
		return { accepted = false, reason = "actor_role_mismatch", state = nextState, record = nil }
	end

	local contributionValid, contributionReason, contributionRatio =
		resolveContributionRatio(eventDefinition, input.metadata)
	if not contributionValid then
		local reason = contributionReason or "invalid_contribution"
		nextState.lastReason = reason
		return {
			accepted = false,
			reason = reason,
			state = nextState,
			record = nil,
			feedbackKey = getFeedbackKey(eventDefinition),
		}
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
	local economyMultiplier = resolveEconomyMultiplier(input.metadata)
	local rawPointsFloat = eventDefinition.basePoints * contributionRatio
	local rawPoints = math.floor(rawPointsFloat + 0.5)
	local pointsFloat = rawPoints * multiplier * economyMultiplier
	local points = math.floor(pointsFloat + 0.5)

	local categoryName = eventDefinition.category
	local bucketName = getEventBucket(eventDefinition)
	local feedbackKey = getFeedbackKey(eventDefinition)
	local playerScore = clonePlayerScore(nextState.playerScores[input.userId])
	local playerBucketScore = cloneBucketScore(playerScore.buckets[bucketName])
	local currentPlayerCategoryTotal = playerBucketScore.categories[categoryName] or 0
	local globalBucketScore = cloneBucketScore(nextState.globalBucketTotals[bucketName])
	local currentGlobalCategoryTotal = if shouldApplyCategoryCap(bucketName)
		then (nextState.globalCategoryTotals[categoryName] or 0)
		else (globalBucketScore.categories[categoryName] or 0)
	local categoryCap = getCategoryCap(categoryName)
	local globalAwardedPoints = points
	local categoryCapReached = false
	if shouldApplyCategoryCap(bucketName) then
		local globalRemaining = categoryCap - currentGlobalCategoryTotal
		globalAwardedPoints = math.min(points, math.max(globalRemaining, 0))
		categoryCapReached = globalAwardedPoints < points
	end
	if globalAwardedPoints <= 0 then
		nextState.lastReason = "category_cap_reached"
		return {
			accepted = false,
			reason = "category_cap_reached",
			state = nextState,
			record = nil,
			categoryCapReached = true,
			feedbackKey = feedbackKey,
		}
	end

	playerBucketScore.categories[categoryName] = currentPlayerCategoryTotal + globalAwardedPoints
	playerBucketScore.total += globalAwardedPoints
	playerScore.buckets[bucketName] = playerBucketScore
	playerScore.total += globalAwardedPoints
	if shouldApplyCategoryCap(bucketName) then
		playerScore.categories[categoryName] = (playerScore.categories[categoryName] or 0) + globalAwardedPoints
	end
	nextState.playerScores[input.userId] = playerScore
	globalBucketScore.categories[categoryName] = (globalBucketScore.categories[categoryName] or 0) + globalAwardedPoints
	globalBucketScore.total += globalAwardedPoints
	nextState.globalBucketTotals[bucketName] = globalBucketScore
	if shouldApplyCategoryCap(bucketName) then
		nextState.globalCategoryTotals[categoryName] = currentGlobalCategoryTotal + globalAwardedPoints
	end
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
		bucket = bucketName,
		rawPoints = rawPoints,
		awardedPoints = globalAwardedPoints,
		contributionRatio = contributionRatio,
		categoryCapReached = categoryCapReached,
		feedbackKey = feedbackKey,
		now = input.now,
		metadata = cloneMetadataValue(input.metadata),
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
		categoryCapReached = categoryCapReached,
		feedbackKey = feedbackKey,
	}
end

function ScoreState.GetPlayerSnapshot(state: State, userId: number): PlayerScore
	return clonePlayerScore(state.playerScores[userId])
end

function ScoreState.GetCategoryTotals(state: State): { [string]: number }
	local totals: { [string]: number } = table.clone(state.globalCategoryTotals)
	return totals
end

function ScoreState.GetBucketTotals(state: State): { [string]: BucketScore? }
	local totals: { [string]: BucketScore? } = {}
	if state.globalBucketTotals == nil then
		return totals
	end
	for bucketName, bucketScore in pairs(state.globalBucketTotals) do
		if bucketScore ~= nil then
			totals[bucketName] = cloneBucketScore(bucketScore)
		end
	end
	return totals
end

function ScoreState.GetRecentEvents(state: State, limit: number?): { EventRecord }
	local size = #state.recentEvents
	local maxItems = size
	if type(limit) == "number" then
		maxItems = math.floor(limit)
		if maxItems <= 0 then
			return {}
		end
	end
	if maxItems > size then
		maxItems = size
	end

	local startIndex = size - maxItems + 1
	local output: { EventRecord } = {}
	for index = startIndex, size do
		local record = state.recentEvents[index]
		local awardedPoints = if validNumber((record :: any).awardedPoints) then (record :: any).awardedPoints else 0
		table.insert(output, {
			sequence = if validNumber((record :: any).sequence) then (record :: any).sequence else 0,
			userId = if validNumber((record :: any).userId) then (record :: any).userId else 0,
			eventId = if type((record :: any).eventId) == "string" then (record :: any).eventId else "",
			category = if type((record :: any).category) == "string" then (record :: any).category else "",
			bucket = if type((record :: any).bucket) == "string" then (record :: any).bucket else "normal",
			rawPoints = if validNumber((record :: any).rawPoints) then (record :: any).rawPoints else awardedPoints,
			awardedPoints = awardedPoints,
			contributionRatio = if validNumber((record :: any).contributionRatio)
				then (record :: any).contributionRatio
				else 1,
			categoryCapReached = (record :: any).categoryCapReached == true,
			feedbackKey = if type((record :: any).feedbackKey) == "string" then (record :: any).feedbackKey else nil,
			now = if validNumber((record :: any).now) then (record :: any).now else 0,
			metadata = cloneMetadataValue((record :: any).metadata),
		})
	end
	return output
end

return ScoreState
