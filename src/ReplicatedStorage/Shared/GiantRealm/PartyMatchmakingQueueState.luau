--!strict

local PartyMatchmakingQueueConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("PartyMatchmakingQueueConfig"))
	else (require :: any)("../Config/PartyMatchmakingQueueConfig")

local PartyMatchmakingQueueState: any = {}

export type DesiredActivity = "raid" | "rescue" | "scouting" | "work_contract"
export type QueueStatus = "pending" | "matched" | "expired" | "cancelled"

export type QueueEntry = {
	operationId: string,
	partyId: string,
	leaderUserId: number,
	partySize: number,
	partyMemberUserIds: { number },
	desiredActivity: DesiredActivity,
	skillBand: number,
	toolTier: number,
	createdAt: number,
	expiration: number,
	status: QueueStatus,
	targetRealmId: string?,
	matchedAt: number?,
	resolvedAt: number?,
	resolvedReason: string?,
}

export type ValidationResult = {
	ok: boolean,
	reason: string?,
	entry: QueueEntry?,
}

local VALID_ACTIVITIES: { [DesiredActivity]: boolean } = {
	raid = true,
	rescue = true,
	scouting = true,
	work_contract = true,
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

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) or value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonNegativeInteger(value: any): boolean
	if not isFiniteNumber(value) or value < 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function isValidActivity(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return VALID_ACTIVITIES[value :: DesiredActivity] == true
end

local function isValidStatus(value: any): boolean
	return value == "pending" or value == "matched" or value == "expired" or value == "cancelled"
end

local function cloneEntry(entry: QueueEntry): QueueEntry
	local clonedMembers: { number } = {}
	for _, userId in ipairs(entry.partyMemberUserIds) do
		table.insert(clonedMembers, userId)
	end

	return {
		operationId = entry.operationId,
		partyId = entry.partyId,
		leaderUserId = entry.leaderUserId,
		partySize = entry.partySize,
		partyMemberUserIds = clonedMembers,
		desiredActivity = entry.desiredActivity,
		skillBand = entry.skillBand,
		toolTier = entry.toolTier,
		createdAt = entry.createdAt,
		expiration = entry.expiration,
		status = entry.status,
		targetRealmId = entry.targetRealmId,
		matchedAt = entry.matchedAt,
		resolvedAt = entry.resolvedAt,
		resolvedReason = entry.resolvedReason,
	}
end

local function normalizePartyMemberUserIds(values: any, partySize: number): ({ number }?, string?)
	if type(values) ~= "table" then
		return nil, "party_member_user_ids_invalid"
	end

	local seen: { [number]: boolean } = {}
	local normalized: { number } = {}
	for _, value in ipairs(values) do
		if not isPositiveInteger(value) then
			return nil, "party_member_user_ids_invalid"
		end
		local userId = value :: number
		if seen[userId] ~= true then
			seen[userId] = true
			table.insert(normalized, userId)
		end
	end

	if #normalized <= 0 then
		return nil, "party_member_user_ids_invalid"
	end
	table.sort(normalized)

	if #normalized ~= partySize then
		return nil, "party_member_user_ids_mismatch"
	end

	return normalized, nil
end

function PartyMatchmakingQueueState.IsRaidBoardSoloPartyId(partyId: any): boolean
	if not isNonEmptyString(partyId) then
		return false
	end
	local prefix = PartyMatchmakingQueueConfig.RaidBoardPartyIdPrefix
	return string.sub(partyId, 1, #prefix) == prefix
end

function PartyMatchmakingQueueState.ValidateEntry(input: any): ValidationResult
	if type(input) ~= "table" then
		return { ok = false, reason = "entry_invalid", entry = nil }
	end
	if not isNonEmptyString(input.operationId) then
		return { ok = false, reason = "operation_id_invalid", entry = nil }
	end
	if not isNonEmptyString(input.partyId) then
		return { ok = false, reason = "party_id_invalid", entry = nil }
	end
	if PartyMatchmakingQueueState.IsRaidBoardSoloPartyId(input.partyId) then
		return { ok = false, reason = "party_id_namespace_reserved", entry = nil }
	end
	if not isValidActivity(input.desiredActivity) then
		return { ok = false, reason = "desired_activity_invalid", entry = nil }
	end
	if not isNonNegativeInteger(input.skillBand) then
		return { ok = false, reason = "skill_band_invalid", entry = nil }
	end
	if not isNonNegativeInteger(input.toolTier) then
		return { ok = false, reason = "tool_tier_invalid", entry = nil }
	end
	if not isFiniteNumber(input.createdAt) or input.createdAt < 0 then
		return { ok = false, reason = "created_at_invalid", entry = nil }
	end
	if not isFiniteNumber(input.expiration) or input.expiration <= input.createdAt then
		return { ok = false, reason = "expiration_invalid", entry = nil }
	end

	local partySize = input.partySize
	if not isPositiveInteger(input.partySize) then
		return { ok = false, reason = "party_size_invalid", entry = nil }
	end
	if not isPositiveInteger(input.leaderUserId) then
		return { ok = false, reason = "leader_user_id_invalid", entry = nil }
	end

	local partyMemberUserIds, memberReason = normalizePartyMemberUserIds(input.partyMemberUserIds, partySize)
	if memberReason ~= nil or partyMemberUserIds == nil then
		return { ok = false, reason = memberReason or "party_member_user_ids_invalid", entry = nil }
	end

	local leaderFound = false
	for _, memberUserId in ipairs(partyMemberUserIds) do
		if memberUserId == input.leaderUserId then
			leaderFound = true
			break
		end
	end
	if not leaderFound then
		return { ok = false, reason = "leader_not_in_party", entry = nil }
	end

	local status = if input.status == nil then "pending" else input.status
	if not isValidStatus(status) then
		return { ok = false, reason = "status_invalid", entry = nil }
	end

	local targetRealmId = input.targetRealmId
	if targetRealmId ~= nil and not isNonEmptyString(targetRealmId) then
		return { ok = false, reason = "target_realm_id_invalid", entry = nil }
	end

	local matchedAt = input.matchedAt
	if matchedAt ~= nil and not isFiniteNumber(matchedAt) then
		return { ok = false, reason = "matched_at_invalid", entry = nil }
	end

	local resolvedAt = input.resolvedAt
	if resolvedAt ~= nil and not isFiniteNumber(resolvedAt) then
		return { ok = false, reason = "resolved_at_invalid", entry = nil }
	end

	local entry: QueueEntry = {
		operationId = input.operationId,
		partyId = input.partyId,
		leaderUserId = input.leaderUserId,
		partySize = partySize,
		partyMemberUserIds = partyMemberUserIds,
		desiredActivity = input.desiredActivity,
		skillBand = input.skillBand,
		toolTier = input.toolTier,
		createdAt = input.createdAt,
		expiration = input.expiration,
		status = status,
		targetRealmId = targetRealmId,
		matchedAt = matchedAt,
		resolvedAt = resolvedAt,
		resolvedReason = if type(input.resolvedReason) == "string" then input.resolvedReason else nil,
	}

	return {
		ok = true,
		reason = nil,
		entry = entry,
	}
end

function PartyMatchmakingQueueState.NewEntry(input: any): ValidationResult
	return PartyMatchmakingQueueState.ValidateEntry(input)
end

function PartyMatchmakingQueueState.GetSnapshot(entry: QueueEntry): QueueEntry?
	local validation = PartyMatchmakingQueueState.ValidateEntry(entry)
	if not validation.ok then
		return nil
	end
	return cloneEntry(validation.entry :: QueueEntry)
end

function PartyMatchmakingQueueState.IsExpired(entry: QueueEntry, nowAt: number): boolean
	local validation = PartyMatchmakingQueueState.ValidateEntry(entry)
	if not validation.ok then
		return true
	end
	if not isFiniteNumber(nowAt) or nowAt < 0 then
		return true
	end

	local validatedEntry = validation.entry :: QueueEntry
	if validatedEntry.status ~= "pending" then
		return false
	end
	return nowAt >= validatedEntry.expiration
end

function PartyMatchmakingQueueState.WithMatch(entry: QueueEntry, targetRealmId: string, nowAt: number): ValidationResult
	local validation = PartyMatchmakingQueueState.ValidateEntry(entry)
	if not validation.ok then
		return { ok = false, reason = validation.reason or "entry_invalid", entry = nil }
	end
	if not isNonEmptyString(targetRealmId) then
		return { ok = false, reason = "target_realm_id_invalid", entry = nil }
	end
	if not isFiniteNumber(nowAt) then
		return { ok = false, reason = "matched_at_invalid", entry = nil }
	end

	local nextEntry = cloneEntry(validation.entry :: QueueEntry)
	if nextEntry.status ~= "pending" then
		return { ok = false, reason = "status_not_pending", entry = nextEntry }
	end

	nextEntry.status = "matched"
	nextEntry.targetRealmId = targetRealmId
	nextEntry.matchedAt = nowAt
	nextEntry.resolvedAt = nowAt
	nextEntry.resolvedReason = "matched"

	return {
		ok = true,
		reason = nil,
		entry = nextEntry,
	}
end

function PartyMatchmakingQueueState.WithExpiry(entry: QueueEntry, nowAt: number, reason: string): ValidationResult
	local validation = PartyMatchmakingQueueState.ValidateEntry(entry)
	if not validation.ok then
		return { ok = false, reason = validation.reason or "entry_invalid", entry = nil }
	end
	if not isFiniteNumber(nowAt) then
		return { ok = false, reason = "resolved_at_invalid", entry = nil }
	end

	local nextEntry = cloneEntry(validation.entry :: QueueEntry)
	if nextEntry.status ~= "pending" then
		return { ok = false, reason = "status_not_pending", entry = nextEntry }
	end

	nextEntry.status = "expired"
	nextEntry.resolvedAt = nowAt
	nextEntry.resolvedReason = reason

	return {
		ok = true,
		reason = nil,
		entry = nextEntry,
	}
end

function PartyMatchmakingQueueState.BuildClientSnapshot(entry: QueueEntry): any
	local snapshot = PartyMatchmakingQueueState.GetSnapshot(entry)
	if snapshot == nil then
		return nil
	end

	return {
		operationId = snapshot.operationId,
		partyId = snapshot.partyId,
		leaderUserId = snapshot.leaderUserId,
		partySize = snapshot.partySize,
		desiredActivity = snapshot.desiredActivity,
		skillBand = snapshot.skillBand,
		toolTier = snapshot.toolTier,
		createdAt = snapshot.createdAt,
		expiration = snapshot.expiration,
		status = snapshot.status,
		targetRealmId = snapshot.targetRealmId,
		matchedAt = snapshot.matchedAt,
		resolvedAt = snapshot.resolvedAt,
		resolvedReason = snapshot.resolvedReason,
	}
end

return PartyMatchmakingQueueState
