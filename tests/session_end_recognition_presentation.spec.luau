--!strict

local SessionEndRecognitionPresentation = require("../src/ReplicatedStorage/Shared/SessionEndRecognitionPresentation")

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
	local model = SessionEndRecognitionPresentation.BuildSessionEndRecognitionModel({}, {})
	assertFalse(model.visible, "unresolved route hidden")
end

do
	local model = SessionEndRecognitionPresentation.BuildSessionEndRecognitionModel({
		routeId = "EscapeRoute_A",
		finalExitPhase = "Resolved",
		finalExitResolvedAt = 105,
	}, {
		ScoreTotal = 300,
		ScoreLastFeedbackKey = "score_escape_success",
		ScoreLastAwardedPoints = 100,
		ScoreLastBucket = "normal",
	})

	assertTrue(model.visible, "resolved route visible")
	assertEqual(model.title, "Session Complete", "title text")
	assertEqual(model.headline, "EscapeRoute_A resolved", "route headline")
	assertTrue(contains(model.detail, "Latest score: Escape success"), "score detail included")
	assertEqual(model.footer, "Final score 300", "score footer")
	assertEqual(model.tone, "positive", "positive tone")
	assertEqual(model.routeId, "EscapeRoute_A", "route id preserved")
	assertEqual(model.resolvedAt, 105, "resolved timestamp preserved")
	assertEqual(model.totalScore, 300, "total score preserved")
end

do
	local model = SessionEndRecognitionPresentation.BuildSessionEndRecognitionModel({
		routeId = "EscapeRoute_B",
		finalExitPhase = "Resolved",
		finalExitResolvedAt = 210,
	}, {
		ScoreTotal = 0 / 0,
		ScoreLastFeedbackKey = 123,
		ScoreLastAwardedPoints = math.huge,
	})

	assertTrue(model.visible, "malformed score attrs do not hide resolved route")
	assertEqual(model.headline, "EscapeRoute_B resolved", "malformed score route headline")
	assertEqual(model.footer, "Final score unavailable", "malformed score footer fallback")
end

do
	local model = SessionEndRecognitionPresentation.BuildSessionEndRecognitionModel({
		routeId = "EscapeRoute_C",
		finalExitPhase = "Open",
		finalExitResolvedAt = nil,
	}, {
		ScoreTotal = 25,
	})

	assertFalse(model.visible, "non-resolved route hidden")
end

print("session_end_recognition_presentation: all checks passed")
