--!strict

local SessionEndRecognitionPresentation: any = {}

export type RouteSnapshot = {
	routeId: any?,
	finalExitPhase: any?,
	finalExitResolvedAt: any?,
}

export type RecognitionModel = {
	visible: boolean,
	title: string,
	headline: string,
	detail: string,
	footer: string,
	tone: string,
	routeId: string?,
	resolvedAt: number?,
	totalScore: number?,
}

local function stringValue(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	if value == "" then
		return nil
	end
	return value
end

local function finiteNonNegativeNumber(value: any): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value < 0 then
		return nil
	end
	return value
end

local function totalScoreText(totalScore: number?): string
	if totalScore == nil then
		return "Final score unavailable"
	end
	return string.format("Final score %d", math.floor(totalScore))
end

local function labelFromFeedbackKey(feedbackKey: any): string?
	if type(feedbackKey) ~= "string" or feedbackKey == "" then
		return nil
	end

	local suffix = string.gsub(feedbackKey, "^score_", "")
	local words = {}
	for word in string.gmatch(suffix, "[^_]+") do
		table.insert(words, word)
	end

	if #words == 0 then
		return nil
	end

	local firstWord = string.upper(string.sub(words[1], 1, 1)) .. string.lower(string.sub(words[1], 2))
	if #words == 1 then
		return firstWord
	end

	for index = 2, #words do
		words[index] = string.lower(words[index])
	end

	words[1] = firstWord
	return table.concat(words, " ")
end

function SessionEndRecognitionPresentation.BuildSessionEndRecognitionModel(
	routeSnapshot: RouteSnapshot?,
	scoreAttributes: any
): RecognitionModel
	local resolvedRouteId = nil
	local resolvedAt = nil
	local finalExitPhase = nil
	if type(routeSnapshot) == "table" then
		local routeSnapshotAny: any = routeSnapshot
		resolvedRouteId = stringValue(routeSnapshotAny.routeId)
		resolvedAt = finiteNonNegativeNumber(routeSnapshotAny.finalExitResolvedAt)
		finalExitPhase = stringValue(routeSnapshotAny.finalExitPhase)
	end

	if finalExitPhase ~= "Resolved" then
		return {
			visible = false,
			title = "Session Complete",
			headline = "",
			detail = "",
			footer = "",
			tone = "neutral",
			routeId = resolvedRouteId,
			resolvedAt = resolvedAt,
			totalScore = nil,
		}
	end

	local scoreFeedbackHeadline = nil
	if type(scoreAttributes) == "table" then
		scoreFeedbackHeadline = labelFromFeedbackKey((scoreAttributes :: any).ScoreLastFeedbackKey)
	end
	local totalScore = nil
	if type(scoreAttributes) == "table" then
		totalScore = finiteNonNegativeNumber((scoreAttributes :: any).ScoreTotal)
	end

	local headline = if resolvedRouteId ~= nil
		then string.format("%s resolved", resolvedRouteId)
		else "Final exit resolved"
	local detail = if scoreFeedbackHeadline ~= nil
		then string.format("Latest score: %s", scoreFeedbackHeadline)
		else "Latest score unavailable"

	return {
		visible = true,
		title = "Session Complete",
		headline = headline,
		detail = detail,
		footer = totalScoreText(totalScore),
		tone = "positive",
		routeId = resolvedRouteId,
		resolvedAt = resolvedAt,
		totalScore = totalScore,
	}
end

return SessionEndRecognitionPresentation
