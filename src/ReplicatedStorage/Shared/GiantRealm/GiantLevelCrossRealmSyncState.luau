--!strict

local GiantLevelConfig = require("../Config/GiantLevelConfig")
local GiantLevelState = require("./GiantLevelState")

local GiantLevelCrossRealmSyncState: any = {}

export type PendingXpBuffer = {
	realmId: string,
	updatedAt: number,
	events: { GiantLevelState.XpEventRecord },
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function cloneEventRecord(record: GiantLevelState.XpEventRecord): GiantLevelState.XpEventRecord
	return {
		operationId = record.operationId,
		eventKind = record.eventKind,
		xpAwarded = record.xpAwarded,
		awardedAt = record.awardedAt,
	}
end

local function sortEvents(events: { GiantLevelState.XpEventRecord })
	table.sort(events, function(a: GiantLevelState.XpEventRecord, b: GiantLevelState.XpEventRecord): boolean
		if a.awardedAt ~= b.awardedAt then
			return a.awardedAt < b.awardedAt
		end
		return a.operationId < b.operationId
	end)
end

function GiantLevelCrossRealmSyncState.NewPendingXpBuffer(realmId: string, now: number): PendingXpBuffer
	return {
		realmId = realmId,
		updatedAt = now,
		events = {},
	}
end

function GiantLevelCrossRealmSyncState.ValidatePendingXpBuffer(buffer: any): (boolean, string?)
	if type(buffer) ~= "table" then
		return false, "pending_buffer_invalid"
	end
	if nonEmptyString(buffer.realmId) == nil then
		return false, "pending_realm_id_invalid"
	end
	if not isFiniteNumber(buffer.updatedAt) or buffer.updatedAt < 0 then
		return false, "pending_updated_at_invalid"
	end
	if type(buffer.events) ~= "table" then
		return false, "pending_events_invalid"
	end

	local seenOperationIds: { [string]: boolean } = {}
	for index, record in ipairs(buffer.events) do
		local valid, reason = GiantLevelState.ValidateEventRecord(record)
		if not valid then
			return false, string.format("%s index=%d", reason or "pending_event_invalid", index)
		end
		if seenOperationIds[record.operationId] == true then
			return false, string.format("pending_operation_id_duplicate index=%d", index)
		end
		seenOperationIds[record.operationId] = true
	end

	return true, nil
end

function GiantLevelCrossRealmSyncState.MergePendingBuffers(
	left: PendingXpBuffer?,
	right: PendingXpBuffer?
): PendingXpBuffer?
	if left == nil then
		return right
	end
	if right == nil then
		return left
	end
	if left.realmId ~= right.realmId then
		return nil
	end

	local mergedEvents: { GiantLevelState.XpEventRecord } = {}
	local seenOperationIds: { [string]: boolean } = {}

	local function appendUnique(record: GiantLevelState.XpEventRecord)
		if seenOperationIds[record.operationId] == true then
			return
		end
		seenOperationIds[record.operationId] = true
		table.insert(mergedEvents, cloneEventRecord(record))
	end

	for _, record in ipairs(left.events) do
		appendUnique(record)
	end
	for _, record in ipairs(right.events) do
		appendUnique(record)
	end

	sortEvents(mergedEvents)

	return {
		realmId = left.realmId,
		updatedAt = math.max(left.updatedAt, right.updatedAt),
		events = mergedEvents,
	}
end

function GiantLevelCrossRealmSyncState.AppendPendingEvent(
	buffer: PendingXpBuffer?,
	record: GiantLevelState.XpEventRecord,
	now: number,
	realmIdOverride: string?
): (PendingXpBuffer?, string?)
	local realmId = nonEmptyString(if buffer ~= nil then buffer.realmId else realmIdOverride)
	if realmId == nil then
		return nil, "pending_realm_id_invalid"
	end

	local valid, reason = GiantLevelState.ValidateEventRecord(record)
	if not valid then
		return nil, reason or "pending_event_invalid"
	end
	if not isFiniteNumber(now) or now < 0 then
		return nil, "pending_now_invalid"
	end

	local nextBuffer = if buffer ~= nil
		then {
			realmId = buffer.realmId,
			updatedAt = now,
			events = {},
		}
		else GiantLevelCrossRealmSyncState.NewPendingXpBuffer(realmId, now)

	for _, existing in ipairs(if buffer ~= nil then buffer.events else {}) do
		table.insert(nextBuffer.events, cloneEventRecord(existing))
	end

	for _, existing in ipairs(nextBuffer.events) do
		if existing.operationId == record.operationId then
			return nextBuffer, "duplicate"
		end
	end

	table.insert(nextBuffer.events, cloneEventRecord(record))
	sortEvents(nextBuffer.events)

	while #nextBuffer.events > GiantLevelConfig.MaxRetainedRecentEvents do
		table.remove(nextBuffer.events, 1)
	end

	return nextBuffer, nil
end

function GiantLevelCrossRealmSyncState.PruneAcknowledgedOperationIds(
	buffer: PendingXpBuffer?,
	acknowledgedOperationIds: { [string]: boolean },
	now: number
): PendingXpBuffer?
	if buffer == nil then
		return nil
	end

	local nextEvents: { GiantLevelState.XpEventRecord } = {}
	for _, record in ipairs(buffer.events) do
		if acknowledgedOperationIds[record.operationId] ~= true then
			table.insert(nextEvents, cloneEventRecord(record))
		end
	end

	if #nextEvents == 0 then
		return nil
	end

	return {
		realmId = buffer.realmId,
		updatedAt = now,
		events = nextEvents,
	}
end

function GiantLevelCrossRealmSyncState.CollectAcknowledgedOperationIds(persistenceRaw: any): { [string]: boolean }
	local acknowledged: { [string]: boolean } = {}
	if type(persistenceRaw) ~= "table" or type(persistenceRaw.recentEvents) ~= "table" then
		return acknowledged
	end

	for _, record in ipairs(persistenceRaw.recentEvents) do
		if type(record) == "table" and type(record.operationId) == "string" and record.operationId ~= "" then
			acknowledged[record.operationId] = true
		end
	end

	return acknowledged
end

function GiantLevelCrossRealmSyncState.ReplayPendingEventsOntoState(
	state: GiantLevelState.State,
	pendingEvents: { GiantLevelState.XpEventRecord }
): (GiantLevelState.State, { string })
	local nextState = state
	local appliedOperationIds: { string } = {}

	for _, record in ipairs(pendingEvents) do
		local result = GiantLevelState.ApplyXpEvent(nextState, {
			operationId = record.operationId,
			eventKind = record.eventKind,
			awardedAt = record.awardedAt,
		})
		if type(result) == "table" and result.accepted == true and type(result.state) == "table" then
			nextState = result.state
			table.insert(appliedOperationIds, record.operationId)
		end
	end

	return nextState, appliedOperationIds
end

function GiantLevelCrossRealmSyncState.MergePersistenceWithPending(
	persistenceRaw: any,
	pendingBuffer: PendingXpBuffer?
): any
	local applied = GiantLevelState.ApplyPersistenceState(persistenceRaw)
	if applied.accepted ~= true or type(applied.state) ~= "table" then
		return applied
	end

	if pendingBuffer == nil or #pendingBuffer.events == 0 then
		return applied
	end

	local mergedState, _appliedIds =
		GiantLevelCrossRealmSyncState.ReplayPendingEventsOntoState(applied.state, pendingBuffer.events)
	local serialized = GiantLevelState.SerializePersistenceState(mergedState)
	local replayApplied = GiantLevelState.ApplyPersistenceState(serialized)
	if replayApplied.accepted ~= true or type(replayApplied.state) ~= "table" then
		return applied
	end

	return {
		accepted = true,
		reason = "accepted",
		state = replayApplied.state,
		needsEntitlementReconcile = applied.needsEntitlementReconcile == true
			or replayApplied.needsEntitlementReconcile == true,
	}
end

local function encodeEventRecord(record: GiantLevelState.XpEventRecord): string
	return table.concat({
		record.operationId,
		record.eventKind,
		tostring(record.xpAwarded),
		tostring(record.awardedAt),
	}, ";")
end

local function decodeEventRecord(encoded: string): GiantLevelState.XpEventRecord?
	local parts = string.split(encoded, ";")
	if #parts ~= 4 then
		return nil
	end

	local xpAwarded = tonumber(parts[3])
	local awardedAt = tonumber(parts[4])
	if xpAwarded == nil or awardedAt == nil then
		return nil
	end

	return {
		operationId = parts[1],
		eventKind = parts[2],
		xpAwarded = xpAwarded,
		awardedAt = awardedAt,
	}
end

function GiantLevelCrossRealmSyncState.EncodePendingXpBuffer(buffer: PendingXpBuffer): (string?, string?)
	local valid, reason = GiantLevelCrossRealmSyncState.ValidatePendingXpBuffer(buffer)
	if not valid then
		return nil, reason or "pending_buffer_invalid"
	end

	local eventLines = {}
	for _, record in ipairs(buffer.events) do
		table.insert(eventLines, encodeEventRecord(record))
	end
	table.sort(eventLines)

	local header = table.concat({
		"v1",
		buffer.realmId,
		tostring(buffer.updatedAt),
		tostring(#eventLines),
	}, "|")
	if #eventLines == 0 then
		return header, nil
	end
	return header .. "\n" .. table.concat(eventLines, "\n"), nil
end

function GiantLevelCrossRealmSyncState.DecodePendingXpBuffer(encoded: any): (PendingXpBuffer?, string?)
	if type(encoded) ~= "string" or encoded == "" then
		return nil, "stored_payload_invalid"
	end

	local newlineIndex = string.find(encoded, "\n", 1, true)
	local header = if newlineIndex ~= nil then string.sub(encoded, 1, newlineIndex - 1) else encoded
	local body = if newlineIndex ~= nil then string.sub(encoded, newlineIndex + 1) else ""

	local headerParts = string.split(header, "|")
	if #headerParts ~= 4 or headerParts[1] ~= "v1" then
		return nil, "stored_payload_invalid"
	end

	local realmId = nonEmptyString(headerParts[2])
	local updatedAt = tonumber(headerParts[3])
	local eventCount = tonumber(headerParts[4])
	if realmId == nil or updatedAt == nil or eventCount == nil then
		return nil, "stored_payload_invalid"
	end
	if not isFiniteNumber(updatedAt) or eventCount < 0 or eventCount % 1 ~= 0 then
		return nil, "stored_payload_invalid"
	end

	local events: { GiantLevelState.XpEventRecord } = {}
	if eventCount > 0 then
		if body == "" then
			return nil, "stored_payload_invalid"
		end
		local eventLines = string.split(body, "\n")
		if #eventLines ~= eventCount then
			return nil, "stored_payload_invalid"
		end
		for _, line in ipairs(eventLines) do
			local record = decodeEventRecord(line)
			if record == nil then
				return nil, "stored_event_invalid"
			end
			table.insert(events, record)
		end
	end

	local buffer: PendingXpBuffer = {
		realmId = realmId,
		updatedAt = updatedAt,
		events = events,
	}
	local valid, validateReason = GiantLevelCrossRealmSyncState.ValidatePendingXpBuffer(buffer)
	if not valid then
		return nil, validateReason or "pending_buffer_invalid"
	end
	return buffer, nil
end

return GiantLevelCrossRealmSyncState
