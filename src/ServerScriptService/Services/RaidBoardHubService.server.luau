--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local LiveRealmHubRouting = require(GiantRealm:WaitForChild("LiveRealmHubRouting"))
local RaidBoardConfig = require(Config:WaitForChild("RaidBoardConfig"))
local RaidBoardHubState = require(GiantRealm:WaitForChild("RaidBoardHubState"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_ATTRIBUTE = "Role"

local globalEnv: any = getfenv()

local lastListRequestAtByUserId: { [number]: number? } = {}
local lastQueueRequestAtByUserId: { [number]: number? } = {}
local ownerDisplayNameByUserId: { [number]: string } = {}
local ownerDisplayNameOrder: { number } = {}

local liveRegistryApiOverride: any = nil
local admissionApiOverride: any = nil
local tinyfolkPartyApiOverride: any = nil
local ownerDisplayNameResolverOverride: ((number) -> string?)? = nil
local nowFnOverride: (() -> number)? = nil

local diagnostics = {
	listAttempts = 0,
	listSucceeded = 0,
	listFailed = 0,
	queueAttempts = 0,
	queueSucceeded = 0,
	queueFailed = 0,
	lastReason = "none",
	lastResolverPath = "none",
}

local function cloneDiagnostics(): any
	return {
		listAttempts = diagnostics.listAttempts,
		listSucceeded = diagnostics.listSucceeded,
		listFailed = diagnostics.listFailed,
		queueAttempts = diagnostics.queueAttempts,
		queueSucceeded = diagnostics.queueSucceeded,
		queueFailed = diagnostics.queueFailed,
		lastReason = diagnostics.lastReason,
		lastResolverPath = diagnostics.lastResolverPath,
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

local function getLiveRegistryHubApi(): any?
	if liveRegistryApiOverride ~= nil then
		return liveRegistryApiOverride
	end
	return getGlobalTable("_LiveRealmRegistryHubSurface_QueryAPI")
end

local function getAdmissionApi(): any?
	if admissionApiOverride ~= nil then
		return admissionApiOverride
	end
	return getGlobalTable("_PartyMatchmakingAdmissionService_QueryAPI")
end

local function buildSoloPartyId(userId: number): string
	return string.format("%s%d", RaidBoardConfig.PartyIdPrefix, userId)
end

local function getTinyfolkPartyApi(): any?
	if tinyfolkPartyApiOverride ~= nil then
		return tinyfolkPartyApiOverride
	end
	return getGlobalTable("_TinyfolkPartyService_QueryAPI")
end

local function resolveQueuePartyContext(player: Player): (boolean, string, string?, { number }?)
	local partyApi = getTinyfolkPartyApi()
	if type(partyApi) ~= "table" or type(partyApi.ResolveRaidBoardQueueContext) ~= "function" then
		return true, "solo", buildSoloPartyId(player.UserId), { player.UserId }
	end

	local context = partyApi.ResolveRaidBoardQueueContext(player.UserId)
	if type(context) ~= "table" then
		return false, "party_context_unavailable", nil, nil
	end
	if context.accepted ~= true then
		local reason = if type(context.reason) == "string" then context.reason else "party_context_rejected"
		return false, reason, nil, nil
	end
	if type(context.partyId) == "string" and type(context.partyMemberUserIds) == "table" then
		return true, "party", context.partyId, context.partyMemberUserIds
	end
	return true, "solo", buildSoloPartyId(player.UserId), { player.UserId }
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
	return (at - lastAt) < RaidBoardConfig.RequestCooldownSeconds
end

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute(ROLE_ATTRIBUTE) == RoleConfig.Roles.Tinyfolk
end

local function touchOwnerDisplayNameCache(ownerUserId: number, displayName: string)
	ownerDisplayNameByUserId[ownerUserId] = displayName
	local existingIndex = table.find(ownerDisplayNameOrder, ownerUserId)
	if existingIndex ~= nil then
		table.remove(ownerDisplayNameOrder, existingIndex)
	end
	table.insert(ownerDisplayNameOrder, ownerUserId)
	while #ownerDisplayNameOrder > RaidBoardConfig.OwnerDisplayNameCacheMax do
		local evictedUserId = table.remove(ownerDisplayNameOrder, 1)
		if type(evictedUserId) == "number" then
			ownerDisplayNameByUserId[evictedUserId] = nil
		end
	end
end

local function resolveOwnerDisplayName(ownerUserId: number): string
	local cached = ownerDisplayNameByUserId[ownerUserId]
	if isNonEmptyString(cached) then
		return cached :: string
	end

	if type(ownerDisplayNameResolverOverride) == "function" then
		local resolved = ownerDisplayNameResolverOverride(ownerUserId)
		if isNonEmptyString(resolved) then
			touchOwnerDisplayNameCache(ownerUserId, resolved :: string)
			return resolved :: string
		end
	end

	local ok, displayName = pcall(function()
		return Players:GetNameFromUserIdAsync(ownerUserId)
	end)
	if ok and isNonEmptyString(displayName) then
		touchOwnerDisplayNameCache(ownerUserId, displayName :: string)
		return displayName :: string
	end

	return RaidBoardHubState.BuildOwnerDisplayName(ownerUserId, nil)
end

local function buildOwnerDisplayNameMap(availability: { any }): { [number]: string }
	local ownerDisplayNames: { [number]: string } = {}
	for _, snapshot in ipairs(availability) do
		if type(snapshot) == "table" and isPositiveInteger(snapshot.ownerUserId) then
			local ownerUserId = snapshot.ownerUserId
			if ownerDisplayNames[ownerUserId] == nil then
				ownerDisplayNames[ownerUserId] = resolveOwnerDisplayName(ownerUserId)
			end
		end
	end
	return ownerDisplayNames
end

local function listAvailability(limit: any): { any }
	local api = getLiveRegistryHubApi()
	if type(api) ~= "table" or type(api.ListLiveRealmAvailability) ~= "function" then
		return {}
	end
	local ok, availability = pcall(function()
		return api.ListLiveRealmAvailability(limit, now())
	end)
	if ok and type(availability) == "table" then
		return availability
	end
	return {}
end

local function fireListResponse(player: Player, responseRemote: RemoteEvent, response: any)
	responseRemote:FireClient(player, response)
end

local function handleListRequest(player: Player, payload: any, responseRemote: RemoteEvent, at: number?): any
	local resolvedAt = if type(at) == "number" then at else now()
	diagnostics.listAttempts += 1

	local requestId = if type(payload) == "table" and isNonEmptyString(payload.requestId) then payload.requestId else ""

	if not isTinyfolk(player) then
		diagnostics.listFailed += 1
		diagnostics.lastReason = "role_not_tinyfolk"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "role_not_tinyfolk",
		}
		fireListResponse(player, responseRemote, response)
		return response
	end

	if isCoolingDown(lastListRequestAtByUserId[player.UserId], resolvedAt) then
		diagnostics.listFailed += 1
		diagnostics.lastReason = "rate_limited"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "rate_limited",
		}
		fireListResponse(player, responseRemote, response)
		return response
	end
	lastListRequestAtByUserId[player.UserId] = resolvedAt

	local limit = if type(payload) == "table" then payload.limit else nil
	local availability = listAvailability(limit)
	local projected = RaidBoardHubState.ProjectListings({
		availability = availability,
		ownerDisplayNames = buildOwnerDisplayNameMap(availability),
		limit = limit,
	})

	if projected.accepted ~= true then
		diagnostics.listFailed += 1
		diagnostics.lastReason = projected.reason or "list_projection_failed"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = projected.reason or "list_projection_failed",
		}
		fireListResponse(player, responseRemote, response)
		return response
	end

	diagnostics.listSucceeded += 1
	diagnostics.lastReason = "accepted"
	local response = {
		requestId = requestId,
		accepted = true,
		reason = "accepted",
		listings = projected.listings,
		refreshedAt = resolvedAt,
	}
	fireListResponse(player, responseRemote, response)
	return response
end

local function handleQueueRequest(player: Player, payload: any, responseRemote: RemoteEvent, at: number?): any
	local resolvedAt = if type(at) == "number" then at else now()
	diagnostics.queueAttempts += 1

	local requestId = if type(payload) == "table" and isNonEmptyString(payload.requestId) then payload.requestId else ""
	local targetRealmId = if type(payload) == "table" then payload.targetRealmId else nil

	if not isTinyfolk(player) then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = "role_not_tinyfolk"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "role_not_tinyfolk",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if not isNonEmptyString(targetRealmId) then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = "target_realm_id_invalid"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "target_realm_id_invalid",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if isCoolingDown(lastQueueRequestAtByUserId[player.UserId], resolvedAt) then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = "rate_limited"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "rate_limited",
		}
		responseRemote:FireClient(player, response)
		return response
	end
	lastQueueRequestAtByUserId[player.UserId] = resolvedAt

	local availability = listAvailability(RaidBoardConfig.DefaultListLimit)
	local projected = RaidBoardHubState.ProjectListings({
		availability = availability,
		ownerDisplayNames = buildOwnerDisplayNameMap(availability),
		limit = RaidBoardConfig.DefaultListLimit,
	})

	local listed = false
	if type(projected.listings) == "table" then
		for _, row in ipairs(projected.listings) do
			if type(row) == "table" and row.realmId == targetRealmId then
				listed = true
				break
			end
		end
	end
	if not listed then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = "target_realm_unavailable"
		diagnostics.lastResolverPath = "listing_missing"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "target_realm_unavailable",
			targetRealmId = targetRealmId,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local admissionTarget = LiveRealmHubRouting.ResolveAdmissionTarget({
		targetRealmId = targetRealmId,
	}, availability)
	diagnostics.lastResolverPath = admissionTarget.resolverPath
	if admissionTarget.accepted ~= true then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = admissionTarget.reason or "target_realm_unavailable"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = admissionTarget.reason or "target_realm_unavailable",
			targetRealmId = targetRealmId,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local queueAccepted, queueReason, queuePartyId, queueMemberUserIds = resolveQueuePartyContext(player)
	if queueAccepted ~= true then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = queueReason
		local response = {
			requestId = requestId,
			accepted = false,
			reason = queueReason,
			targetRealmId = targetRealmId,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local admissionApi = getAdmissionApi()
	if type(admissionApi) ~= "table" or type(admissionApi.RequestPartyMatchAdmission) ~= "function" then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = "admission_api_unavailable"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "admission_api_unavailable",
			targetRealmId = targetRealmId,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local admissionResult = admissionApi.RequestPartyMatchAdmission({
		partyId = queuePartyId,
		targetRealmId = targetRealmId,
		partyMemberUserIds = queueMemberUserIds,
	})

	if type(admissionResult) ~= "table" or admissionResult.accepted ~= true then
		diagnostics.queueFailed += 1
		diagnostics.lastReason = if type(admissionResult) == "table"
				and type(admissionResult.reason) == "string"
			then admissionResult.reason
			else "admission_enqueue_failed"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = diagnostics.lastReason,
			targetRealmId = targetRealmId,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	diagnostics.queueSucceeded += 1
	diagnostics.lastReason = "accepted"
	local queueSnapshot = nil
	if type(admissionResult.snapshot) == "table" then
		queueSnapshot = {
			operationId = admissionResult.snapshot.operationId,
			partyId = admissionResult.snapshot.partyId,
		}
	elseif type(admissionResult.payload) == "table" then
		queueSnapshot = {
			operationId = admissionResult.payload.operationId,
			partyId = admissionResult.payload.partyId,
		}
	end

	local response = {
		requestId = requestId,
		accepted = true,
		reason = "accepted",
		targetRealmId = targetRealmId,
		queueSnapshot = queueSnapshot,
	}
	responseRemote:FireClient(player, response)
	return response
end

local remotesFolder = ensureRemotesFolder()
local listRequestRemote = ensureRemoteEvent(remotesFolder, RaidBoardConfig.Remotes.ListRequest)
local listResponseRemote = ensureRemoteEvent(remotesFolder, RaidBoardConfig.Remotes.ListResponse)
local queueRequestRemote = ensureRemoteEvent(remotesFolder, RaidBoardConfig.Remotes.QueueRequest)
local queueResponseRemote = ensureRemoteEvent(remotesFolder, RaidBoardConfig.Remotes.QueueResponse)
local notifyRemote = ensureRemoteEvent(remotesFolder, RaidBoardConfig.Remotes.Notify)

listRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleListRequest(player, payload, listResponseRemote, nil)
end)

queueRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleQueueRequest(player, payload, queueResponseRemote, nil)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastListRequestAtByUserId[player.UserId] = nil
	lastQueueRequestAtByUserId[player.UserId] = nil
end)

globalEnv._RaidBoardHubService_QueryAPI = {
	HandleListRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleListRequest(player, payload, listResponseRemote, at)
	end,
	HandleQueueRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleQueueRequest(player, payload, queueResponseRemote, at)
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
		liveRegistryApiOverride = configAny.liveRegistryApi
		admissionApiOverride = configAny.admissionApi
		tinyfolkPartyApiOverride = configAny.tinyfolkPartyApi
		ownerDisplayNameResolverOverride = if type(configAny.resolveOwnerDisplayName) == "function"
			then configAny.resolveOwnerDisplayName
			else nil
		nowFnOverride = if type(configAny.now) == "function" then configAny.now else nil
	end,
	ResetForTests = function()
		liveRegistryApiOverride = nil
		admissionApiOverride = nil
		tinyfolkPartyApiOverride = nil
		ownerDisplayNameResolverOverride = nil
		nowFnOverride = nil
		lastListRequestAtByUserId = {}
		lastQueueRequestAtByUserId = {}
		ownerDisplayNameByUserId = {}
		ownerDisplayNameOrder = {}
		diagnostics = {
			listAttempts = 0,
			listSucceeded = 0,
			listFailed = 0,
			queueAttempts = 0,
			queueSucceeded = 0,
			queueFailed = 0,
			lastReason = "none",
			lastResolverPath = "none",
		}
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RaidBoardHubService_QueryAPI", globalEnv._RaidBoardHubService_QueryAPI)
end

return globalEnv._RaidBoardHubService_QueryAPI
