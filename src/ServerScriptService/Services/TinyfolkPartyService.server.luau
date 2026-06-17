--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TinyfolkPartyConfig = require(Config:WaitForChild("TinyfolkPartyConfig"))
local TinyfolkHubConfig = require(Config:WaitForChild("TinyfolkHubConfig"))
local TinyfolkPartyState = require(GiantRealm:WaitForChild("TinyfolkPartyState"))

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_ATTRIBUTE = "Role"

local globalEnv: any = getfenv()

type PartyRecord = TinyfolkPartyState.PartyRecord

local partiesById: { [string]: PartyRecord? } = {}
local partyIdByUserId: { [number]: string? } = {}
local lastRequestAtByUserId: { [number]: number? } = {}
local pendingDisconnectByUserId: { [number]: number? } = {}

local partyResolverApiOverride: any = nil
local playersServiceOverride: any = nil
local nowFnOverride: (() -> number)? = nil

local diagnostics = {
	actionAttempts = 0,
	actionSucceeded = 0,
	actionFailed = 0,
	lastReason = "none",
	lastAction = "none",
}

local function cloneDiagnostics(): any
	return {
		actionAttempts = diagnostics.actionAttempts,
		actionSucceeded = diagnostics.actionSucceeded,
		actionFailed = diagnostics.actionFailed,
		lastReason = diagnostics.lastReason,
		lastAction = diagnostics.lastAction,
	}
end

local function now(): number
	if type(nowFnOverride) == "function" then
		local at = nowFnOverride()
		if type(at) == "number" and at == at then
			return at
		end
	end
	return os.clock()
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
end

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function getPartyResolverApi(): any?
	if partyResolverApiOverride ~= nil then
		return partyResolverApiOverride
	end
	return getGlobalTable("_RealmAdmissionPartyResolver_QueryAPI")
end

local function resolvePlayersService(): any
	if playersServiceOverride ~= nil then
		return playersServiceOverride
	end
	return Players
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	return remote
end

local function isCoolingDown(lastAt: number?, at: number): boolean
	if type(lastAt) ~= "number" then
		return false
	end
	return (at - lastAt) < TinyfolkPartyConfig.RequestCooldownSeconds
end

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute(ROLE_ATTRIBUTE) == RoleConfig.Roles.Tinyfolk
end

local function isHubActivityAllowed(player: Player): (boolean, string)
	local hubApi = getGlobalTable("_TinyfolkHubService_QueryAPI")
	if type(hubApi) ~= "table" or type(hubApi.ResolveActivityEligibility) ~= "function" then
		return true, "hub_api_unavailable"
	end

	local eligibility = hubApi.ResolveActivityEligibility(player.UserId, TinyfolkHubConfig.Activities.Party)
	if type(eligibility) ~= "table" or eligibility.accepted ~= true then
		local reason = if type(eligibility) == "table" and type(eligibility.reason) == "string"
			then eligibility.reason
			else "not_in_shared_hub"
		return false, reason
	end

	return true, "accepted"
end

local function findPlayerByUserId(userId: number): Player?
	local playersService = resolvePlayersService()
	if type(playersService) ~= "table" or type(playersService.GetPlayers) ~= "function" then
		return nil
	end
	for _, player in ipairs(playersService:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function getPartyForUserId(userId: number): PartyRecord?
	local partyId = partyIdByUserId[userId]
	if type(partyId) ~= "string" then
		return nil
	end
	return partiesById[partyId]
end

local function clearPendingDisconnect(userId: number)
	pendingDisconnectByUserId[userId] = nil
end

local function containsUserId(values: { number }, userId: number): boolean
	for _, candidate in ipairs(values) do
		if candidate == userId then
			return true
		end
	end
	return false
end

local function syncPlayerAttributes(player: Player, party: PartyRecord?)
	local attrs = TinyfolkPartyConfig.StateAttributes
	if party == nil then
		player:SetAttribute(attrs.PartyId, nil)
		player:SetAttribute(attrs.IsLeader, false)
		player:SetAttribute(attrs.IsReady, false)
		return
	end

	player:SetAttribute(attrs.PartyId, party.partyId)
	player:SetAttribute(attrs.IsLeader, player.UserId == party.leaderUserId)
	player:SetAttribute(attrs.IsReady, containsUserId(party.readyUserIds, player.UserId))
end

local function syncPartyAttributes(party: PartyRecord?)
	if party == nil then
		return
	end
	for _, memberUserId in ipairs(party.memberUserIds) do
		local player = findPlayerByUserId(memberUserId)
		if player ~= nil then
			syncPlayerAttributes(player, party)
		end
	end
end

local function clearPartyAttributesForUserIds(userIds: { number })
	for _, userId in ipairs(userIds) do
		local player = findPlayerByUserId(userId)
		if player ~= nil then
			syncPlayerAttributes(player, nil)
		end
	end
end

local function updatePartyIndexes(party: PartyRecord?, formerMemberUserIds: { number }?)
	if type(formerMemberUserIds) == "table" then
		for _, userId in ipairs(formerMemberUserIds) do
			partyIdByUserId[userId] = nil
		end
	end
	if party ~= nil then
		for _, userId in ipairs(party.memberUserIds) do
			partyIdByUserId[userId] = party.partyId
		end
		partiesById[party.partyId] = party
	end
end

local function registerPartyWithResolver(party: PartyRecord, at: number)
	local resolverApi = getPartyResolverApi()
	if type(resolverApi) ~= "table" or type(resolverApi.RegisterPartyMembers) ~= "function" then
		return
	end
	resolverApi.RegisterPartyMembers({
		partyId = party.partyId,
		memberUserIds = party.memberUserIds,
		at = at,
	})
end

local function unregisterPartyWithResolver(partyId: string)
	local resolverApi = getPartyResolverApi()
	if type(resolverApi) ~= "table" or type(resolverApi.UnregisterParty) ~= "function" then
		return
	end
	resolverApi.UnregisterParty(partyId)
end

local function applyPartyTransition(
	transition: TinyfolkPartyState.TransitionResult,
	formerMemberUserIds: { number }?
): PartyRecord?
	if transition.accepted ~= true then
		return transition.party
	end

	local previousPartyId = nil
	if type(formerMemberUserIds) == "table" and #formerMemberUserIds > 0 then
		previousPartyId = partyIdByUserId[formerMemberUserIds[1]]
	end

	if transition.dissolved == true then
		if type(previousPartyId) == "string" then
			partiesById[previousPartyId] = nil
			unregisterPartyWithResolver(previousPartyId)
		end
		if type(formerMemberUserIds) == "table" then
			updatePartyIndexes(nil, formerMemberUserIds)
			clearPartyAttributesForUserIds(formerMemberUserIds)
		end
		return nil
	end

	local party = transition.party
	if party == nil then
		return nil
	end

	updatePartyIndexes(party, formerMemberUserIds)
	registerPartyWithResolver(party, party.updatedAt)
	syncPartyAttributes(party)
	return party
end

local function applyDisconnectExpiryForUserId(userId: number, at: number): boolean
	local expiryAt = pendingDisconnectByUserId[userId]
	if type(expiryAt) ~= "number" or at < expiryAt then
		return false
	end

	pendingDisconnectByUserId[userId] = nil
	local party = getPartyForUserId(userId)
	if party == nil then
		return true
	end

	local outcome = TinyfolkPartyState.ResolveTransferOutcome({
		party = party,
		transferredUserIds = { userId },
		at = at,
	})
	if outcome.accepted ~= true then
		return true
	end

	local transition: TinyfolkPartyState.TransitionResult = {
		accepted = true,
		reason = "accepted",
		party = outcome.party,
		dissolved = outcome.dissolved,
		notifyUserIds = party.memberUserIds,
	}
	applyPartyTransition(transition, party.memberUserIds)
	return true
end

local function expirePendingDisconnects(at: number)
	for userId, _expiryAt in pairs(pendingDisconnectByUserId) do
		applyDisconnectExpiryForUserId(userId, at)
	end
end

local function fireActionResponse(player: Player, responseRemote: RemoteEvent, snapshot: any)
	responseRemote:FireClient(player, snapshot)
end

local function fireNotifyToUserIds(userIds: { number }, notifyRemote: RemoteEvent, snapshot: any)
	for _, userId in ipairs(userIds) do
		local targetPlayer = findPlayerByUserId(userId)
		if targetPlayer ~= nil then
			notifyRemote:FireClient(targetPlayer, snapshot)
		end
	end
end

local function buildSnapshotFromParty(party: PartyRecord?, reason: string, accepted: boolean): any
	return TinyfolkPartyState.BuildSnapshot(party, reason, accepted)
end

local function rejectAction(
	player: Player,
	responseRemote: RemoteEvent,
	reason: string,
	party: PartyRecord?,
	action: string
): any
	diagnostics.actionFailed += 1
	diagnostics.lastReason = reason
	diagnostics.lastAction = action
	local snapshot = buildSnapshotFromParty(party, reason, false)
	fireActionResponse(player, responseRemote, snapshot)
	return snapshot
end

local function acceptAction(
	player: Player,
	responseRemote: RemoteEvent,
	notifyRemote: RemoteEvent,
	party: PartyRecord?,
	transition: TinyfolkPartyState.TransitionResult,
	action: string
): any
	diagnostics.actionSucceeded += 1
	diagnostics.lastReason = "accepted"
	diagnostics.lastAction = action
	local snapshot = buildSnapshotFromParty(party, "accepted", true)
	fireActionResponse(player, responseRemote, snapshot)
	if type(transition.notifyUserIds) == "table" then
		fireNotifyToUserIds(transition.notifyUserIds, notifyRemote, snapshot)
	end
	return snapshot
end

local function handleCreate(player: Player, responseRemote: RemoteEvent, notifyRemote: RemoteEvent, at: number): any
	if getPartyForUserId(player.UserId) ~= nil then
		return rejectAction(player, responseRemote, "already_in_party", getPartyForUserId(player.UserId), "create")
	end

	local transition = TinyfolkPartyState.ResolveCreate({
		leaderUserId = player.UserId,
		at = at,
	})
	if transition.accepted ~= true then
		return rejectAction(player, responseRemote, transition.reason, nil, "create")
	end

	local party = applyPartyTransition(transition, nil)
	return acceptAction(player, responseRemote, notifyRemote, party, transition, "create")
end

local function handleInvite(
	player: Player,
	payload: any,
	responseRemote: RemoteEvent,
	notifyRemote: RemoteEvent,
	at: number
): any
	local party = getPartyForUserId(player.UserId)
	if party == nil then
		return rejectAction(player, responseRemote, "not_in_party", nil, "invite")
	end

	local targetUserId = if type(payload) == "table" then payload.targetUserId else nil
	if not isPositiveInteger(targetUserId) then
		return rejectAction(player, responseRemote, "target_user_id_invalid", party, "invite")
	end
	if getPartyForUserId(targetUserId) ~= nil then
		return rejectAction(player, responseRemote, "target_already_in_party", party, "invite")
	end

	local transition = TinyfolkPartyState.ResolveInvite({
		party = party,
		actorUserId = player.UserId,
		targetUserId = targetUserId,
		at = at,
	})
	if transition.accepted ~= true then
		return rejectAction(player, responseRemote, transition.reason, party, "invite")
	end

	local updatedParty = applyPartyTransition(transition, party.memberUserIds)
	return acceptAction(player, responseRemote, notifyRemote, updatedParty, transition, "invite")
end

local function handleAcceptInvite(
	player: Player,
	responseRemote: RemoteEvent,
	notifyRemote: RemoteEvent,
	at: number
): any
	if getPartyForUserId(player.UserId) ~= nil then
		return rejectAction(
			player,
			responseRemote,
			"already_in_party",
			getPartyForUserId(player.UserId),
			"accept_invite"
		)
	end

	local pendingPartyId = nil
	for partyId, record in pairs(partiesById) do
		if record ~= nil and containsUserId(record.pendingInviteUserIds, player.UserId) then
			pendingPartyId = partyId
			break
		end
	end
	if type(pendingPartyId) ~= "string" then
		return rejectAction(player, responseRemote, "invite_not_pending", nil, "accept_invite")
	end

	local party = partiesById[pendingPartyId]
	if party == nil then
		return rejectAction(player, responseRemote, "invite_not_pending", nil, "accept_invite")
	end

	local transition = TinyfolkPartyState.ResolveAcceptInvite({
		party = party,
		userId = player.UserId,
		at = at,
	})
	if transition.accepted ~= true then
		return rejectAction(player, responseRemote, transition.reason, party, "accept_invite")
	end

	local updatedParty = applyPartyTransition(transition, party.memberUserIds)
	return acceptAction(player, responseRemote, notifyRemote, updatedParty, transition, "accept_invite")
end

local function handleDeclineInvite(
	player: Player,
	responseRemote: RemoteEvent,
	notifyRemote: RemoteEvent,
	at: number
): any
	local pendingPartyId = nil
	for partyId, record in pairs(partiesById) do
		if record ~= nil and containsUserId(record.pendingInviteUserIds, player.UserId) then
			pendingPartyId = partyId
			break
		end
	end
	if type(pendingPartyId) ~= "string" then
		return rejectAction(player, responseRemote, "invite_not_pending", nil, "decline_invite")
	end

	local party = partiesById[pendingPartyId]
	if party == nil then
		return rejectAction(player, responseRemote, "invite_not_pending", nil, "decline_invite")
	end

	local transition = TinyfolkPartyState.ResolveDeclineInvite({
		party = party,
		userId = player.UserId,
		at = at,
	})
	if transition.accepted ~= true then
		return rejectAction(player, responseRemote, transition.reason, party, "decline_invite")
	end

	local updatedParty = applyPartyTransition(transition, party.memberUserIds)
	return acceptAction(player, responseRemote, notifyRemote, updatedParty, transition, "decline_invite")
end

local function handleLeave(player: Player, responseRemote: RemoteEvent, notifyRemote: RemoteEvent, at: number): any
	local party = getPartyForUserId(player.UserId)
	if party == nil then
		return rejectAction(player, responseRemote, "not_in_party", nil, "leave")
	end

	local formerMembers = party.memberUserIds
	local transition = TinyfolkPartyState.ResolveLeave({
		party = party,
		userId = player.UserId,
		at = at,
	})
	if transition.accepted ~= true then
		return rejectAction(player, responseRemote, transition.reason, party, "leave")
	end

	local updatedParty = applyPartyTransition(transition, formerMembers)
	return acceptAction(player, responseRemote, notifyRemote, updatedParty, transition, "leave")
end

local function handleSetReady(
	player: Player,
	payload: any,
	responseRemote: RemoteEvent,
	notifyRemote: RemoteEvent,
	at: number
): any
	local party = getPartyForUserId(player.UserId)
	if party == nil then
		return rejectAction(player, responseRemote, "not_in_party", nil, "set_ready")
	end

	local ready = if type(payload) == "table" then payload.ready else nil
	if type(ready) ~= "boolean" then
		return rejectAction(player, responseRemote, "ready_flag_invalid", party, "set_ready")
	end

	local transition = TinyfolkPartyState.ResolveSetReady({
		party = party,
		userId = player.UserId,
		ready = ready,
		at = at,
	})
	if transition.accepted ~= true then
		return rejectAction(player, responseRemote, transition.reason, party, "set_ready")
	end

	local updatedParty = applyPartyTransition(transition, party.memberUserIds)
	return acceptAction(player, responseRemote, notifyRemote, updatedParty, transition, "set_ready")
end

local function handleActionRequest(
	player: Player,
	payload: any,
	responseRemote: RemoteEvent,
	notifyRemote: RemoteEvent,
	at: number?
): any
	local resolvedAt = if type(at) == "number" then at else now()
	diagnostics.actionAttempts += 1
	expirePendingDisconnects(resolvedAt)
	clearPendingDisconnect(player.UserId)

	if not isTinyfolk(player) then
		return rejectAction(player, responseRemote, "role_not_tinyfolk", getPartyForUserId(player.UserId), "unknown")
	end

	local hubAllowed, hubReason = isHubActivityAllowed(player)
	if hubAllowed ~= true then
		return rejectAction(player, responseRemote, hubReason, getPartyForUserId(player.UserId), "unknown")
	end

	if isCoolingDown(lastRequestAtByUserId[player.UserId], resolvedAt) then
		return rejectAction(player, responseRemote, "rate_limited", getPartyForUserId(player.UserId), "unknown")
	end
	lastRequestAtByUserId[player.UserId] = resolvedAt

	local action = if type(payload) == "table" then payload.action else nil
	if action == TinyfolkPartyConfig.Actions.Create then
		return handleCreate(player, responseRemote, notifyRemote, resolvedAt)
	end
	if action == TinyfolkPartyConfig.Actions.Invite then
		return handleInvite(player, payload, responseRemote, notifyRemote, resolvedAt)
	end
	if action == TinyfolkPartyConfig.Actions.AcceptInvite then
		return handleAcceptInvite(player, responseRemote, notifyRemote, resolvedAt)
	end
	if action == TinyfolkPartyConfig.Actions.DeclineInvite then
		return handleDeclineInvite(player, responseRemote, notifyRemote, resolvedAt)
	end
	if action == TinyfolkPartyConfig.Actions.Leave then
		return handleLeave(player, responseRemote, notifyRemote, resolvedAt)
	end
	if action == TinyfolkPartyConfig.Actions.SetReady then
		return handleSetReady(player, payload, responseRemote, notifyRemote, resolvedAt)
	end

	return rejectAction(player, responseRemote, "action_invalid", getPartyForUserId(player.UserId), "unknown")
end

local function resolveRaidBoardQueueContext(userId: number): any
	if not isPositiveInteger(userId) then
		return {
			accepted = false,
			reason = "input_invalid",
		}
	end

	local party = getPartyForUserId(userId)
	if party == nil then
		return {
			accepted = true,
			reason = "solo",
		}
	end

	local queueAccepted, queueReason = TinyfolkPartyState.ValidateRaidBoardQueue(party, userId)
	if queueAccepted ~= true then
		return {
			accepted = false,
			reason = queueReason,
			partyId = party.partyId,
			partyMemberUserIds = party.memberUserIds,
		}
	end

	local resolverApi = getPartyResolverApi()
	if type(resolverApi) == "table" and type(resolverApi.ResolvePartyMemberUserIds) == "function" then
		local resolvedMembers = resolverApi.ResolvePartyMemberUserIds(party.partyId)
		if type(resolvedMembers) ~= "table" or #resolvedMembers ~= #party.memberUserIds then
			return {
				accepted = false,
				reason = "party_members_invalid",
				partyId = party.partyId,
				partyMemberUserIds = party.memberUserIds,
			}
		end
		for _, memberUserId in ipairs(party.memberUserIds) do
			local found = false
			for _, resolvedUserId in ipairs(resolvedMembers) do
				if resolvedUserId == memberUserId then
					found = true
					break
				end
			end
			if not found then
				return {
					accepted = false,
					reason = "party_members_invalid",
					partyId = party.partyId,
					partyMemberUserIds = party.memberUserIds,
				}
			end
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		partyId = party.partyId,
		partyMemberUserIds = party.memberUserIds,
	}
end

local function resolveMatchmakingQueueContext(userId: number): any
	if not isPositiveInteger(userId) then
		return {
			accepted = false,
			reason = "input_invalid",
		}
	end

	local party = getPartyForUserId(userId)
	if party == nil then
		return {
			accepted = false,
			reason = "party_required",
		}
	end

	local queueAccepted, queueReason = TinyfolkPartyState.ValidateMatchmakingQueue(party, userId)
	if queueAccepted ~= true then
		return {
			accepted = false,
			reason = queueReason,
			partyId = party.partyId,
			partyMemberUserIds = party.memberUserIds,
		}
	end

	local resolverApi = getPartyResolverApi()
	if type(resolverApi) == "table" and type(resolverApi.ResolvePartyMemberUserIds) == "function" then
		local resolvedMembers = resolverApi.ResolvePartyMemberUserIds(party.partyId)
		if type(resolvedMembers) ~= "table" or #resolvedMembers ~= #party.memberUserIds then
			return {
				accepted = false,
				reason = "party_members_invalid",
				partyId = party.partyId,
				partyMemberUserIds = party.memberUserIds,
			}
		end
		for _, memberUserId in ipairs(party.memberUserIds) do
			local found = false
			for _, resolvedUserId in ipairs(resolvedMembers) do
				if resolvedUserId == memberUserId then
					found = true
					break
				end
			end
			if not found then
				return {
					accepted = false,
					reason = "party_members_invalid",
					partyId = party.partyId,
					partyMemberUserIds = party.memberUserIds,
				}
			end
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		partyId = party.partyId,
		partyMemberUserIds = party.memberUserIds,
	}
end

local function handleTransferOutcome(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "input_invalid" }
	end
	if type(input.partyId) ~= "string" or input.partyId == "" or type(input.transferredUserIds) ~= "table" then
		return { accepted = false, reason = "input_invalid" }
	end

	local party = partiesById[input.partyId]
	if party == nil then
		return { accepted = false, reason = "party_not_found" }
	end

	local outcome = TinyfolkPartyState.ResolveTransferOutcome({
		party = party,
		transferredUserIds = input.transferredUserIds,
		at = if type(input.at) == "number" then input.at else now(),
	})
	if outcome.accepted ~= true then
		return { accepted = false, reason = outcome.reason or "transfer_outcome_invalid" }
	end

	local transition: TinyfolkPartyState.TransitionResult = {
		accepted = true,
		reason = "accepted",
		party = outcome.party,
		dissolved = outcome.dissolved,
		notifyUserIds = party.memberUserIds,
	}
	local updatedParty = applyPartyTransition(transition, party.memberUserIds)

	return {
		accepted = true,
		reason = "accepted",
		dissolved = outcome.dissolved,
		party = buildSnapshotFromParty(updatedParty, "accepted", true),
		transferredUserIds = outcome.transferredUserIds,
		recoveredUserIds = outcome.recoveredUserIds,
	}
end

local remotesFolder = ensureRemotesFolder()
local actionRequestRemote = ensureRemoteEvent(remotesFolder, TinyfolkPartyConfig.Remotes.ActionRequest)
local actionResponseRemote = ensureRemoteEvent(remotesFolder, TinyfolkPartyConfig.Remotes.ActionResponse)
local notifyRemote = ensureRemoteEvent(remotesFolder, TinyfolkPartyConfig.Remotes.Notify)

actionRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleActionRequest(player, payload, actionResponseRemote, notifyRemote, nil)
end)

resolvePlayersService().PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	local party = getPartyForUserId(player.UserId)
	if party == nil then
		return
	end
	pendingDisconnectByUserId[player.UserId] = now() + TinyfolkPartyConfig.DisconnectGraceSeconds
end)

local playersServiceForEvents = resolvePlayersService()
if
	type(playersServiceForEvents) == "table"
	and type(playersServiceForEvents.PlayerAdded) == "table"
	and type(playersServiceForEvents.PlayerAdded.Connect) == "function"
then
	playersServiceForEvents.PlayerAdded:Connect(function(player: Player)
		local reconnectAt = now()
		expirePendingDisconnects(reconnectAt)
		clearPendingDisconnect(player.UserId)
		local party = getPartyForUserId(player.UserId)
		if party ~= nil then
			syncPlayerAttributes(player, party)
		end
	end)
end

globalEnv._TinyfolkPartyService_QueryAPI = {
	HandleActionRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleActionRequest(player, payload, actionResponseRemote, notifyRemote, at)
	end,
	GetPartySnapshot = function(userId: number): any
		local party = getPartyForUserId(userId)
		return buildSnapshotFromParty(party, if party ~= nil then "snapshot" else "not_in_party", party ~= nil)
	end,
	ResolveRaidBoardQueueContext = function(userId: number): any
		return resolveRaidBoardQueueContext(userId)
	end,
	ResolveMatchmakingQueueContext = function(userId: number): any
		return resolveMatchmakingQueueContext(userId)
	end,
	GetDiagnostics = function(): any
		return cloneDiagnostics()
	end,
	HandleTransferOutcome = function(input: any): any
		return handleTransferOutcome(input)
	end,
	HandleTransferOutcomeForTests = function(input: any): any
		return handleTransferOutcome(input)
	end,
	ExpirePendingDisconnectsForTests = function(at: number?): any
		local resolvedAt = if type(at) == "number" then at else now()
		expirePendingDisconnects(resolvedAt)
		return { accepted = true, reason = "accepted" }
	end,
	GetPendingDisconnectExpiryForTests = function(userId: number): any
		return pendingDisconnectByUserId[userId]
	end,
	ConfigureForTests = function(config: any?)
		local configAny: any = if type(config) == "table" then config else {}
		partyResolverApiOverride = configAny.partyResolverApi
		playersServiceOverride = configAny.playersService
		nowFnOverride = if type(configAny.now) == "function" then configAny.now else nil
	end,
	ResetForTests = function()
		partiesById = {}
		partyIdByUserId = {}
		lastRequestAtByUserId = {}
		pendingDisconnectByUserId = {}
		partyResolverApiOverride = nil
		playersServiceOverride = nil
		nowFnOverride = nil
		diagnostics = {
			actionAttempts = 0,
			actionSucceeded = 0,
			actionFailed = 0,
			lastReason = "none",
			lastAction = "none",
		}
	end,
}

if type(_G) == "table" then
	rawset(_G, "_TinyfolkPartyService_QueryAPI", globalEnv._TinyfolkPartyService_QueryAPI)
end

return globalEnv._TinyfolkPartyService_QueryAPI
