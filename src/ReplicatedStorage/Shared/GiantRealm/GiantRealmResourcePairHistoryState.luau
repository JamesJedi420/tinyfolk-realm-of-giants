--!strict

local GiantRealmResourcePairHistoryState: any = {}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
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

function GiantRealmResourcePairHistoryState.BuildPairKey(
	ownerUserId: number,
	counterpartyUserId: number,
	sourceKind: string
): string
	return string.format("%d.%d.%s", ownerUserId, counterpartyUserId, sourceKind)
end

function GiantRealmResourcePairHistoryState.EncodeRecord(count: number, lastAt: number): string
	return string.format("%d|%.6f", count, lastAt)
end

function GiantRealmResourcePairHistoryState.DecodeRecord(encoded: any): (any?, string?)
	if type(encoded) ~= "string" or encoded == "" then
		return nil, "pair_history_record_invalid"
	end
	local countText, lastAtText = string.match(encoded, "^(%d+)|([%d%.]+)$")
	if countText == nil or lastAtText == nil then
		return nil, "pair_history_record_invalid"
	end
	local count = tonumber(countText)
	local lastAt = tonumber(lastAtText)
	if not isPositiveInteger(count) or not isFiniteNumber(lastAt) or lastAt < 0 then
		return nil, "pair_history_record_invalid"
	end
	return {
		count = count,
		lastAt = lastAt,
	}, nil
end

function GiantRealmResourcePairHistoryState.ResolvePairCount(record: any?, at: number, retentionSeconds: number): number
	if not isFiniteNumber(at) or at < 0 then
		return 0
	end
	if type(record) ~= "table" then
		return 0
	end
	local count = record.count
	local lastAt = record.lastAt
	if not isPositiveInteger(count) or not isFiniteNumber(lastAt) then
		return 0
	end
	if at - lastAt > retentionSeconds then
		return 0
	end
	return count
end

function GiantRealmResourcePairHistoryState.BuildNextRecord(previousCount: number, at: number): any
	return {
		count = previousCount + 1,
		lastAt = at,
	}
end

return GiantRealmResourcePairHistoryState
