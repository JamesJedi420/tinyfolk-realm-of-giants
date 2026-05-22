--!strict

local ScoreConfig = require("../src/ReplicatedStorage/Shared/Config/ScoreConfig")
local ScoreFeedbackPresentation = require("../src/ReplicatedStorage/Shared/ScoreFeedbackPresentation")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function contains(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

do
	local model = ScoreFeedbackPresentation.BuildScoreModel(ScoreConfig, {})
	assertFalse(model.visible, "empty attributes hidden")
end

do
	local attrs = {
		ScoreTotal = 300,
		ScoreLastReason = "accepted",
		ScoreLastFeedbackKey = "score_escape_success",
		ScoreLastAwardedPoints = 100,
		ScoreLastBucket = "normal",
		ScoreLastCategoryCapReached = false,
	}
	local model = ScoreFeedbackPresentation.BuildScoreModel(ScoreConfig, attrs)
	assertTrue(model.visible, "score feedback visible")
	assertEqual(model.title, "Score Update", "title text")
	assertEqual(model.headline, "Escape success", "feedback label maps")
	assertTrue(contains(model.detail, "Normal"), "bucket label included")
	assertTrue(contains(model.detail, "+100"), "awarded points included")
	assertTrue(contains(model.detail, "Total 300"), "total included")
	assertEqual(model.totalText, "Score 300", "total text")
	assertEqual(model.tone, "positive", "positive tone")
end

do
	local attrs = {
		ScoreTotal = 0,
		ScoreLastReason = "category_cap_reached",
		ScoreLastFeedbackKey = nil,
		ScoreLastAwardedPoints = 0,
		ScoreLastBucket = "bonus",
		ScoreLastCategoryCapReached = true,
	}
	local model = ScoreFeedbackPresentation.BuildScoreModel(ScoreConfig, attrs)
	assertTrue(model.visible, "rejection still visible")
	assertEqual(model.headline, "Category cap reached", "reason label maps")
	assertTrue(contains(model.detail, "Bonus"), "bucket still included")
	assertTrue(contains(model.detail, "Category cap reached"), "cap note included")
	assertEqual(model.tone, "warning", "warning tone")
end

do
	local model = ScoreFeedbackPresentation.BuildScoreModel(ScoreConfig, {
		ScoreTotal = 0 / 0,
		ScoreLastReason = 123,
		ScoreLastFeedbackKey = "",
		ScoreLastAwardedPoints = math.huge,
		ScoreLastBucket = "",
		ScoreLastCategoryCapReached = false,
	})
	assertFalse(model.visible, "malformed score attrs hidden")
end

do
	local model = ScoreFeedbackPresentation.BuildScoreModel(ScoreConfig, {
		ScoreTotal = 25,
		ScoreLastFeedbackKey = "score_unknown_bonus",
		ScoreLastAwardedPoints = 25,
	})
	assertEqual(model.headline, "Unknown Bonus", "unknown key falls back to title case")
end

print("score_feedback_presentation: all checks passed")
