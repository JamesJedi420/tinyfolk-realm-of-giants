--!strict

local RealmTradeConversionConfig = require("../Config/RealmTradeConversionConfig")
local RealmTradeConversionState = require("./RealmTradeConversionState")

local RealmTradeConversionCrossRealmSyncState: any = {}

export type PendingConversionRecord = {
	operationId: string,
	role: string,
	realmOwnerUserId: number,
	counterpartyUserId: number?,
	convertedAt: number,
	essence: number,
	wood: number,
	stone: number,
}

export type PendingConversionBuffer = {
	realmId: string,
	updatedAt: number,
	conversions: { PendingConversionRecord },
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function cloneConversionRecord(record: PendingConversionRecord): PendingConversionRecord
	return {
		operationId = record.operationId,
		role = record.role,
		realmOwnerUserId = record.realmOwnerUserId,
		counterpartyUserId = record.counterpartyUserId,
		convertedAt = record.convertedAt,
		essence = record.essence,
		wood = record.wood,
		stone = record.stone,
	}
end

local function sortConversions(conversions: { PendingConversionRecord })
	table.sort(conversions, function(a: PendingConversionRecord, b: PendingConversionRecord): boolean
		if a.convertedAt ~= b.convertedAt then
			return a.convertedAt < b.convertedAt
		end
		return a.operationId < b.operationId
	end)
end

function RealmTradeConversionCrossRealmSyncState.ValidateConversionRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "conversion_record_invalid"
	end
	local operationId = nonEmptyString(record.operationId)
	if operationId == nil then
		return false, "conversion_operation_id_invalid"
	end
	local role = nonEmptyString(record.role)
	if role == nil or RealmTradeConversionState.ResolveAwardAmounts(role).accepted ~= true then
		return false, "conversion_role_invalid"
	end
	if not isPositiveInteger(record.realmOwnerUserId) then
		return false, "conversion_realm_owner_invalid"
	end
	if record.counterpartyUserId ~= nil and not isPositiveInteger(record.counterpartyUserId) then
		return false, "conversion_counterparty_invalid"
	end
	if not isFiniteNumber(record.convertedAt) or record.convertedAt < 0 then
		return false, "conversion_converted_at_invalid"
	end
	if not isFiniteNumber(record.essence) or record.essence < 0 then
		return false, "conversion_essence_invalid"
	end
	if not isFiniteNumber(record.wood) or record.wood < 0 then
		return false, "conversion_wood_invalid"
	end
	if not isFiniteNumber(record.stone) or record.stone < 0 then
		return false, "conversion_stone_invalid"
	end
	if record.essence <= 0 and record.wood <= 0 and record.stone <= 0 then
		return false, "conversion_award_zero"
	end
	return true, nil
end

function RealmTradeConversionCrossRealmSyncState.NewPendingConversionBuffer(
	realmId: string,
	now: number
): PendingConversionBuffer
	return {
		realmId = realmId,
		updatedAt = now,
		conversions = {},
	}
end

function RealmTradeConversionCrossRealmSyncState.ValidatePendingConversionBuffer(buffer: any): (boolean, string?)
	if type(buffer) ~= "table" then
		return false, "pending_buffer_invalid"
	end
	if nonEmptyString(buffer.realmId) == nil then
		return false, "pending_realm_id_invalid"
	end
	if not isFiniteNumber(buffer.updatedAt) or buffer.updatedAt < 0 then
		return false, "pending_updated_at_invalid"
	end
	if type(buffer.conversions) ~= "table" then
		return false, "pending_conversions_invalid"
	end

	local seenOperationIds: { [string]: boolean } = {}
	for index, record in ipairs(buffer.conversions) do
		local valid, reason = RealmTradeConversionCrossRealmSyncState.ValidateConversionRecord(record)
		if not valid then
			return false, string.format("%s index=%d", reason or "pending_conversion_invalid", index)
		end
		if seenOperationIds[record.operationId] == true then
			return false, string.format("pending_operation_id_duplicate index=%d", index)
		end
		seenOperationIds[record.operationId] = true
	end

	return true, nil
end

function RealmTradeConversionCrossRealmSyncState.MergePendingBuffers(
	left: PendingConversionBuffer?,
	right: PendingConversionBuffer?
): PendingConversionBuffer?
	if left == nil then
		return right
	end
	if right == nil then
		return left
	end
	if left.realmId ~= right.realmId then
		return nil
	end

	local mergedConversions: { PendingConversionRecord } = {}
	local seenOperationIds: { [string]: boolean } = {}

	local function appendUnique(record: PendingConversionRecord)
		if seenOperationIds[record.operationId] == true then
			return
		end
		seenOperationIds[record.operationId] = true
		table.insert(mergedConversions, cloneConversionRecord(record))
	end

	for _, record in ipairs(left.conversions) do
		appendUnique(record)
	end
	for _, record in ipairs(right.conversions) do
		appendUnique(record)
	end

	sortConversions(mergedConversions)

	return {
		realmId = left.realmId,
		updatedAt = math.max(left.updatedAt, right.updatedAt),
		conversions = mergedConversions,
	}
end

function RealmTradeConversionCrossRealmSyncState.AppendPendingConversion(
	buffer: PendingConversionBuffer?,
	record: PendingConversionRecord,
	now: number,
	realmIdOverride: string?
): (PendingConversionBuffer?, string?)
	local realmId = nonEmptyString(if buffer ~= nil then buffer.realmId else realmIdOverride)
	if realmId == nil then
		return nil, "pending_realm_id_invalid"
	end

	local valid, reason = RealmTradeConversionCrossRealmSyncState.ValidateConversionRecord(record)
	if not valid then
		return nil, reason or "pending_conversion_invalid"
	end
	if not isFiniteNumber(now) or now < 0 then
		return nil, "pending_now_invalid"
	end

	local nextBuffer = if buffer ~= nil
		then {
			realmId = buffer.realmId,
			updatedAt = now,
			conversions = {},
		}
		else RealmTradeConversionCrossRealmSyncState.NewPendingConversionBuffer(realmId, now)

	for _, existing in ipairs(if buffer ~= nil then buffer.conversions else {}) do
		table.insert(nextBuffer.conversions, cloneConversionRecord(existing))
	end

	for _, existing in ipairs(nextBuffer.conversions) do
		if existing.operationId == record.operationId then
			return nextBuffer, "duplicate"
		end
	end

	table.insert(nextBuffer.conversions, cloneConversionRecord(record))
	sortConversions(nextBuffer.conversions)

	while #nextBuffer.conversions > RealmTradeConversionConfig.MaxRetainedRecentConversions do
		table.remove(nextBuffer.conversions, 1)
	end

	return nextBuffer, nil
end

function RealmTradeConversionCrossRealmSyncState.PruneAcknowledgedOperationIds(
	buffer: PendingConversionBuffer?,
	acknowledgedOperationIds: { [string]: boolean },
	now: number
): PendingConversionBuffer?
	if buffer == nil then
		return nil
	end

	local nextConversions: { PendingConversionRecord } = {}
	for _, record in ipairs(buffer.conversions) do
		if acknowledgedOperationIds[record.operationId] ~= true then
			table.insert(nextConversions, cloneConversionRecord(record))
		end
	end

	if #nextConversions == 0 then
		return nil
	end

	return {
		realmId = buffer.realmId,
		updatedAt = now,
		conversions = nextConversions,
	}
end

function RealmTradeConversionCrossRealmSyncState.CollectAcknowledgedOperationIds(
	sessionLedger: any
): { [string]: boolean }
	local acknowledged: { [string]: boolean } = {}
	if type(sessionLedger) ~= "table" or type(sessionLedger.recentConversions) ~= "table" then
		return acknowledged
	end

	for _, record in ipairs(sessionLedger.recentConversions) do
		if type(record) == "table" and type(record.operationId) == "string" and record.operationId ~= "" then
			acknowledged[record.operationId] = true
		end
	end

	return acknowledged
end

function RealmTradeConversionCrossRealmSyncState.ReplayPendingConversionsOntoLedger(
	ledger: any,
	pendingConversions: { PendingConversionRecord }
): (any, { string })
	local nextLedger = ledger
	local appliedOperationIds: { string } = {}

	for _, record in ipairs(pendingConversions) do
		local result = RealmTradeConversionState.ApplyConversion(nextLedger, {
			operationId = record.operationId,
			role = record.role,
			realmOwnerUserId = record.realmOwnerUserId,
			counterpartyUserId = record.counterpartyUserId,
			convertedAt = record.convertedAt,
			essence = record.essence,
			wood = record.wood,
			stone = record.stone,
		})
		if type(result) == "table" and result.accepted == true and type(result.ledger) == "table" then
			nextLedger = result.ledger
			table.insert(appliedOperationIds, record.operationId)
		end
	end

	return nextLedger, appliedOperationIds
end

function RealmTradeConversionCrossRealmSyncState.MergeSessionLedgerWithPending(
	sessionLedger: any,
	pendingBuffer: PendingConversionBuffer?
): any
	local ledger = if type(sessionLedger) == "table"
		then sessionLedger
		else RealmTradeConversionState.CreateEmptySessionLedger()

	local valid, validateReason = RealmTradeConversionState.ValidateSessionLedger(ledger)
	if not valid then
		return { accepted = false, reason = validateReason or "session_ledger_invalid" }
	end

	if pendingBuffer == nil or #pendingBuffer.conversions == 0 then
		return {
			accepted = true,
			reason = "accepted",
			ledger = ledger,
		}
	end

	local mergedLedger, _appliedIds =
		RealmTradeConversionCrossRealmSyncState.ReplayPendingConversionsOntoLedger(ledger, pendingBuffer.conversions)
	local mergedValid, mergedReason = RealmTradeConversionState.ValidateSessionLedger(mergedLedger)
	if not mergedValid then
		return { accepted = false, reason = mergedReason or "merged_ledger_invalid", ledger = ledger }
	end

	return {
		accepted = true,
		reason = "accepted",
		ledger = mergedLedger,
	}
end

local function encodeConversionRecord(record: PendingConversionRecord): string
	local counterparty = if record.counterpartyUserId ~= nil then tostring(record.counterpartyUserId) else ""
	return table.concat({
		record.operationId,
		record.role,
		tostring(record.realmOwnerUserId),
		counterparty,
		tostring(record.convertedAt),
		tostring(record.essence),
		tostring(record.wood),
		tostring(record.stone),
	}, ";")
end

local function decodeConversionRecord(encoded: string): PendingConversionRecord?
	local parts = string.split(encoded, ";")
	if #parts ~= 8 then
		return nil
	end

	local realmOwnerUserId = tonumber(parts[3])
	local convertedAt = tonumber(parts[5])
	local essence = tonumber(parts[6])
	local wood = tonumber(parts[7])
	local stone = tonumber(parts[8])
	if realmOwnerUserId == nil or convertedAt == nil or essence == nil or wood == nil or stone == nil then
		return nil
	end

	local counterpartyUserId = if parts[4] ~= "" then tonumber(parts[4]) else nil
	if parts[4] ~= "" and counterpartyUserId == nil then
		return nil
	end

	return {
		operationId = parts[1],
		role = parts[2],
		realmOwnerUserId = realmOwnerUserId,
		counterpartyUserId = counterpartyUserId,
		convertedAt = convertedAt,
		essence = essence,
		wood = wood,
		stone = stone,
	}
end

function RealmTradeConversionCrossRealmSyncState.EncodePendingConversionBuffer(
	buffer: PendingConversionBuffer
): (string?, string?)
	local valid, reason = RealmTradeConversionCrossRealmSyncState.ValidatePendingConversionBuffer(buffer)
	if not valid then
		return nil, reason or "pending_buffer_invalid"
	end

	local conversionLines = {}
	for _, record in ipairs(buffer.conversions) do
		table.insert(conversionLines, encodeConversionRecord(record))
	end
	table.sort(conversionLines)

	local header = table.concat({
		"v1",
		buffer.realmId,
		tostring(buffer.updatedAt),
		tostring(#conversionLines),
	}, "|")
	if #conversionLines == 0 then
		return header, nil
	end
	return header .. "\n" .. table.concat(conversionLines, "\n"), nil
end

function RealmTradeConversionCrossRealmSyncState.DecodePendingConversionBuffer(
	encoded: any
): (PendingConversionBuffer?, string?)
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
	local conversionCount = tonumber(headerParts[4])
	if realmId == nil or updatedAt == nil or conversionCount == nil then
		return nil, "stored_payload_invalid"
	end
	if not isFiniteNumber(updatedAt) or conversionCount < 0 or conversionCount % 1 ~= 0 then
		return nil, "stored_payload_invalid"
	end

	local conversions: { PendingConversionRecord } = {}
	if conversionCount > 0 then
		if body == "" then
			return nil, "stored_payload_invalid"
		end
		local conversionLines = string.split(body, "\n")
		if #conversionLines ~= conversionCount then
			return nil, "stored_payload_invalid"
		end
		for _, line in ipairs(conversionLines) do
			local record = decodeConversionRecord(line)
			if record == nil then
				return nil, "stored_conversion_invalid"
			end
			table.insert(conversions, record)
		end
	end

	local buffer: PendingConversionBuffer = {
		realmId = realmId,
		updatedAt = updatedAt,
		conversions = conversions,
	}
	local valid, validateReason = RealmTradeConversionCrossRealmSyncState.ValidatePendingConversionBuffer(buffer)
	if not valid then
		return nil, validateReason or "pending_buffer_invalid"
	end
	return buffer, nil
end

return RealmTradeConversionCrossRealmSyncState
