--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RescueContractConfig = require(Config:WaitForChild("RescueContractConfig"))
local TinyfolkHubConfig = require(Config:WaitForChild("TinyfolkHubConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local RescueContractHubState = require(GiantRealm:WaitForChild("RescueContractHubState"))

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_ATTRIBUTE = "Role"

local globalEnv: any = getfenv()

local lastListRequestAtByUserId: { [number]: number? } = {}
local lastAcceptRequestAtByUserId: { [number]: number? } = {}

local rescueHubApiOverride: any = nil
local nowFnOverride: (() -> number)? = nil

local diagnostics = {
	listAttempts = 0,
	listSucceeded = 0,
	listFailed = 0,
	acceptAttempts = 0,
	acceptSucceeded = 0,
	acceptFailed = 0,
	lastReason = "none",
}

local function cloneDiagnostics(): any
	return {
		listAttempts = diagnostics.listAttempts,
		listSucceeded = diagnostics.listSucceeded,
		listFailed = diagnostics.listFailed,
		acceptAttempts = diagnostics.acceptAttempts,
		acceptSucceeded = diagnostics.acceptSucceeded,
		acceptFailed = diagnostics.acceptFailed,
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

local function getRescueHubApi(): any?
	if rescueHubApiOverride ~= nil then
		return rescueHubApiOverride
	end
	return getGlobalTable("_RescueContractHubSurface_QueryAPI")
end

local function getTinyfolkHubApi(): any?
	return getGlobalTable("_TinyfolkHubService_QueryAPI")
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
	local hubApi = getTinyfolkHubApi()
	if type(hubApi) ~= "table" or type(hubApi.ResolveActivityEligibility) ~= "function" then
		return true, "hub_api_unavailable"
	end

	local eligibility =
		hubApi.ResolveActivityEligibility(player.UserId, TinyfolkHubConfig.Activities.RescueContractBoard)
	if type(eligibility) ~= "table" or eligibility.accepted ~= true then
		local reason = if type(eligibility) == "table" and type(eligibility.reason) == "string"
			then eligibility.reason
			else "not_in_shared_hub"
		return false, reason
	end

	return true, "accepted"
end

local function listPendingEntries(limit: any, at: number): { any }
	local api = getRescueHubApi()
	if type(api) ~= "table" or type(api.GetPendingRescueQueueEntries) ~= "function" then
		return {}
	end
	local ok, entries = pcall(function()
		return api.GetPendingRescueQueueEntries(limit, at)
	end)
	if ok and type(entries) == "table" then
		return entries
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

	local hubAllowed, hubReason = isHubActivityAllowed(player)
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

	if
		isCoolingDown(
			lastListRequestAtByUserId[player.UserId],
			resolvedAt,
			RescueContractConfig.HubRequestCooldownSeconds
		)
	then
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
	local entries = listPendingEntries(limit, resolvedAt)
	local projected = RescueContractHubState.ProjectContracts({
		entries = entries,
		limit = limit,
		nowAt = resolvedAt,
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
		contracts = projected.contracts,
		refreshedAt = resolvedAt,
	}
	fireListResponse(player, responseRemote, response)
	return response
end

local function handleAcceptRequest(player: Player, payload: any, responseRemote: RemoteEvent, at: number?): any
	local resolvedAt = if type(at) == "number" then at else now()
	diagnostics.acceptAttempts += 1

	local requestId = if type(payload) == "table" and isNonEmptyString(payload.requestId) then payload.requestId else ""
	local queueEntryId = if type(payload) == "table" then payload.queueEntryId else nil

	if not isTinyfolk(player) then
		diagnostics.acceptFailed += 1
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
		diagnostics.acceptFailed += 1
		diagnostics.lastReason = hubReason
		local response = {
			requestId = requestId,
			accepted = false,
			reason = hubReason,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if not isNonEmptyString(queueEntryId) then
		diagnostics.acceptFailed += 1
		diagnostics.lastReason = "queue_entry_id_invalid"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "queue_entry_id_invalid",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	if
		isCoolingDown(
			lastAcceptRequestAtByUserId[player.UserId],
			resolvedAt,
			RescueContractConfig.HubRequestCooldownSeconds
		)
	then
		diagnostics.acceptFailed += 1
		diagnostics.lastReason = "rate_limited"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "rate_limited",
		}
		responseRemote:FireClient(player, response)
		return response
	end
	lastAcceptRequestAtByUserId[player.UserId] = resolvedAt

	local api = getRescueHubApi()
	if type(api) ~= "table" or type(api.AcceptRescueQueueEntry) ~= "function" then
		diagnostics.acceptFailed += 1
		diagnostics.lastReason = "rescue_hub_api_unavailable"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "rescue_hub_api_unavailable",
		}
		responseRemote:FireClient(player, response)
		return response
	end

	local acceptResult = api.AcceptRescueQueueEntry(player.UserId, queueEntryId, resolvedAt)
	if type(acceptResult) ~= "table" or acceptResult.accepted ~= true then
		diagnostics.acceptFailed += 1
		diagnostics.lastReason = if type(acceptResult) == "table" and type(acceptResult.reason) == "string"
			then acceptResult.reason
			else "accept_failed"
		local response = {
			requestId = requestId,
			accepted = false,
			reason = diagnostics.lastReason,
			queueEntryId = queueEntryId,
		}
		responseRemote:FireClient(player, response)
		return response
	end

	diagnostics.acceptSucceeded += 1
	diagnostics.lastReason = "accepted"
	local response = {
		requestId = requestId,
		accepted = true,
		reason = if acceptResult.duplicate == true then "duplicate_completed" else "accepted",
		queueEntryId = queueEntryId,
		duplicate = acceptResult.duplicate == true,
	}
	responseRemote:FireClient(player, response)
	return response
end

local remotesFolder = ensureRemotesFolder()
local listRequestRemote = ensureRemoteEvent(remotesFolder, RescueContractConfig.Remotes.ListRequest)
local listResponseRemote = ensureRemoteEvent(remotesFolder, RescueContractConfig.Remotes.ListResponse)
local acceptRequestRemote = ensureRemoteEvent(remotesFolder, RescueContractConfig.Remotes.AcceptRequest)
local acceptResponseRemote = ensureRemoteEvent(remotesFolder, RescueContractConfig.Remotes.AcceptResponse)
local notifyRemote = ensureRemoteEvent(remotesFolder, RescueContractConfig.Remotes.Notify)

listRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleListRequest(player, payload, listResponseRemote, nil)
end)

acceptRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleAcceptRequest(player, payload, acceptResponseRemote, nil)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastListRequestAtByUserId[player.UserId] = nil
	lastAcceptRequestAtByUserId[player.UserId] = nil
end)

globalEnv._RescueContractHubService_QueryAPI = {
	HandleListRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleListRequest(player, payload, listResponseRemote, at)
	end,
	HandleAcceptRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleAcceptRequest(player, payload, acceptResponseRemote, at)
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
		rescueHubApiOverride = configAny.rescueHubApi
		nowFnOverride = if type(configAny.now) == "function" then configAny.now else nil
	end,
	ResetForTests = function()
		rescueHubApiOverride = nil
		nowFnOverride = nil
		lastListRequestAtByUserId = {}
		lastAcceptRequestAtByUserId = {}
		diagnostics = {
			listAttempts = 0,
			listSucceeded = 0,
			listFailed = 0,
			acceptAttempts = 0,
			acceptSucceeded = 0,
			acceptFailed = 0,
			lastReason = "none",
		}
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RescueContractHubService_QueryAPI", globalEnv._RescueContractHubService_QueryAPI)
end

return globalEnv._RescueContractHubService_QueryAPI
