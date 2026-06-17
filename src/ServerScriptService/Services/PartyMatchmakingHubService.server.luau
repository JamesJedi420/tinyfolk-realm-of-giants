--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local PartyMatchmakingQueueConfig = require(Config:WaitForChild("PartyMatchmakingQueueConfig"))
local TinyfolkHubConfig = require(Config:WaitForChild("TinyfolkHubConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_ATTRIBUTE = "Role"

local globalEnv: any = getfenv()

local lastEnqueueRequestAtByUserId: { [number]: number? } = {}
local lastPollRequestAtByUserId: { [number]: number? } = {}

local matchmakingQueueApiOverride: any = nil
local tinyfolkPartyApiOverride: any = nil
local nowFnOverride: (() -> number)? = nil

local diagnostics = {
	enqueueAttempts = 0,
	enqueueSucceeded = 0,
	enqueueFailed = 0,
	pollAttempts = 0,
	pollSucceeded = 0,
	pollFailed = 0,
	lastReason = "none",
}

local function cloneDiagnostics(): any
	return {
		enqueueAttempts = diagnostics.enqueueAttempts,
		enqueueSucceeded = diagnostics.enqueueSucceeded,
		enqueueFailed = diagnostics.enqueueFailed,
		pollAttempts = diagnostics.pollAttempts,
		pollSucceeded = diagnostics.pollSucceeded,
		pollFailed = diagnostics.pollFailed,
		lastReason = diagnostics.lastReason,
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

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isNonNegativeInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value >= 0
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

local function getMatchmakingQueueApi(): any?
	if matchmakingQueueApiOverride ~= nil then
		return matchmakingQueueApiOverride
	end
	return getGlobalTable("_PartyMatchmakingQueue_QueryAPI")
end

local function getTinyfolkPartyApi(): any?
	if tinyfolkPartyApiOverride ~= nil then
		return tinyfolkPartyApiOverride
	end
	return getGlobalTable("_TinyfolkPartyService_QueryAPI")
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

local function isCoolingDown(lastAt: number?, at: number, cooldownSeconds: number): boolean
	if type(lastAt) ~= "number" then
		return false
	end
	return (at - lastAt) < cooldownSeconds
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

local function isValidDesiredActivity(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	for _, activity in pairs(PartyMatchmakingQueueConfig.Activities) do
		if activity == value then
			return true
		end
	end
	return false
end

local function resolveQueuePartyContext(player: Player): (boolean, string, string?, { number }?)
	local partyApi = getTinyfolkPartyApi()
	if type(partyApi) ~= "table" or type(partyApi.ResolveMatchmakingQueueContext) ~= "function" then
		return false, "party_context_unavailable", nil, nil
	end

	local context = partyApi.ResolveMatchmakingQueueContext(player.UserId)
	if type(context) ~= "table" or context.accepted ~= true then
		local reason = if type(context) == "table" and type(context.reason) == "string"
			then context.reason
			else "party_context_rejected"
		return false, reason, nil, nil
	end
	if type(context.partyId) ~= "string" or type(context.partyMemberUserIds) ~= "table" then
		return false, "party_context_invalid", nil, nil
	end
	return true, "accepted", context.partyId, context.partyMemberUserIds
end

local remotesFolder = ensureRemotesFolder()
local enqueueRequestRemote = ensureRemoteEvent(remotesFolder, PartyMatchmakingQueueConfig.Remotes.EnqueueRequest)
local enqueueResponseRemote = ensureRemoteEvent(remotesFolder, PartyMatchmakingQueueConfig.Remotes.EnqueueResponse)
local pollRequestRemote = ensureRemoteEvent(remotesFolder, PartyMatchmakingQueueConfig.Remotes.PollRequest)
local pollResponseRemote = ensureRemoteEvent(remotesFolder, PartyMatchmakingQueueConfig.Remotes.PollResponse)
local notifyRemote = ensureRemoteEvent(remotesFolder, PartyMatchmakingQueueConfig.Remotes.Notify)

local function handleEnqueueRequest(
	player: Player,
	payload: any,
	responseRemote: RemoteEvent,
	at: number?
): any
	local resolvedAt = if type(at) == "number" then at else now()
	diagnostics.enqueueAttempts += 1

	local requestId = if type(payload) == "table" then payload.requestId else nil
	local desiredActivity = if type(payload) == "table" then payload.desiredActivity else nil
	local skillBand = if type(payload) == "table" then payload.skillBand else 0
	local toolTier = if type(payload) == "table" then payload.toolTier else 0
	local timeoutSeconds = if type(payload) == "table" then payload.timeoutSeconds else nil

	if not isTinyfolk(player) then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = "role_not_tinyfolk"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "role_not_tinyfolk",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local hubAllowed, hubReason = isHubActivityAllowed(player)
	if hubAllowed ~= true then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = hubReason
		local response = {
			requestId = requestId,
			accepted = false,
			reason = hubReason,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if not isValidDesiredActivity(desiredActivity) then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = "desired_activity_invalid"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "desired_activity_invalid",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if not isNonNegativeInteger(skillBand) or not isNonNegativeInteger(toolTier) then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = "queue_preferences_invalid"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "queue_preferences_invalid",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if
		isCoolingDown(
			lastEnqueueRequestAtByUserId[player.UserId],
			resolvedAt,
			PartyMatchmakingQueueConfig.RequestCooldownSeconds
		)
	then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = "rate_limited"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "rate_limited",
		}
		responseRemote:FireClient(player, response)
		return response
	end
	lastEnqueueRequestAtByUserId[player.UserId] = resolvedAt

	local queueAccepted, queueReason, queuePartyId, queueMemberUserIds = resolveQueuePartyContext(player)
	if queueAccepted ~= true then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = queueReason
		local response = {
			requestId = requestId,
			accepted = false,
			reason = queueReason,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local queueApi = getMatchmakingQueueApi()
	if type(queueApi) ~= "table" or type(queueApi.EnqueueMatchmaking) ~= "function" then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = "matchmaking_queue_unavailable"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "matchmaking_queue_unavailable",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local enqueueResult = queueApi.EnqueueMatchmaking({
		partyId = queuePartyId,
		leaderUserId = player.UserId,
		partySize = #queueMemberUserIds,
		partyMemberUserIds = queueMemberUserIds,
		desiredActivity = desiredActivity,
		skillBand = skillBand,
		toolTier = toolTier,
		timeoutSeconds = timeoutSeconds,
		createdAt = resolvedAt,
	})

	if type(enqueueResult) ~= "table" or enqueueResult.accepted ~= true then
		diagnostics.enqueueFailed += 1
		diagnostics.lastReason = if type(enqueueResult) == "table" and type(enqueueResult.reason) == "string"
			then enqueueResult.reason
			else "matchmaking_enqueue_failed"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = diagnostics.lastReason,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	diagnostics.enqueueSucceeded += 1
	diagnostics.lastReason = "accepted"
	local response = {
		requestId = requestId,
		accepted = true,
		reason = "accepted",
		queueSnapshot = enqueueResult.snapshot,
	}
	responseRemote:FireClient(player, response)
	return response
end

local function handlePollRequest(player: Player, payload: any, responseRemote: RemoteEvent, at: number?): any
	local resolvedAt = if type(at) == "number" then at else now()
	diagnostics.pollAttempts += 1

	local requestId = if type(payload) == "table" then payload.requestId else nil
	local operationId = if type(payload) == "table" then payload.operationId else nil
	local partyId = if type(payload) == "table" then payload.partyId else nil

	if not isTinyfolk(player) then
		diagnostics.pollFailed += 1
		diagnostics.lastReason = "role_not_tinyfolk"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "role_not_tinyfolk",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if
		isCoolingDown(lastPollRequestAtByUserId[player.UserId], resolvedAt, PartyMatchmakingQueueConfig.PollCoalesceSeconds)
	then
		diagnostics.pollFailed += 1
		diagnostics.lastReason = "rate_limited"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "rate_limited",
		}
		responseRemote:FireClient(player, response)
		return response
	end
	lastPollRequestAtByUserId[player.UserId] = resolvedAt

	local queueApi = getMatchmakingQueueApi()
	if type(queueApi) ~= "table" or type(queueApi.GetQueueSnapshot) ~= "function" then
		diagnostics.pollFailed += 1
		diagnostics.lastReason = "matchmaking_queue_unavailable"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "matchmaking_queue_unavailable",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local snapshotResult = queueApi.GetQueueSnapshot({
		operationId = operationId,
		partyId = partyId,
	})
	if type(snapshotResult) ~= "table" or snapshotResult.accepted ~= true then
		diagnostics.pollFailed += 1
		diagnostics.lastReason = if type(snapshotResult) == "table" and type(snapshotResult.reason) == "string"
			then snapshotResult.reason
			else "queue_snapshot_not_found"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = diagnostics.lastReason,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	diagnostics.pollSucceeded += 1
	diagnostics.lastReason = "accepted"
	local response = {
		requestId = requestId,
		accepted = true,
		reason = "accepted",
		queueSnapshot = snapshotResult.snapshot,
	}
	responseRemote:FireClient(player, response)

	if type(snapshotResult.snapshot) == "table" and snapshotResult.snapshot.status ~= "pending" then
		notifyRemote:FireClient(player, {
			kind = "queue_resolved",
			queueSnapshot = snapshotResult.snapshot,
		})
	end

	return response
end

enqueueRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleEnqueueRequest(player, payload, enqueueResponseRemote, nil)
end)

pollRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handlePollRequest(player, payload, pollResponseRemote, nil)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastEnqueueRequestAtByUserId[player.UserId] = nil
	lastPollRequestAtByUserId[player.UserId] = nil
end)

globalEnv._PartyMatchmakingHubService_QueryAPI = {
	HandleEnqueueRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleEnqueueRequest(player, payload, enqueueResponseRemote, at)
	end,
	HandlePollRequestForTests = function(player: Player, payload: any, at: number?): any
		return handlePollRequest(player, payload, pollResponseRemote, at)
	end,
	BroadcastNotify = function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		notifyRemote:FireAllClients(payload)
	end,
	GetDiagnostics = function(): any
		return cloneDiagnostics()
	end,
	ConfigureForTests = function(config: any?)
		local configAny: any = if type(config) == "table" then config else {}
		matchmakingQueueApiOverride = configAny.matchmakingQueueApi
		tinyfolkPartyApiOverride = configAny.tinyfolkPartyApi
		nowFnOverride = if type(configAny.now) == "function" then configAny.now else nil
	end,
	ResetForTests = function()
		matchmakingQueueApiOverride = nil
		tinyfolkPartyApiOverride = nil
		nowFnOverride = nil
		lastEnqueueRequestAtByUserId = {}
		lastPollRequestAtByUserId = {}
		diagnostics = {
			enqueueAttempts = 0,
			enqueueSucceeded = 0,
			enqueueFailed = 0,
			pollAttempts = 0,
			pollSucceeded = 0,
			pollFailed = 0,
			lastReason = "none",
		}
	end,
}

if type(_G) == "table" then
	rawset(_G, "_PartyMatchmakingHubService_QueryAPI", globalEnv._PartyMatchmakingHubService_QueryAPI)
end

return globalEnv._PartyMatchmakingHubService_QueryAPI
