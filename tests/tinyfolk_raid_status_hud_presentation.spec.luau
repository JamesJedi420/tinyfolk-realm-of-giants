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

print("tinyfolk_raid_status_hud_presentation: all checks passed")
