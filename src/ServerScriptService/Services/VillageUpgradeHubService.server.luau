--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local UpgradeBoardConfig = require(Config:WaitForChild("UpgradeBoardConfig"))
local VillageUpgradeHubConfig = require(Config:WaitForChild("VillageUpgradeHubConfig"))
local VillageUpgradeHubState = require(GiantRealm:WaitForChild("VillageUpgradeHubState"))

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "VillageUpgradeHubRequest"
local RESPONSE_REMOTE_NAME = "VillageUpgradeHubResponse"

local ROLE_ATTRIBUTE = "Role"
local globalEnv: any = getfenv()
local lastRequestAtByUserId: { [number]: number? } = {}

local function now(): number
	return os.clock()
end

local function debugLog(message: string)
	print(string.format("[VillageUpgradeHubService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[VillageUpgradeHubService] %s", message))
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

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end
	return (at - last) < VillageUpgradeHubConfig.RequestCooldownSeconds
end

local function getUpgradeBoardQueryApi(): any?
	local queryApi = globalEnv._UpgradeBoardService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._UpgradeBoardService_QueryAPI) == "table" then
		return (_G :: any)._UpgradeBoardService_QueryAPI
	end
	return nil
end

local function getWorksiteUpgradeQueryApi(): any?
	local queryApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._VillageWorksiteUpgradeService_QueryAPI) == "table" then
		return (_G :: any)._VillageWorksiteUpgradeService_QueryAPI
	end
	return nil
end

local function getGiantBuildModeQueryApi(): any?
	local queryApi = globalEnv._GiantBuildModeService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._GiantBuildModeService_QueryAPI) == "table" then
		return (_G :: any)._GiantBuildModeService_QueryAPI
	end
	return nil
end

local function getRealmOwnerUserId(): number?
	local buildApi = getGiantBuildModeQueryApi()
	if type(buildApi) ~= "table" or type(buildApi.GetRealmOwnerUserId) ~= "function" then
		return nil
	end
	return buildApi.GetRealmOwnerUserId()
end

local function resolveBoardId(payload: any): string
	if type(payload) == "string" and payload ~= "" then
		return payload
	end
	if type(payload) == "table" and type(payload.boardId) == "string" and payload.boardId ~= "" then
		return payload.boardId
	end
	return UpgradeBoardConfig.DefaultBoardId
end

local function buildLevelByWorksiteId(): { [string]: number }
	local levelByWorksiteId: { [string]: number } = {}
	local worksiteApi = getWorksiteUpgradeQueryApi()
	if type(worksiteApi) ~= "table" or type(worksiteApi.GetUpgradeLevel) ~= "function" then
		return levelByWorksiteId
	end

	for _, catalogEntry in VillageUpgradeHubConfig.HubWorksiteCatalog do
		levelByWorksiteId[catalogEntry.worksiteId] = worksiteApi.GetUpgradeLevel(catalogEntry.worksiteId)
	end

	return levelByWorksiteId
end

local function buildHubSnapshotForPlayer(player: Player, boardId: string): any
	local boardApi = getUpgradeBoardQueryApi()
	if type(boardApi) ~= "table" then
		return { accepted = false, reason = "upgrade_board_query_unavailable" }
	end

	local resolvedEffects = if type(boardApi.GetResolvedEffects) == "function"
		then boardApi.GetResolvedEffects(player.UserId)
		else {}
	local levelByWorksiteId = buildLevelByWorksiteId()

	return VillageUpgradeHubState.BuildHubSnapshot({
		boardId = boardId,
		shrineLevel = levelByWorksiteId[ShrineConfig.DefaultShrineId] or 0,
		dwellingLevel = levelByWorksiteId[StationConfig.DefaultGiantDwellingId] or 0,
		resolvedEffects = resolvedEffects,
		levelByWorksiteId = levelByWorksiteId,
	})
end

local function rejectHub(player: Player, reason: string, responseRemote: RemoteEvent)
	debugWarn(string.format("Rejected VillageUpgradeHubRequest userId=%d reason=%s", player.UserId, reason))
	responseRemote:FireClient(player, {
		accepted = false,
		reason = reason,
	})
end

local function requestHub(player: Player, payload: any, at: number?, responseRemote: RemoteEvent): any
	local resolvedAt = if type(at) == "number" then at else now()
	if isCoolingDown(player.UserId, resolvedAt) then
		rejectHub(player, "request_cooldown", responseRemote)
		return { accepted = false, reason = "request_cooldown" }
	end
	lastRequestAtByUserId[player.UserId] = resolvedAt

	if player:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Giant then
		rejectHub(player, "requester_not_giant", responseRemote)
		return { accepted = false, reason = "requester_not_giant" }
	end

	local ownerUserId = getRealmOwnerUserId()
	if type(ownerUserId) ~= "number" or ownerUserId <= 0 then
		rejectHub(player, "realm_owner_unavailable", responseRemote)
		return { accepted = false, reason = "realm_owner_unavailable" }
	end
	if ownerUserId ~= player.UserId then
		rejectHub(player, "giant_realm_owner_mismatch", responseRemote)
		return { accepted = false, reason = "giant_realm_owner_mismatch" }
	end

	local boardId = resolveBoardId(payload)
	local snapshot = buildHubSnapshotForPlayer(player, boardId)
	responseRemote:FireClient(player, snapshot)
	if snapshot.accepted == true then
		debugLog(string.format("Served VillageUpgradeHubRequest userId=%d boardId=%s", player.UserId, boardId))
	end
	return snapshot
end

local remotesFolder = ensureRemotesFolder()
local requestRemote = ensureRemoteEvent(remotesFolder, REQUEST_REMOTE_NAME)
local responseRemote = ensureRemoteEvent(remotesFolder, RESPONSE_REMOTE_NAME)

requestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	requestHub(player, payload, nil, responseRemote)
end)

local villageUpgradeHubQueryAPI = {
	BuildHubSnapshotForPlayer = buildHubSnapshotForPlayer,
	RequestHubForTests = requestHub,
}

globalEnv._VillageUpgradeHubService_QueryAPI = villageUpgradeHubQueryAPI
_G._VillageUpgradeHubService_QueryAPI = villageUpgradeHubQueryAPI

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
end)

debugLog("VillageUpgradeHubService initialized")
