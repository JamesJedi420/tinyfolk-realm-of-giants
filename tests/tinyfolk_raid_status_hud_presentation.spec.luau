--!strict

local Config = require("../src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local Presentation = require("../src/ReplicatedStorage/Shared/TinyfolkStatus/TinyfolkRaidHudPresentation")

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
	local model = Presentation.BuildHudModel(Config, { Role = "Giant" })
	assertFalse(model.visible, "non-tinyfolk hidden")
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudSummary = "threat_medium|threat|warning|||;captured|custody|critical|||;bleed|personal_effect|warning|||;teammate_rescue_111|teammate_activity|info|||;score_capture_success|score_feedback|positive|||",
		RaidHudThreatLevel = "medium",
		RaidHudCustodyState = "captured",
		RaidHudPersonalEffects = "bleed|personal_effect|warning|||",
		RaidHudTeammateActivity = "teammate_rescue_111|teammate_activity|info|||",
		RaidHudScoreFeedback = "score_capture_success|score_feedback|positive|||",
		RaidHudUpdatedAt = 123.45,
	})

	assertTrue(model.visible, "tinyfolk visible")
	assertEqual(model.title, "Tinyfolk Raid Status", "title text")
	assertTrue(contains(model.summary, "Threat: Medium"), "summary threat text")
	assertTrue(contains(model.summary, "Custody: Capture active - release timer running"), "summary custody text")
	assertTrue(contains(model.summary, "Bleed"), "summary personal effect text")
	assertTrue(contains(model.summary, "Teammate: Rescue 111"), "summary teammate text")
	assertTrue(contains(model.summary, "Score: Capture Success"), "summary score text")
	assertEqual(model.threat, "Threat: Medium", "threat line")
	assertEqual(model.custody, "Custody: Capture active - release timer running", "custody line")
	assertEqual(model.personalEffects, "Bleed", "effects line")
	assertEqual(model.teammateActivity, "Teammate: Rescue 111", "team line")
	assertEqual(model.scoreFeedback, "Score: Capture Success", "score line")
	assertEqual(model.updatedAt, "Updated at 123.45", "updated line")
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudSummary = nil,
		RaidHudThreatLevel = nil,
		RaidHudCustodyState = nil,
		RaidHudPersonalEffects = nil,
		RaidHudTeammateActivity = nil,
		RaidHudScoreFeedback = nil,
		RaidHudUpdatedAt = 0 / 0,
	})

	assertEqual(model.summary, "Summary: none", "empty summary fallback")
	assertEqual(model.personalEffects, "Effects: none", "empty effects fallback")
	assertEqual(model.teammateActivity, "Team: none", "empty team fallback")
	assertEqual(model.scoreFeedback, "Score: none", "empty score fallback")
	assertEqual(model.updatedAt, "Updated at --", "invalid update fallback")
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudSummary = "bad|||;valid_summary|threat|warning|||;also_bad|custody|||",
		RaidHudThreatLevel = "low",
	})

	assertTrue(contains(model.summary, "Threat: Valid Summary"), "valid summary retained")
	assertFalse(contains(model.summary, "bad"), "malformed summary chunk ignored")
	assertFalse(contains(model.summary, "also_bad"), "malformed custody chunk ignored")
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudTeammateActivity = "teammate_captured_222|teammate_activity|critical|||",
	})

	assertEqual(
		model.teammateActivity,
		"Teammate: Capture active - rescue window available",
		"teammate captured agency text"
	)
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudSummary = "captured|custody|critical|20|||",
		RaidHudCustodyState = "captured",
		RaidHudUpdatedAt = 11,
	})

	assertEqual(model.summary, "Custody: Capture active - release in 9s", "captured summary shows release countdown")
	assertEqual(model.custody, "Custody: Capture active - release in 9s", "custody line shows release countdown")
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudTeammateActivity = "teammate_captured_222|teammate_activity|critical|20|||;teammate_rescue_333|teammate_activity|info|16|||",
		RaidHudUpdatedAt = 11,
	})

	assertTrue(
		contains(model.teammateActivity, "Teammate: Capture active - rescue window 9s"),
		"teammate captured shows rescue window countdown"
	)
	assertTrue(contains(model.teammateActivity, "Teammate: Rescue window 5s"), "teammate rescue shows rescue countdown")
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudPersonalEffects = "post_rescue_protected|personal_effect|positive|15|||",
		RaidHudUpdatedAt = 11,
	})

	assertEqual(model.personalEffects, "Safe return protection 4s", "post-rescue protection countdown")
end

do
	local model = Presentation.BuildHudModel(Config, {
		Role = "Tinyfolk",
		RaidHudSummary = "captured|custody|critical|10|||",
		RaidHudCustodyState = "captured",
		RaidHudTeammateActivity = "teammate_captured_222|teammate_activity|critical|bad|||",
		RaidHudPersonalEffects = "post_rescue_protected|personal_effect|positive|10|||",
		RaidHudUpdatedAt = 11,
	})

	assertEqual(
		model.custody,
		"Custody: Capture active - release timer running",
		"past release time uses custody fallback"
	)
	assertEqual(
		model.teammateActivity,
		"Teammate: Capture active - rescue window available",
		"invalid teammate time uses rescue fallback"
	)
	assertEqual(model.personalEffects, "Post Rescue Protected", "past protection time uses effect fallback")
end

print("tinyfolk_raid_status_hud_presentation: all checks passed")
