--!strict

local ModerationReportConfig = require("../Config/ModerationReportConfig")

local ModerationReportState = {}

export type SanitizedEvent = {
	sequence: number,
	timestamp: number,
	category: string,
	message: string,
	severity: string,
	metadata: any?,
}

export type ReportContext = {
	reportId: string,
	surfaceKind: string,
	realmId: string,
	sessionId: string,
	reporterUserId: number,
	capturingUserId: number?,
	capturedUserId: number?,
	generatedAt: number,
	recentEvents: { SanitizedEvent },
	surfaceDetails: any?,
	abuseSignals: any?,
}

export type State = {
	exportSequence: number,
	lastReason: string?,
}

export type BuildInput = {
	now: number,
	reporterUserId: number,
	surfaceKind: string,
	realmId: string?,
	sessionId: string?,
	capturingUserId: number?,
	capturedUserId: number?,
	recentEvents: { any }?,
	surfaceDetails: any?,
	abuseSignals: any?,
}

export type BuildResult = {
	accepted: boolean,
	reason: string,
	context: ReportContext?,
}

export type AffordanceInput = {
	captureActive: boolean?,
	custodyTransferPending: boolean?,
	ransomOfferActive: boolean?,
	repeatedBlockingFlagged: boolean?,
	rescueBlocked: boolean?,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function positiveUserId(value: any): number?
	if not isFiniteNumber(value) then
		return nil
	end
	if value <= 0 or value % 1 ~= 0 then
		return nil
	end
	return value
end

local function nonEmptyString(value: any): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local blockedKeyLookup: { [string]: boolean } = {}
for _, key in ipairs(ModerationReportConfig.BlockedMetadataKeys) do
	blockedKeyLookup[string.lower(key)] = true
end

local allowedCategoryLookup: { [string]: boolean } = {}
for _, category in ipairs(ModerationReportConfig.ReportEventCategories) do
	allowedCategoryLookup[category] = true
end

local surfaceKindLookup: { [string]: boolean } = {}
for _, surfaceKind in pairs(ModerationReportConfig.SurfaceKinds) do
	surfaceKindLookup[surfaceKind] = true
end

local function isBlockedMetadataKey(key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	return blockedKeyLookup[string.lower(key)] == true
end

local cloneSanitizedValue: (value: any, depth: number) -> any
cloneSanitizedValue = function(value: any, depth: number): any
	if depth > 4 then
		return nil
	end

	if type(value) ~= "table" then
		if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
			return value
		end
		return nil
	end

	local output: any = {}
	for key, childValue in pairs(value) do
		if not isBlockedMetadataKey(key) then
			local sanitizedChild = cloneSanitizedValue(childValue, depth + 1)
			if sanitizedChild ~= nil then
				output[cloneSanitizedValue(key, depth + 1)] = sanitizedChild
			end
		end
	end
	return output
end

function ModerationReportState.SanitizeMetadata(metadata: any): any?
	if metadata == nil then
		return nil
	end
	if type(metadata) ~= "table" then
		return nil
	end
	return cloneSanitizedValue(metadata, 0)
end

function ModerationReportState.SanitizeEventRecord(record: any): SanitizedEvent?
	if type(record) ~= "table" then
		return nil
	end

	local category = nonEmptyString(record.category)
	local message = nonEmptyString(record.message)
	local severity = nonEmptyString(record.severity)
	local timestamp = record.timestamp
	local sequence = record.sequence
	if category == nil or message == nil or severity == nil then
		return nil
	end
	if not isFiniteNumber(timestamp) or not isFiniteNumber(sequence) then
		return nil
	end
	if allowedCategoryLookup[category] ~= true then
		return nil
	end

	return {
		sequence = sequence,
		timestamp = timestamp,
		category = category,
		message = message,
		severity = severity,
		metadata = ModerationReportState.SanitizeMetadata(record.metadata),
	}
end

function ModerationReportState.FilterRecentEvents(events: { any }?, limit: number?): { SanitizedEvent }
	local output: { SanitizedEvent } = {}
	if type(events) ~= "table" then
		return output
	end

	local resolvedLimit = ModerationReportConfig.MaxRecentEvents
	if type(limit) == "number" and limit > 0 then
		resolvedLimit = math.min(math.floor(limit), ModerationReportConfig.MaxRecentEvents)
	end

	for index = #events, 1, -1 do
		local sanitized = ModerationReportState.SanitizeEventRecord(events[index])
		if sanitized ~= nil then
			table.insert(output, 1, sanitized)
		end
		if #output >= resolvedLimit then
			break
		end
	end

	return output
end

function ModerationReportState.NewState(): State
	return {
		exportSequence = 0,
		lastReason = nil,
	}
end

function ModerationReportState.MakeReportId(
	state: State,
	reporterUserId: number,
	surfaceKind: string,
	now: number
): (State, string)
	local nextState = {
		exportSequence = state.exportSequence + 1,
		lastReason = state.lastReason,
	}
	local atMillis = math.floor(now * 1000)
	local reportId =
		string.format("report_%d_%s_%d_%d", reporterUserId, surfaceKind, atMillis, nextState.exportSequence)
	return nextState, reportId
end

function ModerationReportState.BuildReportContext(state: State, input: BuildInput): (State, BuildResult)
	local nextState = {
		exportSequence = state.exportSequence,
		lastReason = state.lastReason,
	}

	local reporterUserId = positiveUserId(input.reporterUserId)
	local surfaceKind = nonEmptyString(input.surfaceKind)
	local now = input.now
	if reporterUserId == nil then
		nextState.lastReason = "reporter_user_id_invalid"
		return nextState, { accepted = false, reason = "reporter_user_id_invalid", context = nil }
	end
	if surfaceKind == nil or surfaceKindLookup[surfaceKind] ~= true then
		nextState.lastReason = "surface_kind_invalid"
		return nextState, { accepted = false, reason = "surface_kind_invalid", context = nil }
	end
	if not isFiniteNumber(now) or now < 0 then
		nextState.lastReason = "timestamp_invalid"
		return nextState, { accepted = false, reason = "timestamp_invalid", context = nil }
	end

	local realmId = nonEmptyString(input.realmId) or "unknown_realm"
	local sessionId = nonEmptyString(input.sessionId) or "unknown_session"
	local reportId: string
	nextState, reportId = ModerationReportState.MakeReportId(nextState, reporterUserId, surfaceKind, now)

	local context: ReportContext = {
		reportId = reportId,
		surfaceKind = surfaceKind,
		realmId = realmId,
		sessionId = sessionId,
		reporterUserId = reporterUserId,
		capturingUserId = positiveUserId(input.capturingUserId),
		capturedUserId = positiveUserId(input.capturedUserId),
		generatedAt = now,
		recentEvents = ModerationReportState.FilterRecentEvents(input.recentEvents),
		surfaceDetails = ModerationReportState.SanitizeMetadata(input.surfaceDetails),
		abuseSignals = ModerationReportState.SanitizeMetadata(input.abuseSignals),
	}

	nextState.lastReason = "accepted"
	return nextState, {
		accepted = true,
		reason = "accepted",
		context = context,
	}
end

function ModerationReportState.ResolveAffordanceSurfaces(input: AffordanceInput): { string }
	local surfaces: { string } = {}
	local kinds = ModerationReportConfig.SurfaceKinds

	if input.captureActive == true then
		table.insert(surfaces, kinds.Capture)
	end
	if input.custodyTransferPending == true then
		table.insert(surfaces, kinds.CustodyTransfer)
	end
	if input.ransomOfferActive == true then
		table.insert(surfaces, kinds.Ransom)
	end
	if input.repeatedBlockingFlagged == true then
		table.insert(surfaces, kinds.RepeatedBlocking)
	end
	if input.rescueBlocked == true then
		table.insert(surfaces, kinds.RescueBlocking)
	end

	return surfaces
end

function ModerationReportState.SerializeAffordanceSurfaces(surfaces: { string }): string
	local parts: { string } = {}
	for _, surfaceKind in ipairs(surfaces) do
		if surfaceKindLookup[surfaceKind] == true then
			table.insert(parts, surfaceKind)
		end
	end
	return table.concat(parts, ",")
end

function ModerationReportState.ParseAffordanceSurfaces(serialized: any): { string }
	if type(serialized) ~= "string" or serialized == "" then
		return {}
	end

	local surfaces: { string } = {}
	for surfaceKind in string.gmatch(serialized, "[^,]+") do
		if surfaceKindLookup[surfaceKind] == true then
			table.insert(surfaces, surfaceKind)
		end
	end
	return surfaces
end

function ModerationReportState.ExportSummary(context: ReportContext): any
	return {
		reportId = context.reportId,
		surfaceKind = context.surfaceKind,
		realmId = context.realmId,
		sessionId = context.sessionId,
		reporterUserId = context.reporterUserId,
		capturingUserId = context.capturingUserId,
		capturedUserId = context.capturedUserId,
		generatedAt = context.generatedAt,
		recentEvents = context.recentEvents,
		surfaceDetails = context.surfaceDetails,
		abuseSignals = context.abuseSignals,
	}
end

return ModerationReportState
