--!strict

local TinyfolkPartyConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("TinyfolkPartyConfig"))
	else (require :: any)("../Config/TinyfolkPartyConfig")

local TinyfolkPartyState: any = {}

export type PartyRecord = {
	partyId: string,
	leaderUserId: number,
	memberUserIds: { number },
	readyUserIds: { number },
	pendingInviteUserIds: { number },
	createdAt: number,
	updatedAt: number,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	party: PartyRecord?,
	dissolved: boolean?,
	notifyUserIds: { number }?,
}

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function cloneSortedUserIds(values: { number }): { number }
	local cloned: { number } = {}
	for _, userId in ipairs(values) do
		table.insert(cloned, userId)
	end
	table.sort(cloned)
	return cloned
end

local function normalizeUserIds(values: any): { number }?
	if type(values) ~= "table" then
		return nil
	end

	local seen: { [number]: boolean } = {}
	local normalized: { number } = {}
	for _, value in ipairs(values) do
		if isPositiveInteger(value) then
			local userId = value :: number
			if seen[userId] ~= true then
				seen[userId] = true
				table.insert(normalized, userId)
			end
		end
	end

	if #normalized <= 0 then
		return nil
	end

	table.sort(normalized)
	return normalized
end

local function containsUserId(values: { number }, userId: number): boolean
	for _, candidate in ipairs(values) do
		if candidate == userId then
			return true
		end
	end
	return false
end

local function withoutUserId(values: { number }, userId: number): { number }
	local nextValues: { number } = {}
	for _, candidate in ipairs(values) do
		if candidate ~= userId then
			table.insert(nextValues, candidate)
		end
	end
	return nextValues
end

local function cloneParty(party: PartyRecord): PartyRecord
	return {
		partyId = party.partyId,
		leaderUserId = party.leaderUserId,
		memberUserIds = cloneSortedUserIds(party.memberUserIds),
		readyUserIds = cloneSortedUserIds(party.readyUserIds),
		pendingInviteUserIds = cloneSortedUserIds(party.pendingInviteUserIds),
		createdAt = party.createdAt,
		updatedAt = party.updatedAt,
	}
end

function TinyfolkPartyState.BuildPartyId(leaderUserId: number, createdAt: number): string
	return string.format("%s%d:%d", TinyfolkPartyConfig.PartyIdPrefix, leaderUserId, math.floor(createdAt * 1000))
end

function TinyfolkPartyState.BuildSnapshot(party: PartyRecord?, reason: string, accepted: boolean): any
	if party == nil then
		return {
			accepted = accepted,
			reason = reason,
		}
	end

	return {
		accepted = accepted,
		reason = reason,
		partyId = party.partyId,
		leaderUserId = party.leaderUserId,
		memberUserIds = cloneSortedUserIds(party.memberUserIds),
		readyUserIds = cloneSortedUserIds(party.readyUserIds),
		pendingInviteUserIds = cloneSortedUserIds(party.pendingInviteUserIds),
		updatedAt = party.updatedAt,
	}
end

function TinyfolkPartyState.AreAllMembersReady(party: PartyRecord): boolean
	for _, memberUserId in ipairs(party.memberUserIds) do
		if not containsUserId(party.readyUserIds, memberUserId) then
			return false
		end
	end
	return #party.memberUserIds > 0
end

function TinyfolkPartyState.ResolveCreate(input: any): TransitionResult
	if type(input) ~= "table" or not isPositiveInteger(input.leaderUserId) or not isFiniteNumber(input.at) then
		return { accepted = false, reason = "input_invalid", party = nil, dissolved = false }
	end

	local leaderUserId = input.leaderUserId :: number
	local at = input.at :: number
	local party: PartyRecord = {
		partyId = TinyfolkPartyState.BuildPartyId(leaderUserId, at),
		leaderUserId = leaderUserId,
		memberUserIds = { leaderUserId },
		readyUserIds = {},
		pendingInviteUserIds = {},
		createdAt = at,
		updatedAt = at,
	}

	return {
		accepted = true,
		reason = "accepted",
		party = party,
		dissolved = false,
		notifyUserIds = { leaderUserId },
	}
end

function TinyfolkPartyState.ResolveInvite(input: any): TransitionResult
	if type(input) ~= "table" or type(input.party) ~= "table" then
		return { accepted = false, reason = "input_invalid", party = nil, dissolved = false }
	end

	local party = cloneParty(input.party :: PartyRecord)
	local actorUserId = input.actorUserId
	local targetUserId = input.targetUserId
	local maxPartySize = if type(input.maxPartySize) == "number"
		then input.maxPartySize
		else TinyfolkPartyConfig.MaxPartySize
	local at = input.at

	if not isPositiveInteger(actorUserId) or not isPositiveInteger(targetUserId) or not isFiniteNumber(at) then
		return { accepted = false, reason = "input_invalid", party = party, dissolved = false }
	end
	if actorUserId ~= party.leaderUserId then
		return { accepted = false, reason = "party_leader_required", party = party, dissolved = false }
	end
	if containsUserId(party.memberUserIds, targetUserId) then
		return { accepted = false, reason = "target_already_member", party = party, dissolved = false }
	end
	if containsUserId(party.pendingInviteUserIds, targetUserId) then
		return { accepted = false, reason = "target_already_invited", party = party, dissolved = false }
	end
	if #party.memberUserIds >= maxPartySize then
		return { accepted = false, reason = "party_full", party = party, dissolved = false }
	end

	table.insert(party.pendingInviteUserIds, targetUserId)
	table.sort(party.pendingInviteUserIds)
	party.updatedAt = at

	return {
		accepted = true,
		reason = "accepted",
		party = party,
		dissolved = false,
		notifyUserIds = { targetUserId },
	}
end

function TinyfolkPartyState.ResolveAcceptInvite(input: any): TransitionResult
	if type(input) ~= "table" or type(input.party) ~= "table" then
		return { accepted = false, reason = "input_invalid", party = nil, dissolved = false }
	end

	local party = cloneParty(input.party :: PartyRecord)
	local userId = input.userId
	local maxPartySize = if type(input.maxPartySize) == "number"
		then input.maxPartySize
		else TinyfolkPartyConfig.MaxPartySize
	local at = input.at

	if not isPositiveInteger(userId) or not isFiniteNumber(at) then
		return { accepted = false, reason = "input_invalid", party = party, dissolved = false }
	end
	if not containsUserId(party.pendingInviteUserIds, userId) then
		return { accepted = false, reason = "invite_not_pending", party = party, dissolved = false }
	end
	if #party.memberUserIds >= maxPartySize then
		return { accepted = false, reason = "party_full", party = party, dissolved = false }
	end

	party.pendingInviteUserIds = withoutUserId(party.pendingInviteUserIds, userId)
	table.insert(party.memberUserIds, userId)
	table.sort(party.memberUserIds)
	party.readyUserIds = {}
	party.updatedAt = at

	local notifyUserIds = cloneSortedUserIds(party.memberUserIds)
	return {
		accepted = true,
		reason = "accepted",
		party = party,
		dissolved = false,
		notifyUserIds = notifyUserIds,
	}
end

function TinyfolkPartyState.ResolveDeclineInvite(input: any): TransitionResult
	if type(input) ~= "table" or type(input.party) ~= "table" then
		return { accepted = false, reason = "input_invalid", party = nil, dissolved = false }
	end

	local party = cloneParty(input.party :: PartyRecord)
	local userId = input.userId
	local at = input.at

	if not isPositiveInteger(userId) or not isFiniteNumber(at) then
		return { accepted = false, reason = "input_invalid", party = party, dissolved = false }
	end
	if not containsUserId(party.pendingInviteUserIds, userId) then
		return { accepted = false, reason = "invite_not_pending", party = party, dissolved = false }
	end

	party.pendingInviteUserIds = withoutUserId(party.pendingInviteUserIds, userId)
	party.updatedAt = at

	return {
		accepted = true,
		reason = "accepted",
		party = party,
		dissolved = false,
		notifyUserIds = { party.leaderUserId, userId },
	}
end

function TinyfolkPartyState.ResolveLeave(input: any): TransitionResult
	if type(input) ~= "table" or type(input.party) ~= "table" then
		return { accepted = false, reason = "input_invalid", party = nil, dissolved = false }
	end

	local party = cloneParty(input.party :: PartyRecord)
	local userId = input.userId
	local at = input.at

	if not isPositiveInteger(userId) or not isFiniteNumber(at) then
		return { accepted = false, reason = "input_invalid", party = party, dissolved = false }
	end
	if not containsUserId(party.memberUserIds, userId) then
		return { accepted = false, reason = "not_party_member", party = party, dissolved = false }
	end

	local notifyUserIds = cloneSortedUserIds(party.memberUserIds)
	if userId == party.leaderUserId or #party.memberUserIds <= 1 then
		return {
			accepted = true,
			reason = "accepted",
			party = nil,
			dissolved = true,
			notifyUserIds = notifyUserIds,
		}
	end

	party.memberUserIds = withoutUserId(party.memberUserIds, userId)
	party.readyUserIds = withoutUserId(party.readyUserIds, userId)
	party.pendingInviteUserIds = withoutUserId(party.pendingInviteUserIds, userId)
	party.updatedAt = at

	return {
		accepted = true,
		reason = "accepted",
		party = party,
		dissolved = false,
		notifyUserIds = notifyUserIds,
	}
end

function TinyfolkPartyState.ResolveSetReady(input: any): TransitionResult
	if type(input) ~= "table" or type(input.party) ~= "table" then
		return { accepted = false, reason = "input_invalid", party = nil, dissolved = false }
	end

	local party = cloneParty(input.party :: PartyRecord)
	local userId = input.userId
	local ready = input.ready
	local at = input.at

	if not isPositiveInteger(userId) or type(ready) ~= "boolean" or not isFiniteNumber(at) then
		return { accepted = false, reason = "input_invalid", party = party, dissolved = false }
	end
	if not containsUserId(party.memberUserIds, userId) then
		return { accepted = false, reason = "not_party_member", party = party, dissolved = false }
	end

	if ready then
		if not containsUserId(party.readyUserIds, userId) then
			table.insert(party.readyUserIds, userId)
			table.sort(party.readyUserIds)
		end
	else
		party.readyUserIds = withoutUserId(party.readyUserIds, userId)
	end
	party.updatedAt = at

	return {
		accepted = true,
		reason = "accepted",
		party = party,
		dissolved = false,
		notifyUserIds = cloneSortedUserIds(party.memberUserIds),
	}
end

function TinyfolkPartyState.ValidateRaidBoardQueue(party: PartyRecord, requesterUserId: number): (boolean, string)
	if not isPositiveInteger(requesterUserId) then
		return false, "input_invalid"
	end
	if requesterUserId ~= party.leaderUserId then
		return false, "party_leader_required"
	end
	local members = normalizeUserIds(party.memberUserIds)
	if members == nil then
		return false, "party_members_invalid"
	end
	if not TinyfolkPartyState.AreAllMembersReady(party) then
		return false, "party_not_ready"
	end
	return true, "accepted"
end

return TinyfolkPartyState
