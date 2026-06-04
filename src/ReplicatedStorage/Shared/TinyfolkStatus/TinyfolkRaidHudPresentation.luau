--!strict

local TinyfolkRaidHudPresentation: any = {}

export type Entry = {
	id: string,
	category: string,
	severity: string,
	endsAt: string?,
	progressRatio: string?,
	sourceUserId: string?,
	targetUserId: string?,
	privacy: string?,
}

export type HudModel = {
	visible: boolean,
	title: string,
	status: string,
	summary: string,
	threat: string,
	threatStage: string,
	custody: string,
	personalEffects: string,
	teammateActivity: string,
	scoreFeedback: string,
	updatedAt: string,
	accentTone: string,
}

local function getHud(config: any): any
	if type(config) ~= "table" or type(config.RaidHud) ~= "table" then
		return {}
	end
	return config.RaidHud
end

local function titleCase(value: any): string
	if type(value) ~= "string" or value == "" then
		return ""
	end

	local normalized = string.gsub(string.lower(value), "[_%-]+", " ")
	local words: { string } = {}
	for word in string.gmatch(normalized, "%S+") do
		local head = string.upper(string.sub(word, 1, 1))
		local tail = string.sub(word, 2)
		table.insert(words, head .. tail)
	end
	return table.concat(words, " ")
end

local function splitEntries(serialized: any): { Entry }
	if type(serialized) ~= "string" or serialized == "" then
		return {}
	end

	local entries: { Entry } = {}
	for chunk in string.gmatch(serialized, "[^;]+") do
		local parts = string.split(chunk, "|")
		if
			parts[1] == nil
			or parts[1] == ""
			or parts[2] == nil
			or parts[2] == ""
			or parts[3] == nil
			or parts[3] == ""
		then
			continue
		end
		table.insert(entries, {
			id = parts[1] or "",
			category = parts[2] or "",
			severity = parts[3] or "",
			endsAt = parts[4],
			progressRatio = parts[5],
			sourceUserId = parts[6],
			targetUserId = parts[7],
			privacy = parts[8],
		})
	end

	return entries
end

local function joinTexts(values: { string }): string
	local filtered: { string } = {}
	for _, value in ipairs(values) do
		if type(value) == "string" and value ~= "" then
			table.insert(filtered, value)
		end
	end

	return table.concat(filtered, " • ")
end

local function formatCustodyState(state: string): string
	if state == "captured" then
		return "Capture active - release timer running"
	end
	return titleCase(state)
end

local function formatEntry(entry: Entry, hud: any): string
	local categories: any = if type(hud.Categories) == "table" then hud.Categories else {}
	local threatCategory = categories.Threat or "threat"
	local custodyCategory = categories.Custody or "custody"
	local personalEffectCategory = categories.PersonalEffect or "personal_effect"
	local teammateCategory = categories.TeammateActivity or "teammate_activity"
	local scoreCategory = categories.ScoreFeedback or "score_feedback"
	local escapeCategory = categories.Escape or "escape"

	if entry.category == threatCategory then
		local label = entry.id
		if string.find(label, "giant_proximity_warning_", 1, true) == 1 then
			return string.format("Warning: %s", titleCase(string.sub(label, 24)))
		end
		if string.find(label, "threat_", 1, true) == 1 then
			return string.format("Threat: %s", titleCase(string.sub(label, 8)))
		end
		return string.format("Threat: %s", titleCase(label))
	end

	if entry.category == custodyCategory then
		return string.format("Custody: %s", formatCustodyState(entry.id))
	end

	if entry.category == personalEffectCategory then
		return titleCase(entry.id)
	end

	if entry.category == teammateCategory then
		local text = entry.id
		if string.find(text, "teammate_captured_", 1, true) == 1 then
			return "Teammate: Capture active - rescue window available"
		end
		if string.find(text, "teammate_", 1, true) == 1 then
			text = string.sub(text, 10)
		end
		return string.format("Teammate: %s", titleCase(text))
	end

	if entry.category == scoreCategory then
		local text = entry.id
		if string.find(text, "score_", 1, true) == 1 then
			text = string.sub(text, 7)
		end
		return string.format("Score: %s", titleCase(text))
	end

	if entry.category == escapeCategory then
		return string.format("Escape: %s", titleCase(entry.id))
	end

	return string.format("%s: %s", titleCase(entry.category), titleCase(entry.id))
end

local function formatEntryList(serialized: any, hud: any, emptyLabel: string): string
	local entries = splitEntries(serialized)
	if #entries == 0 then
		return emptyLabel
	end

	local values: { string } = {}
	for _, entry in ipairs(entries) do
		table.insert(values, formatEntry(entry, hud))
	end

	return joinTexts(values)
end

local function formatUpdatedAt(updatedAt: any): string
	if type(updatedAt) ~= "number" or updatedAt ~= updatedAt or updatedAt == math.huge or updatedAt == -math.huge then
		return "Updated at --"
	end

	return string.format("Updated at %.2f", updatedAt)
end

function TinyfolkRaidHudPresentation.BuildHudModel(config: any, attributes: any): HudModel
	local hud = getHud(config)
	local role = if type(attributes) == "table" then attributes.Role else nil
	local visible = role == "Tinyfolk"
	local threatLevel = if type(attributes) == "table" and type(attributes.RaidHudThreatLevel) == "string"
		then attributes.RaidHudThreatLevel
		else "none"
	local threatStage = if type(attributes) == "table" and type(attributes.RaidHudThreatStage) == "string"
		then attributes.RaidHudThreatStage
		else "calm"
	local custodyState = if type(attributes) == "table" and type(attributes.RaidHudCustodyState) == "string"
		then attributes.RaidHudCustodyState
		else "free"

	local summary = formatEntryList(attributes and attributes.RaidHudSummary, hud, "Summary: none")
	local personalEffects = formatEntryList(attributes and attributes.RaidHudPersonalEffects, hud, "Effects: none")
	local teammateActivity = formatEntryList(attributes and attributes.RaidHudTeammateActivity, hud, "Team: none")
	local scoreFeedback = formatEntryList(attributes and attributes.RaidHudScoreFeedback, hud, "Score: none")

	return {
		visible = visible,
		title = "Tinyfolk Raid Status",
		status = if threatStage == "calm"
			then string.format("Threat: %s", titleCase(threatLevel))
			else string.format("Threat: %s / Stage: %s", titleCase(threatLevel), titleCase(threatStage)),
		summary = summary,
		threat = string.format("Threat: %s", titleCase(threatLevel)),
		threatStage = string.format("Stage: %s", titleCase(threatStage)),
		custody = string.format("Custody: %s", formatCustodyState(custodyState)),
		personalEffects = personalEffects,
		teammateActivity = teammateActivity,
		scoreFeedback = scoreFeedback,
		updatedAt = formatUpdatedAt(if type(attributes) == "table" then attributes.RaidHudUpdatedAt else nil),
		accentTone = threatLevel,
	}
end

return TinyfolkRaidHudPresentation
