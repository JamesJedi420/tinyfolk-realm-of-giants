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
	support: string,
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

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function remainingSeconds(entry: Entry, now: number?): number?
	if now == nil then
		return nil
	end

	local endsAt = tonumber(entry.endsAt or "")
	if endsAt == nil or endsAt ~= endsAt or endsAt == math.huge or endsAt == -math.huge then
		return nil
	end

	local remaining = endsAt - now
	if remaining <= 0 then
		return nil
	end

	return math.ceil(remaining)
end

local function formatCountdown(label: string, entry: Entry, now: number?): string?
	local remaining = remainingSeconds(entry, now)
	if remaining == nil then
		return nil
	end
	return string.format("%s %ds", label, remaining)
end

local function formatCustodyState(state: string, entry: Entry?, now: number?): string
	if state == "captured" then
		if entry ~= nil then
			local countdown = formatCountdown("Capture active - release in", entry, now)
			if countdown ~= nil then
				return countdown
			end
		end
		return "Capture active - release timer running"
	end
	if state == "released" then
		return "Release complete"
	end
	if state == "rescued" then
		return "Rescue complete"
	end
	if state == "expired" or state == "timeout" then
		return "Release window ended - safe return available"
	end
	return titleCase(state)
end

local function formatEntry(entry: Entry, hud: any, now: number?): string
	local categories: any = if type(hud.Categories) == "table" then hud.Categories else {}
	local threatCategory = categories.Threat or "threat"
	local custodyCategory = categories.Custody or "custody"
	local personalEffectCategory = categories.PersonalEffect or "personal_effect"
	local teammateCategory = categories.TeammateActivity or "teammate_activity"
	local scoreCategory = categories.ScoreFeedback or "score_feedback"
	local escapeCategory = categories.Escape or "escape"
	local supportCategory = categories.Support or "support"

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
		return string.format("Custody: %s", formatCustodyState(entry.id, entry, now))
	end

	if entry.category == personalEffectCategory then
		if entry.id == "post_rescue_protected" then
			local countdown = formatCountdown("Safe return protection", entry, now)
			if countdown ~= nil then
				return countdown
			end
		end
		return titleCase(entry.id)
	end

	if entry.category == teammateCategory then
		local text = entry.id
		if string.find(text, "teammate_captured_", 1, true) == 1 then
			local countdown = formatCountdown("Teammate: Capture active - rescue window", entry, now)
			if countdown ~= nil then
				return countdown
			end
			return "Teammate: Capture active - rescue window available"
		end
		if string.find(text, "teammate_released_", 1, true) == 1 then
			return "Teammate: Release complete"
		end
		if string.find(text, "teammate_rescued_", 1, true) == 1 then
			return "Teammate: Rescue complete"
		end
		if
			string.find(text, "teammate_expired_", 1, true) == 1
			or string.find(text, "teammate_timeout_", 1, true) == 1
		then
			return "Teammate: Release window ended - safe return available"
		end
		if string.find(text, "teammate_rescue_", 1, true) == 1 then
			local countdown = formatCountdown("Teammate: Rescue window", entry, now)
			if countdown ~= nil then
				return countdown
			end
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

	if entry.category == supportCategory then
		if entry.id == "moderation_report_support" then
			return "Support: Report capture or custody issue (server export available)"
		end
		return string.format("Support: %s", titleCase(entry.id))
	end

	return string.format("%s: %s", titleCase(entry.category), titleCase(entry.id))
end

local function formatEntryList(serialized: any, hud: any, emptyLabel: string, now: number?): string
	local entries = splitEntries(serialized)
	if #entries == 0 then
		return emptyLabel
	end

	local values: { string } = {}
	for _, entry in ipairs(entries) do
		table.insert(values, formatEntry(entry, hud, now))
	end

	return joinTexts(values)
end

local function findEntry(serialized: any, category: string, id: string): Entry?
	for _, entry in ipairs(splitEntries(serialized)) do
		if entry.category == category and entry.id == id then
			return entry
		end
	end
	return nil
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
	local updatedAt = finiteNumber(if type(attributes) == "table" then attributes.RaidHudUpdatedAt else nil)
	local categories: any = if type(hud.Categories) == "table" then hud.Categories else {}
	local custodyCategory = categories.Custody or "custody"
	local custodyEntry = findEntry(attributes and attributes.RaidHudSummary, custodyCategory, custodyState)

	local summary = formatEntryList(attributes and attributes.RaidHudSummary, hud, "Summary: none", updatedAt)
	local personalEffects =
		formatEntryList(attributes and attributes.RaidHudPersonalEffects, hud, "Effects: none", updatedAt)
	local teammateActivity =
		formatEntryList(attributes and attributes.RaidHudTeammateActivity, hud, "Team: none", updatedAt)
	local scoreFeedback = formatEntryList(attributes and attributes.RaidHudScoreFeedback, hud, "Score: none", updatedAt)
	local supportCategory = categories.Support or "support"
	local supportEntry =
		findEntry(attributes and attributes.RaidHudSummary, supportCategory, "moderation_report_support")
	local support = if supportEntry ~= nil
		then "Support: Report capture or custody issue (server export available)"
		else "Support: none"

	return {
		visible = visible,
		title = "Tinyfolk Raid Status",
		status = if threatStage == "calm"
			then string.format("Threat: %s", titleCase(threatLevel))
			else string.format("Threat: %s / Stage: %s", titleCase(threatLevel), titleCase(threatStage)),
		summary = summary,
		threat = string.format("Threat: %s", titleCase(threatLevel)),
		threatStage = string.format("Stage: %s", titleCase(threatStage)),
		custody = string.format("Custody: %s", formatCustodyState(custodyState, custodyEntry, updatedAt)),
		personalEffects = personalEffects,
		teammateActivity = teammateActivity,
		scoreFeedback = scoreFeedback,
		support = support,
		updatedAt = formatUpdatedAt(if type(attributes) == "table" then attributes.RaidHudUpdatedAt else nil),
		accentTone = threatLevel,
	}
end

return TinyfolkRaidHudPresentation
