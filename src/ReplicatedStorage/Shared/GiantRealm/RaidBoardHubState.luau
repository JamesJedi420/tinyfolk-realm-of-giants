--!strict

local LiveRealmHubRouting = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("LiveRealmHubRouting"))
	else (require :: any)("./LiveRealmHubRouting")

local LiveRealmRegistryState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("LiveRealmRegistryState"))
	else (require :: any)("./LiveRealmRegistryState")

local RaidBoardConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("RaidBoardConfig"))
	else (require :: any)("../Config/RaidBoardConfig")

local RaidBoardHubState: any = {}

local FORBIDDEN_CLIENT_FIELDS = {
	privateServerId = true,
	jobId = true,
}

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
end

local function clampDangerRating(value: any): number
	if type(value) ~= "number" or value ~= value then
		return LiveRealmRegistryState.DEFAULT_DANGER_RATING
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

function RaidBoardHubState.ResolveRewardTierLabel(dangerRating: any): string
	local resolvedDanger = clampDangerRating(dangerRating)
	for _, bucket in ipairs(RaidBoardConfig.RewardTierBuckets) do
		if type(bucket) == "table" and type(bucket.minDanger) == "number" and resolvedDanger >= bucket.minDanger then
			return if type(bucket.label) == "string" then bucket.label else "Unknown"
		end
	end
	return "Low"
end

function RaidBoardHubState.ResolveEntryTypeLabel(accessMode: any): string
	if type(accessMode) ~= "string" then
		return "Unknown"
	end
	local label = RaidBoardConfig.EntryTypeLabels[accessMode]
	return if type(label) == "string" then label else "Unknown"
end

function RaidBoardHubState.BuildOwnerDisplayName(ownerUserId: any, resolvedDisplayName: any?): string
	if isNonEmptyString(resolvedDisplayName) then
		return resolvedDisplayName :: string
	end
	if isPositiveInteger(ownerUserId) then
		return string.format("Giant %d", ownerUserId)
	end
	return "Unknown Giant"
end

function RaidBoardHubState.BuildRealmDisplayName(ownerDisplayName: string): string
	if ownerDisplayName == "" then
		return "Unknown Realm"
	end
	return string.format("%s's Realm", ownerDisplayName)
end

function RaidBoardHubState.IsDiscoverableSnapshot(snapshot: any): boolean
	if type(snapshot) ~= "table" then
		return false
	end
	if snapshot.isAvailable ~= true then
		return false
	end
	return snapshot.accessMode == LiveRealmRegistryState.AccessMode.Public
		or snapshot.accessMode == LiveRealmRegistryState.AccessMode.RaidEnabled
end

function RaidBoardHubState.IsQueueableSnapshot(snapshot: any, availability: { any }): boolean
	if not RaidBoardHubState.IsDiscoverableSnapshot(snapshot) then
		return false
	end
	if not isNonEmptyString(snapshot.realmId) then
		return false
	end
	local resolved = LiveRealmHubRouting.ResolveAdmissionTarget({
		targetRealmId = snapshot.realmId,
	}, availability)
	return resolved.accepted == true
end

function RaidBoardHubState.BuildListingRow(snapshot: any, availability: { any }, ownerDisplayName: string?): any?
	if not RaidBoardHubState.IsDiscoverableSnapshot(snapshot) then
		return nil
	end
	if not isNonEmptyString(snapshot.realmId) or not isPositiveInteger(snapshot.ownerUserId) then
		return nil
	end

	local ownerLabel = RaidBoardHubState.BuildOwnerDisplayName(snapshot.ownerUserId, ownerDisplayName)
	local dangerRating = clampDangerRating(snapshot.dangerRating)

	return {
		realmId = snapshot.realmId,
		ownerUserId = snapshot.ownerUserId,
		ownerDisplayName = ownerLabel,
		realmDisplayName = RaidBoardHubState.BuildRealmDisplayName(ownerLabel),
		dangerRating = dangerRating,
		playerCount = if type(snapshot.playerCount) == "number"
			then math.max(0, math.floor(snapshot.playerCount))
			else 0,
		capacity = if type(snapshot.capacity) == "number"
			then math.max(1, math.floor(snapshot.capacity))
			else LiveRealmRegistryState.DEFAULT_CAPACITY,
		accessMode = snapshot.accessMode,
		entryTypeLabel = RaidBoardHubState.ResolveEntryTypeLabel(snapshot.accessMode),
		rewardTierLabel = RaidBoardHubState.ResolveRewardTierLabel(dangerRating),
		isQueueable = RaidBoardHubState.IsQueueableSnapshot(snapshot, availability),
		updatedAt = if type(snapshot.updatedAt) == "number" then snapshot.updatedAt else 0,
	}
end

function RaidBoardHubState.SortListingRows(rows: { any }): { any }
	local sorted = table.clone(rows)
	table.sort(sorted, function(left: any, right: any): boolean
		local leftDanger = if type(left) == "table" then left.dangerRating else 0
		local rightDanger = if type(right) == "table" then right.dangerRating else 0
		if leftDanger ~= rightDanger then
			return leftDanger > rightDanger
		end
		local leftRealmId = if type(left) == "table" then left.realmId else ""
		local rightRealmId = if type(right) == "table" then right.realmId else ""
		return leftRealmId < rightRealmId
	end)
	return sorted
end

function RaidBoardHubState.ProjectListings(input: any): any
	if type(input) ~= "table" or type(input.availability) ~= "table" then
		return {
			accepted = false,
			reason = "availability_invalid",
			listings = {},
		}
	end

	local limit = input.limit
	if limit == nil then
		limit = RaidBoardConfig.DefaultListLimit
	end
	if not isPositiveInteger(limit) then
		return {
			accepted = false,
			reason = "list_limit_invalid",
			listings = {},
		}
	end
	if limit > RaidBoardConfig.MaxListLimit then
		limit = RaidBoardConfig.MaxListLimit
	end

	local ownerDisplayNames = if type(input.ownerDisplayNames) == "table" then input.ownerDisplayNames else {}
	local rows = {}
	for _, snapshot in ipairs(input.availability) do
		local ownerDisplayName = if type(snapshot) == "table" and type(snapshot.ownerUserId) == "number"
			then ownerDisplayNames[snapshot.ownerUserId]
			else nil
		local row = RaidBoardHubState.BuildListingRow(snapshot, input.availability, ownerDisplayName)
		if row ~= nil then
			table.insert(rows, row)
		end
	end

	local sortedRows = RaidBoardHubState.SortListingRows(rows)
	local boundedRows = {}
	for index, row in ipairs(sortedRows) do
		if index > limit then
			break
		end
		table.insert(boundedRows, row)
	end

	return {
		accepted = true,
		reason = "accepted",
		listings = boundedRows,
	}
end

function RaidBoardHubState.AssertClientSafeListingRow(row: any): (boolean, string?)
	if type(row) ~= "table" then
		return false, "listing_row_invalid"
	end
	for fieldName in pairs(FORBIDDEN_CLIENT_FIELDS) do
		if row[fieldName] ~= nil then
			return false, "forbidden_field_exposed"
		end
	end
	return true, nil
end

function RaidBoardHubState.FormatListingRowLine(row: any): string
	if type(row) ~= "table" then
		return "Unavailable listing"
	end
	local population = string.format("%d/%d", row.playerCount or 0, row.capacity or 0)
	return string.format(
		"%s | Danger %.2f | %s | %s | %s | Queueable=%s",
		row.realmDisplayName or row.realmId or "Unknown",
		row.dangerRating or 0,
		row.rewardTierLabel or "Unknown",
		row.entryTypeLabel or "Unknown",
		population,
		tostring(row.isQueueable == true)
	)
end

return RaidBoardHubState
