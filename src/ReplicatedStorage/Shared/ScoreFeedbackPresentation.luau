--!strict

local ScoreFeedbackPresentation: any = {}

export type ScoreModel = {
	visible: boolean,
	title: string,
	headline: string,
	detail: string,
	totalText: string,
	tone: string,
}

local FEEDBACK_LABELS = {
	score_escape_success = "Escape success",
	score_rescue_complete = "Rescue complete",
	score_capture_success = "Capture success",
	score_capture_release = "Capture released",
	score_objective_partial = "Objective progress",
	score_tutorial_bonus = "Tutorial bonus",
	score_hidden_discovery = "Hidden discovery",
	score_compensation_grant = "Compensation granted",
}

local REASON_LABELS = {
	accepted = "Score updated",
	invalid_event_id = "Invalid score event",
	actor_not_found = "Actor not found",
	actor_role_mismatch = "Role mismatch",
	event_unknown = "Unknown score event",
	missing_contribution = "Missing contribution",
	category_cap_reached = "Category cap reached",
}

local BUCKET_LABELS = {
	normal = "Normal",
	bonus = "Bonus",
	hidden = "Hidden",
	compensation = "Compensation",
}

local function readString(attributes: any, name: string): string?
	if type(attributes) ~= "table" then
		return nil
	end

	local value = attributes[name]
	if type(value) ~= "string" or value == "" then
		return nil
	end

	return value
end

local function readNumber(attributes: any, name: string): number?
	if type(attributes) ~= "table" then
		return nil
	end

	local value = attributes[name]
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end

	return value
end

local function titleCase(value: string): string
	local normalized = string.gsub(string.lower(value), "[_%-]+", " ")
	local words: { string } = {}
	for word in string.gmatch(normalized, "%S+") do
		local head = string.upper(string.sub(word, 1, 1))
		local tail = string.sub(word, 2)
		table.insert(words, head .. tail)
	end
	return table.concat(words, " ")
end

local function prettyScoreKey(key: string): string
	local cleaned = key
	if string.find(cleaned, "score_", 1, true) == 1 then
		cleaned = string.sub(cleaned, 7)
	end
	return titleCase(cleaned)
end

local function labelForScore(key: string?): string
	if key == nil then
		return "Score updated"
	end

	local mapped = FEEDBACK_LABELS[key]
	if type(mapped) == "string" and mapped ~= "" then
		return mapped
	end

	return prettyScoreKey(key)
end

local function labelForReason(reason: string?): string
	if reason == nil then
		return "Score updated"
	end

	local mapped = REASON_LABELS[reason]
	if type(mapped) == "string" and mapped ~= "" then
		return mapped
	end

	return titleCase(reason)
end

local function labelForBucket(bucket: string?): string?
	if bucket == nil then
		return nil
	end

	local mapped = BUCKET_LABELS[bucket]
	if type(mapped) == "string" and mapped ~= "" then
		return mapped
	end

	return titleCase(bucket)
end

local function formatSignedPoints(points: number?): string?
	if points == nil then
		return nil
	end

	if points >= 0 then
		return string.format("+%d", math.floor(points))
	end

	return tostring(math.floor(points))
end

local function joinParts(parts: { string }): string
	local filtered: { string } = {}
	for _, part in ipairs(parts) do
		if type(part) == "string" and part ~= "" then
			table.insert(filtered, part)
		end
	end
	return table.concat(filtered, " • ")
end

function ScoreFeedbackPresentation.BuildScoreModel(config: any, attributes: any): ScoreModel
	local stateAttributes: any = if type(config) == "table" and type(config.StateAttributes) == "table"
		then config.StateAttributes
		else {}
	local feedbackKey = readString(attributes, stateAttributes.ScoreLastFeedbackKey or "ScoreLastFeedbackKey")
	local reason = readString(attributes, stateAttributes.ScoreLastReason or "ScoreLastReason")
	local bucket = readString(attributes, stateAttributes.ScoreLastBucket or "ScoreLastBucket")
	local awardedPoints = readNumber(attributes, stateAttributes.ScoreLastAwardedPoints or "ScoreLastAwardedPoints")
	local totalPoints = readNumber(attributes, stateAttributes.ScoreTotal or "ScoreTotal") or 0
	local capReached = false
	if type(attributes) == "table" then
		capReached = attributes[stateAttributes.ScoreLastCategoryCapReached or "ScoreLastCategoryCapReached"] == true
	end

	local visible = feedbackKey ~= nil or reason ~= nil or totalPoints > 0
	if not visible then
		return {
			visible = false,
			title = "Score Update",
			headline = "",
			detail = "",
			totalText = "",
			tone = "neutral",
		}
	end

	local detailParts: { string } = {}
	local bucketLabel = labelForBucket(bucket)
	if bucketLabel ~= nil then
		table.insert(detailParts, bucketLabel)
	end

	local pointsText = formatSignedPoints(awardedPoints)
	if pointsText ~= nil then
		table.insert(detailParts, pointsText)
	end

	table.insert(detailParts, string.format("Total %d", math.floor(totalPoints)))
	if capReached then
		table.insert(detailParts, "Category cap reached")
	end

	if feedbackKey == nil and reason ~= nil then
		table.insert(detailParts, labelForReason(reason))
	end

	local tone = if capReached
		then "warning"
		elseif reason ~= nil and reason ~= "accepted" then "warning"
		elseif awardedPoints ~= nil and awardedPoints > 0 then "positive"
		else "neutral"

	return {
		visible = true,
		title = "Score Update",
		headline = if feedbackKey ~= nil
			then labelForScore(feedbackKey)
			elseif reason ~= nil then labelForReason(reason)
			else "Score updated",
		detail = joinParts(detailParts),
		totalText = string.format("Score %d", math.floor(totalPoints)),
		tone = tone,
	}
end

return ScoreFeedbackPresentation
