--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local AdmissionQueueProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("AdmissionQueueProducer"))
	else (require :: any)("./AdmissionQueueProducer")
local RealmEntryPortalConfig = require(Config:WaitForChild("RealmEntryPortalConfig"))
local TinyfolkHubConfig = require(Config:WaitForChild("TinyfolkHubConfig"))
local RealmEntryPortalHubState = require(GiantRealm:WaitForChild("RealmEntryPortalHubState"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_ATTRIBUTE = "Role"
local DEFAULT_ADMISSION_EXPIRATION_SECONDS = 600

local globalEnv: any = getfenv()

local lastListRequestAtByUserId: { [number]: number? } = {}
local lastEnterRequestAtByUserId: { [number]: number? } = {}
local ownerDisplayNameByUserId: { [number]: string } = {}
local ownerDisplayNameOrder: { number } = {}

local liveRegistryApiOverride: any = nil
local handoffApiOverride: any = nil
local locationApiOverride: any = nil
local assignmentApiOverride: any = nil
local admissionQueueApiOverride: any = nil
local permissionApiOverride: any = nil
local ownerDisplayNameResolverOverride: ((number) -> string?)? = nil
local nowFnOverride: (() -> number)? = nil

local diagnostics = {
	listAttempts = 0,
	listSucceeded = 0,
	listFailed = 0,
	enterAttempts = 0,
	enterSucceeded = 0,
	enterFailed = 0,
	lastReason = "none",
	lastResolverPath = "none",
}

local admissionProducer: any = nil

local function cloneDiagnostics(): any
	return {
		listAttempts = diagnostics.listAttempts,
		listSucceeded = diagnostics.listSucceeded,
		listFailed = diagnostics.listFailed,
		enterAttempts = diagnostics.enterAttempts,
		enterSucceeded = diagnostics.enterSucceeded,
		enterFailed = diagnostics.enterFailed,
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

local function wallClock(): number
	return os.time()
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

local function getHandoffApi(): any?
	if handoffApiOverride ~= nil then
		return handoffApiOverride
	end
	return getGlobalTable("_RealmTransferHandoffService_QueryAPI")
end

local function getLocationApi(): any?
	if locationApiOverride ~= nil then
		return locationApiOverride
	end
	return getGlobalTable("_PlayerLocationService_QueryAPI")
end

local function getAssignmentApi(): any?
	if assignmentApiOverride ~= nil then
		return assignmentApiOverride
	end
	return getGlobalTable("_RealmTransferAssignmentService_QueryAPI")
end

local function getPermissionApi(): any?
	if permissionApiOverride ~= nil then
		return permissionApiOverride
	end
	return getGlobalTable("_RealmPermissionService_QueryAPI")
end

local function getTinyfolkHubApi(): any?
	return getGlobalTable("_TinyfolkHubService_QueryAPI")
end

local function getAdmissionProducer(): any
	if admissionProducer == nil then
		admissionProducer = AdmissionQueueProducer.Create({
			defaultExpirationSeconds = DEFAULT_ADMISSION_EXPIRATION_SECONDS,
			now = function(): number
				return now()
			end,
			queryApiResolver = function()
				if admissionQueueApiOverride ~= nil then
					return admissionQueueApiOverride
				end
				return getGlobalTable("_RealmAdmissionQueue_QueryAPI")
			end,
		})
	end
	return admissionProducer
end

local function buildSoloPartyId(userId: number): string
	return string.format("%s%d", RealmEntryPortalConfig.PartyIdPrefix, userId)
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
	return (at - lastAt) < RealmEntryPortalConfig.RequestCooldownSeconds
end

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute(ROLE_ATTRIBUTE) == RoleConfig.Roles.Tinyfolk
end

local function isHubActivityAllowed(player: Player, activity: string): (boolean, string)
	local hubApi = getTinyfolkHubApi()
	if type(hubApi) ~= "table" or type(hubApi.ResolveActivityEligibility) ~= "function" then
		return true, "hub_api_unavailable"
	end

	local eligibility = hubApi.ResolveActivityEligibility(player.UserId, activity)
	if type(eligibility) ~= "table" or eligibility.accepted ~= true then
		local reason = if type(eligibility) == "table" and type(eligibility.reason) == "string"
			then eligibility.reason
			else "not_in_shared_hub"
		return false, reason
	end

	return true, "accepted"
end

local function touchOwnerDisplayNameCache(ownerUserId: number, displayName: string)
	ownerDisplayNameByUserId[ownerUserId] = displayName
	local existingIndex = table.find(ownerDisplayNameOrder, ownerUserId)
	if existingIndex ~= nil then
		table.remove(ownerDisplayNameOrder, existingIndex)
	end
	table.insert(ownerDisplayNameOrder, ownerUserId)
	while #ownerDisplayNameOrder > RealmEntryPortalConfig.OwnerDisplayNameCacheMax do
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

	return RealmEntryPortalHubState.BuildOwnerDisplayName(ownerUserId, nil)
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

local function validateRealmPermission(targetRealmId: string, entryType: string, userId: number): (boolean, string)
	local permissionApi = getPermissionApi()
	if type(permissionApi) ~= "table" or type(permissionApi.EvaluateAdmissionForRealm) ~= "function" then
		return true, "accepted"
	end

	local ok, result = pcall(function()
		return permissionApi.EvaluateAdmissionForRealm(targetRealmId, {
			entryType = entryType,
			requesterUserIds = { userId },
		})
	end)
	if not ok or type(result) ~= "table" then
		return true, "accepted"
	end
	if result.accepted == true then
		return true, "accepted"
	end
	return false, if type(result.reason) == "string" then result.reason else "realm_access_denied"
end

local function rollbackFailedEntry(userId: number, handoffToken: string?, targetRealmId: string)
	local handoffApi = getHandoffApi()
	if
		handoffApi ~= nil
		and isNonEmptyString(handoffToken)
		and type(handoffApi.InvalidateHandoffOnAbort) == "function"
	then
		pcall(function()
			handoffApi.InvalidateHandoffOnAbort({
				userId = userId,
				handoffToken = handoffToken,
				targetRealmId = targetRealmId,
				now = wallClock(),
			})
		end)
	end

	local locationApi = getLocationApi()
	if type(locationApi) == "table" and type(locationApi.ApplyTransition) == "function" then
		pcall(function()
			locationApi.ApplyTransition(userId, {
				operation = "abort_transit",
				now = wallClock(),
			})
		end)
		pcall(function()
			locationApi.ApplyTransition(userId, {
				operation = "resolve_hub",
				now = wallClock(),
			})
		end)
	end

	local assignmentApi = getAssignmentApi()
	if type(assignmentApi) == "table" and type(assignmentApi.ApplyTransition) == "function" then
		pcall(function()
			assignmentApi.ApplyTransition(userId, {
				operation = "abort_to_hub",
				now = wallClock(),
			})
		end)
	end
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

	local hubAllowed, hubReason = isHubActivityAllowed(player, TinyfolkHubConfig.Activities.RealmPortal)
	if hubAllowed ~= true then
		diagnostics.listFailed += 1
		diagnostics.lastReason = hubReason
		local response = {
			requestId = requestId,
			accepted = false,
			reason = hubReason,
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

	local entryMethod = if type(payload) == "table" then payload.entryMethod else nil
	local limit = if type(payload) == "table" then payload.limit else nil
	local availability = listAvailability(limit)
	local projected = RealmEntryPortalHubState.ProjectListings({
		availability = availability,
		ownerDisplayNames = buildOwnerDisplayNameMap(availability),
		limit = limit,
		entryMethod = entryMethod,
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
		entryMethod = projected.entryMethod,
		refreshedAt = resolvedAt,
	}
	fireListResponse(player, responseRemote, response)
	return response
end

local function handleEnterRequest(player: Player, payload: any, responseRemote: RemoteEvent, at: number?): any
	local resolvedAt = if type(at) == "number" then at else now()
	diagnostics.enterAttempts += 1

	local requestId = if type(payload) == "table" and isNonEmptyString(payload.requestId) then payload.requestId else ""
	local targetRealmId = if type(payload) == "table" then payload.targetRealmId else nil
	local entryMethod = if type(payload) == "table" then payload.entryMethod else nil
	local entryRole = if type(payload) == "table" then payload.entryRole else nil

	local function rejectEnter(reason: string, extra: any?): any
		diagnostics.enterFailed += 1
		diagnostics.lastReason = reason
		local response = {
			requestId = requestId,
			accepted = false,
			reason = reason,
			targetRealmId = targetRealmId,
		}
		if type(extra) == "table" then
			for key, value in pairs(extra) do
				response[key] = value
			end
		end
		responseRemote:FireClient(player, response)
		return response
	end

	if not isTinyfolk(player) then
		return rejectEnter("role_not_tinyfolk")
	end

	local hubAllowed, hubReason = isHubActivityAllowed(player, TinyfolkHubConfig.Activities.RealmPortal)
	if hubAllowed ~= true then
		return rejectEnter(hubReason)
	end

	if not isNonEmptyString(targetRealmId) then
		return rejectEnter("target_realm_id_invalid")
	end

	if isCoolingDown(lastEnterRequestAtByUserId[player.UserId], resolvedAt) then
		return rejectEnter("rate_limited")
	end
	lastEnterRequestAtByUserId[player.UserId] = resolvedAt

	local availability = listAvailability(RealmEntryPortalConfig.DefaultListLimit)
	local entryPlan = RealmEntryPortalHubState.ResolveEntryRequest({
		entryMethod = entryMethod or RealmEntryPortalConfig.EntryMethods.Portal,
		entryRole = entryRole,
		targetRealmId = targetRealmId,
		availability = availability,
	})
	diagnostics.lastResolverPath = entryPlan.resolverPath or "none"
	if entryPlan.accepted ~= true then
		return rejectEnter(entryPlan.reason or "entry_request_rejected")
	end

	local listed = false
	local projected = RealmEntryPortalHubState.ProjectListings({
		availability = availability,
		ownerDisplayNames = buildOwnerDisplayNameMap(availability),
		limit = RealmEntryPortalConfig.DefaultListLimit,
		entryMethod = entryPlan.entryMethod,
	})
	if type(projected.listings) == "table" then
		for _, row in ipairs(projected.listings) do
			if type(row) == "table" and row.realmId == targetRealmId and row.isEnterable == true then
				listed = true
				break
			end
		end
	end
	if not listed then
		return rejectEnter("target_realm_unavailable", { resolverPath = diagnostics.lastResolverPath })
	end

	local permissionOk, permissionReason =
		validateRealmPermission(targetRealmId :: string, entryPlan.admissionEntryType, player.UserId)
	if permissionOk ~= true then
		return rejectEnter(permissionReason)
	end

	local handoffApi = getHandoffApi()
	if type(handoffApi) ~= "table" or type(handoffApi.BeginHandoff) ~= "function" then
		return rejectEnter("handoff_service_unavailable")
	end

	local operationId = string.format("portal_entry:%d:%d", player.UserId, math.floor(resolvedAt * 1000))
	local beginHandoff = handoffApi.BeginHandoff({
		userId = player.UserId,
		targetRealmId = targetRealmId,
		operationId = operationId,
		assignmentReason = entryPlan.assignmentReason,
		realmOwnerUserId = entryPlan.realmOwnerUserId,
		now = wallClock(),
	})
	if type(beginHandoff) ~= "table" or beginHandoff.accepted ~= true then
		return rejectEnter(if type(beginHandoff) == "table" then beginHandoff.reason else "handoff_begin_failed")
	end

	local handoffToken = beginHandoff.handoffToken
	if not isNonEmptyString(handoffToken) then
		rollbackFailedEntry(player.UserId, nil, targetRealmId :: string)
		return rejectEnter("handoff_token_missing")
	end

	local locationApi = getLocationApi()
	if type(locationApi) == "table" and type(locationApi.ApplyTransition) == "function" then
		local locationResult = locationApi.ApplyTransition(player.UserId, {
			operation = entryPlan.locationBeginOperation,
			now = wallClock(),
			realmOwnerUserId = entryPlan.realmOwnerUserId,
			realmId = targetRealmId,
			transitReason = entryPlan.locationTransitReason,
		})
		if type(locationResult) ~= "table" or locationResult.accepted ~= true then
			rollbackFailedEntry(player.UserId, handoffToken, targetRealmId :: string)
			return rejectEnter(
				if type(locationResult) == "table" then locationResult.reason else "location_transition_failed"
			)
		end
	end

	local assignmentApi = getAssignmentApi()
	if type(assignmentApi) == "table" and type(assignmentApi.ApplyTransition) == "function" then
		local assignmentResult = assignmentApi.ApplyTransition(player.UserId, {
			operation = entryPlan.assignmentBeginOperation,
			now = wallClock(),
			realmOwnerUserId = entryPlan.realmOwnerUserId,
			realmId = targetRealmId,
		})
		if type(assignmentResult) ~= "table" or assignmentResult.accepted ~= true then
			rollbackFailedEntry(player.UserId, handoffToken, targetRealmId :: string)
			return rejectEnter(
				if type(assignmentResult) == "table" then assignmentResult.reason else "assignment_transition_failed"
			)
		end
	end

	local admissionResult = getAdmissionProducer().Enqueue({
		operationId = operationId,
		partyId = buildSoloPartyId(player.UserId),
		targetRealmId = targetRealmId,
		entryType = entryPlan.admissionEntryType,
		partyMemberUserIds = { player.UserId },
		createdAt = resolvedAt,
		retryCount = 0,
	})
	if admissionResult.accepted ~= true then
		rollbackFailedEntry(player.UserId, handoffToken, targetRealmId :: string)
		return rejectEnter(admissionResult.reason or "admission_enqueue_failed")
	end

	diagnostics.enterSucceeded += 1
	diagnostics.lastReason = "accepted"
	local response = {
		requestId = requestId,
		accepted = true,
		reason = "accepted",
		targetRealmId = targetRealmId,
		entryMethod = entryPlan.entryMethod,
		entryRole = entryPlan.entryRole,
		entryRoleLabel = entryPlan.entryRoleLabel,
		handoffToken = handoffToken,
		sessionRecordRealmId = targetRealmId,
		locationConfirmOperation = entryPlan.locationConfirmOperation,
		queueSnapshot = if type(admissionResult.snapshot) == "table"
			then {
				operationId = admissionResult.snapshot.operationId,
				partyId = admissionResult.snapshot.partyId,
			}
			elseif type(admissionResult.payload) == "table" then {
				operationId = admissionResult.payload.operationId,
				partyId = admissionResult.payload.partyId,
			}
			else nil,
	}
	responseRemote:FireClient(player, response)
	return response
end

local remotesFolder = ensureRemotesFolder()
local listRequestRemote = ensureRemoteEvent(remotesFolder, RealmEntryPortalConfig.Remotes.ListRequest)
local listResponseRemote = ensureRemoteEvent(remotesFolder, RealmEntryPortalConfig.Remotes.ListResponse)
local enterRequestRemote = ensureRemoteEvent(remotesFolder, RealmEntryPortalConfig.Remotes.EnterRequest)
local enterResponseRemote = ensureRemoteEvent(remotesFolder, RealmEntryPortalConfig.Remotes.EnterResponse)
local notifyRemote = ensureRemoteEvent(remotesFolder, RealmEntryPortalConfig.Remotes.Notify)

listRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleListRequest(player, payload, listResponseRemote, nil)
end)

enterRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleEnterRequest(player, payload, enterResponseRemote, nil)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastListRequestAtByUserId[player.UserId] = nil
	lastEnterRequestAtByUserId[player.UserId] = nil
end)

globalEnv._RealmEntryPortalHubService_QueryAPI = {
	HandleListRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleListRequest(player, payload, listResponseRemote, at)
	end,
	HandleEnterRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleEnterRequest(player, payload, enterResponseRemote, at)
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
		handoffApiOverride = configAny.handoffApi
		locationApiOverride = configAny.locationApi
		assignmentApiOverride = configAny.assignmentApi
		admissionQueueApiOverride = configAny.admissionQueueApi
		permissionApiOverride = configAny.permissionApi
		ownerDisplayNameResolverOverride = if type(configAny.resolveOwnerDisplayName) == "function"
			then configAny.resolveOwnerDisplayName
			else nil
		nowFnOverride = if type(configAny.now) == "function" then configAny.now else nil
	end,
	ResetForTests = function()
		liveRegistryApiOverride = nil
		handoffApiOverride = nil
		locationApiOverride = nil
		assignmentApiOverride = nil
		admissionQueueApiOverride = nil
		permissionApiOverride = nil
		ownerDisplayNameResolverOverride = nil
		nowFnOverride = nil
		lastListRequestAtByUserId = {}
		lastEnterRequestAtByUserId = {}
		ownerDisplayNameByUserId = {}
		ownerDisplayNameOrder = {}
		diagnostics = {
			listAttempts = 0,
			listSucceeded = 0,
			listFailed = 0,
			enterAttempts = 0,
			enterSucceeded = 0,
			enterFailed = 0,
			lastReason = "none",
			lastResolverPath = "none",
		}
		admissionProducer = nil
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RealmEntryPortalHubService_QueryAPI", globalEnv._RealmEntryPortalHubService_QueryAPI)
end

return globalEnv._RealmEntryPortalHubService_QueryAPI
