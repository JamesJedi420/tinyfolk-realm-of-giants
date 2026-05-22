--!strict

local RaidStatusProjection: any = {}

export type Entry = {
	id: string,
	category: string,
	severity: string,
	labelKey: string,
	endsAt: number?,
	progressRatio: number?,
	sourceUserId: number?,
	targetUserId: number?,
	privacy: string?,
}

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function positiveUserId(value: any): number?
	local numeric = finiteNumber(value)
	if numeric == nil then
		return nil
	end
	if numeric <= 0 or numeric % 1 ~= 0 then
		return nil
	end
	return numeric
end

local function stringValue(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function boolValue(value: any): boolean
	return value == true
end

local function unitValue(value: any): number?
	local numeric = finiteNumber(value)
	if numeric == nil then
		return nil
	end
	if numeric < 0 then
		return 0
	end
	if numeric > 1 then
		return 1
	end
	return numeric
end

local function sanitizeEndsAt(value: any, now: number?): number?
	local endsAt = finiteNumber(value)
	if endsAt == nil then
		return nil
	end
	if now ~= nil and endsAt <= now then
		return nil
	end
	return endsAt
end

local function addOrRefresh(entriesById: { [string]: Entry }, order: { string }, entry: Entry)
	local existing = entriesById[entry.id]
	if existing == nil then
		entriesById[entry.id] = entry
		table.insert(order, entry.id)
		return
	end

	local currentEndsAt = finiteNumber(existing.endsAt)
	local nextEndsAt = finiteNumber(entry.endsAt)
	if nextEndsAt ~= nil and (currentEndsAt == nil or nextEndsAt > currentEndsAt) then
		existing.endsAt = nextEndsAt
	end
	if entry.progressRatio ~= nil then
		existing.progressRatio = entry.progressRatio
	end
	if entry.sourceUserId ~= nil then
		existing.sourceUserId = entry.sourceUserId
	end
	if entry.targetUserId ~= nil then
		existing.targetUserId = entry.targetUserId
	end
	existing.severity = entry.severity
	existing.labelKey = entry.labelKey
	existing.privacy = entry.privacy
end

local function sortedEntries(entriesById: { [string]: Entry }, order: { string }): { Entry }
	local output: { Entry } = {}
	for _, id in ipairs(order) do
		local entry = entriesById[id]
		if entry ~= nil then
			table.insert(output, entry)
		end
	end
	return output
end

local function getAttr(attributes: any, name: string): any
	if type(attributes) ~= "table" then
		return nil
	end
	return attributes[name]
end

local function getHud(config: any): any
	if type(config) ~= "table" or type(config.RaidHud) ~= "table" then
		return {}
	end
	return config.RaidHud
end

local function categoryName(config: any, key: string, fallback: string): string
	local hud = getHud(config)
	local categories: any = if type(hud.Categories) == "table" then hud.Categories else {}
	local value = categories[key]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function severityName(config: any, key: string, fallback: string): string
	local hud = getHud(config)
	local severity: any = if type(hud.Severity) == "table" then hud.Severity else {}
	local value = severity[key]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function escapeToken(value: any): string
	local text = tostring(value)
	text = string.gsub(text, "|", "/")
	text = string.gsub(text, ";", ",")
	text = string.gsub(text, ":", "_")
	return text
end

local function serializeEntries(entries: { Entry }): string
	local chunks: { string } = {}
	for _, entry in ipairs(entries) do
		table.insert(
			chunks,
			table.concat({
				escapeToken(entry.id),
				escapeToken(entry.category),
				escapeToken(entry.severity),
				escapeToken(entry.endsAt or ""),
				escapeToken(entry.progressRatio or ""),
				escapeToken(entry.sourceUserId or ""),
				escapeToken(entry.targetUserId or ""),
				escapeToken(entry.privacy or ""),
			}, "|")
		)
	end
	return table.concat(chunks, ";")
end

local function resolveThreatLevel(config: any, exposureRatio: any, panicActive: any): string
	local hud = getHud(config)
	local levels: any = hud.ThreatLevels or {}
	if panicActive == true then
		return levels.High or "high"
	end

	local exposure = unitValue(exposureRatio) or 0
	local thresholds: any = hud.ThreatExposureThresholds or {}
	if exposure >= (thresholds.High or 0.75) then
		return levels.High or "high"
	end
	if exposure >= (thresholds.Medium or 0.45) then
		return levels.Medium or "medium"
	end
	if exposure >= (thresholds.Low or 0.1) then
		return levels.Low or "low"
	end
	return levels.None or "none"
end

local function addPersonalEffect(
	config: any,
	entriesById: { [string]: Entry },
	order: { string },
	id: string,
	active: any,
	endsAt: any,
	now: number?
)
	if active ~= true then
		return
	end

	addOrRefresh(entriesById, order, {
		id = id,
		category = categoryName(config, "PersonalEffect", "personal_effect"),
		severity = if id == "stun"
			then severityName(config, "Critical", "critical")
			else severityName(config, "Warning", "warning"),
		labelKey = "raid_status_" .. id,
		endsAt = sanitizeEndsAt(endsAt, now),
		privacy = "self",
	})
end

local function addCustodyEntries(
	config: any,
	entriesById: { [string]: Entry },
	order: { string },
	attrs: any,
	now: number?
)
	local custodyCategory = categoryName(config, "Custody", "custody")

	if boolValue(getAttr(attrs, "Escaped")) then
		addOrRefresh(entriesById, order, {
			id = "escaped",
			category = categoryName(config, "Escape", "escape"),
			severity = severityName(config, "Positive", "positive"),
			labelKey = "raid_status_escaped",
			privacy = "team",
		})
		return "escaped"
	end

	local carriedState = stringValue(getAttr(attrs, "CarriedState"))
	local carriedBy = positiveUserId(getAttr(attrs, "CarriedByUserId"))
	if carriedBy ~= nil or carriedState == "Carried" then
		addOrRefresh(entriesById, order, {
			id = "carried",
			category = custodyCategory,
			severity = severityName(config, "Critical", "critical"),
			labelKey = "raid_status_carried",
			privacy = "opposing_role_redacted",
		})
		return "carried"
	end

	local captureActive = boolValue(getAttr(attrs, "CaptureActive"))
	local captureExpiresAt = sanitizeEndsAt(getAttr(attrs, "CaptureExpiresAt"), now)
	if captureActive and positiveUserId(getAttr(attrs, "CaptureCustodianUserId")) ~= nil then
		addOrRefresh(entriesById, order, {
			id = "captured",
			category = custodyCategory,
			severity = severityName(config, "Critical", "critical"),
			labelKey = "raid_status_captured",
			endsAt = captureExpiresAt,
			privacy = "opposing_role_redacted",
		})
		return "captured"
	end

	if boolValue(getAttr(attrs, "DownedIsDowned")) then
		addOrRefresh(entriesById, order, {
			id = "downed",
			category = custodyCategory,
			severity = severityName(config, "Critical", "critical"),
			labelKey = "raid_status_downed",
			endsAt = sanitizeEndsAt(getAttr(attrs, "DownedExpiresAt"), now),
			progressRatio = unitValue(getAttr(attrs, "DownedSelfRecoveryProgress")),
			privacy = "team",
		})
		return "downed"
	end

	return "free"
end

local function addScoreFeedback(config: any, entriesById: { [string]: Entry }, order: { string }, attrs: any)
	local feedbackKey = stringValue(getAttr(attrs, "ScoreLastFeedbackKey"))
	if feedbackKey == nil then
		return
	end

	addOrRefresh(entriesById, order, {
		id = "score_feedback",
		category = categoryName(config, "ScoreFeedback", "score_feedback"),
		severity = if boolValue(getAttr(attrs, "ScoreLastCategoryCapReached"))
			then severityName(config, "Warning", "warning")
			else severityName(config, "Positive", "positive"),
		labelKey = feedbackKey,
		progressRatio = nil,
		privacy = "self",
	})
end

local function threatLevelName(config: any, key: string, fallback: string): string
	local levels = getHud(config).ThreatLevels or {}
	local value = levels[key]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function warningLevelName(config: any, key: string, fallback: string): string
	local warningConfig: any = if type(config) == "table" and type(config.GiantProximityWarning) == "table"
		then config.GiantProximityWarning
		else {}
	local levels: any = if type(warningConfig.Levels) == "table" then warningConfig.Levels else {}
	local value = levels[key]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function addThreatEntry(config: any, entriesById: { [string]: Entry }, order: { string }, threatLevel: string)
	if threatLevel == threatLevelName(config, "None", "none") then
		return
	end

	local highLevel = threatLevelName(config, "High", "high")
	addOrRefresh(entriesById, order, {
		id = "threat_" .. threatLevel,
		category = categoryName(config, "Threat", "threat"),
		severity = if threatLevel == highLevel
			then severityName(config, "Critical", "critical")
			else severityName(config, "Warning", "warning"),
		labelKey = "raid_status_threat_" .. threatLevel,
		privacy = "opposing_role_redacted",
	})
end

local function addThreatStageEntry(
	config: any,
	entriesById: { [string]: Entry },
	order: { string },
	threatStage: string
)
	if threatStage == "" or threatStage == "calm" then
		return
	end

	addOrRefresh(entriesById, order, {
		id = "threat_stage_" .. threatStage,
		category = categoryName(config, "Threat", "threat"),
		severity = if threatStage == "critical"
			then severityName(config, "Critical", "critical")
			elseif threatStage == "pressure" then severityName(config, "Warning", "warning")
			else severityName(config, "Info", "info"),
		labelKey = "raid_status_threat_stage_" .. threatStage,
		privacy = "opposing_role_redacted",
	})
end

local function resolveWarningLevel(config: any, value: any): string?
	local hud = getHud(config)
	local warningConfig: any = if type(config) == "table" and type(config.GiantProximityWarning) == "table"
		then config.GiantProximityWarning
		else {}
	local levels: any = if type(warningConfig.Levels) == "table" then warningConfig.Levels else {}
	local resolved = stringValue(value)
	if resolved == nil then
		return nil
	end

	local allowed = {
		[levels.Watch or "watch"] = true,
		[levels.Near or "near"] = true,
		[levels.Danger or "danger"] = true,
		[levels.None or "none"] = true,
	}
	if allowed[resolved] == true then
		return resolved
	end

	local threatLevels: any = hud.ThreatLevels or {}
	if resolved == (threatLevels.Low or "low") then
		return levels.Watch or "watch"
	end
	if resolved == (threatLevels.Medium or "medium") then
		return levels.Near or "near"
	end
	if resolved == (threatLevels.High or "high") then
		return levels.Danger or "danger"
	end
	return nil
end

local function addGiantProximityWarningEntry(
	config: any,
	entriesById: { [string]: Entry },
	order: { string },
	warningLevel: string
)
	local noneLevel = warningLevelName(config, "None", "none")
	if warningLevel == noneLevel then
		return
	end
	local dangerLevel = warningLevelName(config, "Danger", "danger")
	local watchLevel = warningLevelName(config, "Watch", "watch")

	addOrRefresh(entriesById, order, {
		id = "giant_proximity_warning_" .. warningLevel,
		category = categoryName(config, "Threat", "threat"),
		severity = if warningLevel == dangerLevel
			then severityName(config, "Critical", "critical")
			elseif warningLevel == watchLevel then severityName(config, "Info", "info")
			else severityName(config, "Warning", "warning"),
		labelKey = "raid_status_giant_proximity_" .. warningLevel,
		privacy = "opposing_role_redacted",
	})
end

local function addTeammateActivity(
	config: any,
	entriesById: { [string]: Entry },
	order: { string },
	teammate: any,
	now: number?
)
	if type(teammate) ~= "table" then
		return
	end

	local role = stringValue(teammate.role or getAttr(teammate.attributes, "Role"))
	if role ~= "Tinyfolk" then
		return
	end

	local userId = positiveUserId(teammate.userId)
	if userId == nil then
		return
	end

	local attrs = teammate.attributes or {}
	local category = categoryName(config, "TeammateActivity", "teammate_activity")

	if boolValue(getAttr(attrs, "Escaped")) then
		addOrRefresh(entriesById, order, {
			id = "teammate_escaped_" .. tostring(userId),
			category = category,
			severity = severityName(config, "Positive", "positive"),
			labelKey = "raid_status_teammate_escaped",
			sourceUserId = userId,
			privacy = "team",
		})
		return
	end

	if
		boolValue(getAttr(attrs, "CaptureActive"))
		and positiveUserId(getAttr(attrs, "CaptureCustodianUserId")) ~= nil
	then
		addOrRefresh(entriesById, order, {
			id = "teammate_captured_" .. tostring(userId),
			category = category,
			severity = severityName(config, "Critical", "critical"),
			labelKey = "raid_status_teammate_captured",
			sourceUserId = userId,
			endsAt = sanitizeEndsAt(getAttr(attrs, "CaptureExpiresAt"), now),
			privacy = "opposing_role_redacted",
		})
		return
	end

	if boolValue(getAttr(attrs, "DownedIsDowned")) then
		addOrRefresh(entriesById, order, {
			id = "teammate_downed_" .. tostring(userId),
			category = category,
			severity = severityName(config, "Critical", "critical"),
			labelKey = "raid_status_teammate_downed",
			sourceUserId = userId,
			endsAt = sanitizeEndsAt(getAttr(attrs, "DownedExpiresAt"), now),
			privacy = "team",
		})
		return
	end

	if boolValue(getAttr(attrs, "RescueContractActive")) then
		addOrRefresh(entriesById, order, {
			id = "teammate_rescue_" .. tostring(userId),
			category = category,
			severity = severityName(config, "Info", "info"),
			labelKey = "raid_status_teammate_rescue",
			sourceUserId = userId,
			targetUserId = positiveUserId(getAttr(attrs, "RescueContractTargetUserId"))
				or positiveUserId(getAttr(attrs, "RescueContractRescuerUserId")),
			endsAt = sanitizeEndsAt(getAttr(attrs, "RescueContractExpiresAt"), now),
			privacy = "team",
		})
	end
end

function RaidStatusProjection.BuildPlayerProjection(config: any, input: any): any
	local projectionConfig = if type(config) == "table" then config :: any else {} :: any
	local attrs = if type(input) == "table" then input.attributes else nil
	local now = if type(input) == "table" then finiteNumber(input.now) else nil
	local entriesById: { [string]: Entry } = {}
	local order: { string } = {}
	local configAttrs: any = projectionConfig.Attributes or {}

	addPersonalEffect(
		projectionConfig,
		entriesById,
		order,
		"bleed",
		getAttr(attrs, configAttrs.BleedActive or "TinyfolkBleedActive"),
		getAttr(attrs, configAttrs.BleedUntil or "TinyfolkBleedUntil"),
		now
	)
	addPersonalEffect(
		projectionConfig,
		entriesById,
		order,
		"stun",
		getAttr(attrs, configAttrs.StunActive or "TinyfolkStunActive"),
		getAttr(attrs, configAttrs.StunUntil or "TinyfolkStunUntil"),
		now
	)
	addPersonalEffect(
		projectionConfig,
		entriesById,
		order,
		"flux",
		getAttr(attrs, configAttrs.FluxActive or "TinyfolkFluxActive"),
		getAttr(attrs, configAttrs.FluxUntil or "TinyfolkFluxUntil"),
		now
	)

	if boolValue(getAttr(attrs, "PostRescueProtected")) then
		addOrRefresh(entriesById, order, {
			id = "post_rescue_protected",
			category = categoryName(projectionConfig, "PersonalEffect", "personal_effect"),
			severity = severityName(projectionConfig, "Positive", "positive"),
			labelKey = "raid_status_post_rescue_protected",
			endsAt = sanitizeEndsAt(getAttr(attrs, "PostRescueProtectionExpiresAt"), now),
			privacy = "self",
		})
	end

	if boolValue(getAttr(attrs, "RescueAccelerationActive")) then
		addOrRefresh(entriesById, order, {
			id = "rescue_acceleration",
			category = categoryName(projectionConfig, "PersonalEffect", "personal_effect"),
			severity = severityName(projectionConfig, "Positive", "positive"),
			labelKey = "raid_status_rescue_acceleration",
			endsAt = sanitizeEndsAt(getAttr(attrs, "RescueAccelerationExpiresAt"), now),
			privacy = "self",
		})
	end

	local custodyState = addCustodyEntries(projectionConfig, entriesById, order, attrs, now)
	local exposureRatio = unitValue(getAttr(attrs, configAttrs.FearExposureRatio or "TinyfolkFearExposureRatio"))
	local threatLevel = resolveThreatLevel(
		projectionConfig,
		exposureRatio,
		getAttr(attrs, configAttrs.FearPanic or "TinyfolkFearPanic")
	)
	local warningLevel = resolveWarningLevel(
		projectionConfig,
		getAttr(attrs, configAttrs.GiantProximityWarningLevel or "TinyfolkGiantProximityWarningLevel")
	)
	local threatStage = stringValue(getAttr(attrs, configAttrs.RaidHudThreatStage or "TinyfolkRaidHudThreatStage"))
	if warningLevel == nil then
		local threatLevels = getHud(projectionConfig).ThreatLevels or {}
		warningLevel = if threatLevel == (threatLevels.Low or "low")
			then "watch"
			elseif threatLevel == (threatLevels.Medium or "medium") then "near"
			elseif threatLevel == (threatLevels.High or "high") then "danger"
			else "none"
	end
	local resolvedWarningLevel = warningLevel or "none"
	addThreatEntry(projectionConfig, entriesById, order, threatLevel)
	addThreatStageEntry(projectionConfig, entriesById, order, threatStage or "calm")
	addGiantProximityWarningEntry(projectionConfig, entriesById, order, resolvedWarningLevel)
	addScoreFeedback(projectionConfig, entriesById, order, attrs)

	local teammates = if type(input) == "table" and type(input.teammates) == "table" then input.teammates else {}
	for _, teammate in ipairs(teammates) do
		addTeammateActivity(projectionConfig, entriesById, order, teammate, now)
	end

	local entries = sortedEntries(entriesById, order)
	return {
		entries = entries,
		summary = serializeEntries(entries),
		threatLevel = threatLevel,
		threatStage = threatStage or "calm",
		giantProximityWarningLevel = resolvedWarningLevel,
		custodyState = custodyState,
		personalEffects = serializeEntries((function()
			local filtered: { Entry } = {}
			for _, entry in ipairs(entries) do
				if entry.category == categoryName(projectionConfig, "PersonalEffect", "personal_effect") then
					table.insert(filtered, entry)
				end
			end
			return filtered
		end)()),
		teammateActivity = serializeEntries((function()
			local filtered: { Entry } = {}
			for _, entry in ipairs(entries) do
				if entry.category == categoryName(projectionConfig, "TeammateActivity", "teammate_activity") then
					table.insert(filtered, entry)
				end
			end
			return filtered
		end)()),
		scoreFeedback = serializeEntries((function()
			local filtered: { Entry } = {}
			for _, entry in ipairs(entries) do
				if entry.category == categoryName(projectionConfig, "ScoreFeedback", "score_feedback") then
					table.insert(filtered, entry)
				end
			end
			return filtered
		end)()),
	}
end

return RaidStatusProjection
