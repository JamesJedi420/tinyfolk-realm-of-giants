--!strict

local RescueContractConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("RescueContractConfig"))
	else (require :: any)("../Config/RescueContractConfig")

local RescueContractHubState: any = {}

local FORBIDDEN_CLIENT_FIELDS = {
	storeReceiptId = true,
	sessionId = true,
}

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
end

local function clampDangerRating(value: any): number
	if type(value) ~= "number" or value ~= value then
		return RescueContractConfig.QueueDangerRating
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

function RescueContractHubState.ResolveRewardTierLabel(dangerRating: any): string
	local resolvedDanger = clampDangerRating(dangerRating)
	for _, bucket in ipairs(RescueContractConfig.RewardTierBuckets) do
		if type(bucket) == "table" and type(bucket.minDanger) == "number" and resolvedDanger >= bucket.minDanger then
			return if type(bucket.label) == "string" then bucket.label else "Unknown"
		end
	end
	return "Lower"
end

function RescueContractHubState.BuildRealmDisplayName(realmId: any, targetRealmOwnerUserId: any): string
	if isNonEmptyString(realmId) then
		return realmId :: string
	end
	if isPositiveInteger(targetRealmOwnerUserId) then
		return string.format("giant_realm_%d", targetRealmOwnerUserId)
	end
	return "Unknown Realm"
end

function RescueContractHubState.BuildContractRow(entry: any, nowAt: number?): any?
	if type(entry) ~= "table" or entry.status ~= "pending" then
		return nil
	end
	if not isNonEmptyString(entry.queueEntryId) then
		return nil
	end
	if not isPositiveInteger(entry.capturedUserId) then
		return nil
	end

	local dangerRating = clampDangerRating(entry.dangerRating)
	local expiration = if type(entry.expiration) == "number" then entry.expiration else 0
	local secondsRemaining = expiration
	if type(nowAt) == "number" then
		secondsRemaining = math.max(0, expiration - nowAt)
	end

	return {
		queueEntryId = entry.queueEntryId,
		capturedUserId = entry.capturedUserId,
		realmId = entry.realmId,
		realmDisplayName = RescueContractHubState.BuildRealmDisplayName(entry.realmId, entry.targetRealmOwnerUserId),
		targetRealmOwnerUserId = entry.targetRealmOwnerUserId,
		rewardHint = entry.rewardHint,
		dangerRating = dangerRating,
		rewardTierLabel = RescueContractHubState.ResolveRewardTierLabel(dangerRating),
		expiration = expiration,
		secondsRemaining = secondsRemaining,
		entryRouteKind = entry.entryRouteKind,
		isAcceptable = true,
		createdAt = if type(entry.createdAt) == "number" then entry.createdAt else 0,
	}
end

function RescueContractHubState.SortContractRows(rows: { any }): { any }
	local sorted = table.clone(rows)
	table.sort(sorted, function(left: any, right: any): boolean
		local leftCreated = if type(left) == "table" then left.createdAt else 0
		local rightCreated = if type(right) == "table" then right.createdAt else 0
		if leftCreated ~= rightCreated then
			return leftCreated < rightCreated
		end
		local leftId = if type(left) == "table" then left.queueEntryId else ""
		local rightId = if type(right) == "table" then right.queueEntryId else ""
		return leftId < rightId
	end)
	return sorted
end

function RescueContractHubState.ProjectContracts(input: any): any
	if type(input) ~= "table" or type(input.entries) ~= "table" then
		return {
			accepted = false,
			reason = "entries_invalid",
			contracts = {},
		}
	end

	local limit = input.limit
	if limit == nil then
		limit = RescueContractConfig.DefaultListLimit
	end
	if not isPositiveInteger(limit) then
		return {
			accepted = false,
			reason = "list_limit_invalid",
			contracts = {},
		}
	end
	if limit > RescueContractConfig.MaxListLimit then
		limit = RescueContractConfig.MaxListLimit
	end

	local nowAt = input.nowAt
	local rows: { any } = {}
	for _, entry in ipairs(input.entries) do
		local row = RescueContractHubState.BuildContractRow(entry, nowAt)
		if row ~= nil then
			table.insert(rows, row)
		end
	end

	local sortedRows = RescueContractHubState.SortContractRows(rows)
	local boundedRows: { any } = {}
	for index, row in ipairs(sortedRows) do
		if index > limit then
			break
		end
		table.insert(boundedRows, row)
	end

	return {
		accepted = true,
		reason = "accepted",
		contracts = boundedRows,
	}
end

function RescueContractHubState.AssertClientSafeContractRow(row: any): (boolean, string?)
	if type(row) ~= "table" then
		return false, "contract_row_invalid"
	end
	for fieldName in pairs(FORBIDDEN_CLIENT_FIELDS) do
		if row[fieldName] ~= nil then
			return false, "forbidden_field_exposed"
		end
	end
	return true, nil
end

function RescueContractHubState.FormatContractRowLine(row: any): string
	if type(row) ~= "table" then
		return "Unavailable rescue contract"
	end
	return string.format(
		"%s | Tinyfolk custody rescue | Danger %.2f | %s | %ds remaining",
		row.realmDisplayName or row.realmId or "Unknown",
		row.dangerRating or 0,
		row.rewardTierLabel or "Unknown",
		math.floor(row.secondsRemaining or 0)
	)
end

return RescueContractHubState
