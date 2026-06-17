--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MemoryStoreObservabilityService = require(script.Parent:WaitForChild("MemoryStoreObservabilityService"))

local REMOTES_FOLDER_NAME = "Remotes"
local DEBUG_REQUEST_REMOTE_NAME = "MemoryStoreObservabilityDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "MemoryStoreObservabilityDebugStateResponse"
local DEBUG_REQUEST_COOLDOWN_SECONDS = 2

local lastDebugRequestAtByUserId: { [number]: number } = {}

local function debugLog(message: string)
	print(string.format("[MemoryStoreObservabilityService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[MemoryStoreObservabilityService] %s", message))
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
	local lastAt = lastDebugRequestAtByUserId[userId]
	if type(lastAt) ~= "number" then
		return false
	end
	return (at - lastAt) < DEBUG_REQUEST_COOLDOWN_SECONDS
end

local remotesFolder = ensureRemotesFolder()
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local at = os.clock()
	if isCoolingDown(player.UserId, at) then
		debugWarn(string.format("Rejected debug snapshot userId=%d reason=rate_limited", player.UserId))
		return
	end
	lastDebugRequestAtByUserId[player.UserId] = at

	if payload ~= nil then
		debugWarn(string.format("Rejected debug snapshot userId=%d reason=malformed_payload", player.UserId))
		return
	end

	local snapshot = MemoryStoreObservabilityService.GetSnapshot()
	debugResponseRemote:FireClient(player, snapshot)
	debugLog(
		string.format(
			"Sent MemoryStore observability snapshot userId=%d accepted=%s",
			player.UserId,
			tostring(snapshot.accepted)
		)
	)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastDebugRequestAtByUserId[player.UserId] = nil
end)

debugLog("MemoryStore observability debug remotes ready")

return MemoryStoreObservabilityService
