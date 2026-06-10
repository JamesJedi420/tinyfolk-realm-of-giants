--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TrophyConfig = require(Config:WaitForChild("TrophyConfig"))
local TrophyDisplayPolicyState = require(GiantRealm:WaitForChild("TrophyDisplayPolicyState"))
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else require("./ProfilePersistenceGateway")

local REMOTES_FOLDER_NAME = "Remotes"
local UPDATE_REQUEST_REMOTE_NAME = TrophyConfig.DisplayPolicyRemotes.UpdateRequest
local UPDATE_RESPONSE_REMOTE_NAME = TrophyConfig.DisplayPolicyRemotes.UpdateResponse

local OPT_OUT_ATTRIBUTE = TrophyConfig.DisplayPolicyAttributes.OptOutOfNameDisplay
local REQUEST_COOLDOWN_SECONDS = 0.25

local lastRequestAtByUserId: { [number]: number? } = {}

local function debugLog(message: string)
	print(string.format("[TrophyDisplayPolicyService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[TrophyDisplayPolicyService] %s", message))
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	debugLog("Created ReplicatedStorage.Remotes folder")
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
	debugLog(string.format("Created ReplicatedStorage.Remotes.%s", remoteName))
	return remote
end

local function isCoolingDown(userId: number): boolean
	local lastRequestAt = lastRequestAtByUserId[userId]
	if lastRequestAt == nil then
		return false
	end
	return (os.clock() - lastRequestAt) < REQUEST_COOLDOWN_SECONDS
end

local function markRequest(userId: number)
	lastRequestAtByUserId[userId] = os.clock()
end

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
end

local function projectPreferenceAttributes(player: Player, preference: any)
	player:SetAttribute(OPT_OUT_ATTRIBUTE, preference.optOutOfNameDisplay == true)
end

local function readPreferenceFromProfile(player: Player): any
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
	if not profileResult.ok then
		debugWarn(
			string.format(
				"Trophy display policy read failed userId=%d reason=%s",
				player.UserId,
				tostring(profileResult.reason)
			)
		)
		return TrophyDisplayPolicyState.CreateDefaultPreference()
	end

	return TrophyDisplayPolicyState.ReadFromProfile(profileResult.data)
end

local function findPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function resolveOptOutForUserId(userId: number): boolean
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
		return true
	end

	local player = findPlayerByUserId(userId)
	if player == nil then
		return true
	end

	local preference = readPreferenceFromProfile(player)
	return preference.optOutOfNameDisplay == true
end

local function syncPreferenceFromProfile(player: Player)
	local preference = readPreferenceFromProfile(player)
	projectPreferenceAttributes(player, preference)
end

local function setOptOutForPlayer(player: Player, optOutOfNameDisplay: boolean): any
	if not isTinyfolk(player) then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			optOutOfNameDisplay = nil,
		}
	end

	if type(optOutOfNameDisplay) ~= "boolean" then
		return {
			accepted = false,
			reason = "opt_out_invalid",
			optOutOfNameDisplay = nil,
		}
	end

	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = TrophyDisplayPolicyState.ApplyUpdate(currentData, optOutOfNameDisplay)
		if transition.accepted ~= true then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		return {
			accepted = false,
			reason = updateResult.reason or "trophy_display_policy_update_failed",
			optOutOfNameDisplay = nil,
		}
	end

	local preference = TrophyDisplayPolicyState.ReadFromProfile(updateResult.data)
	projectPreferenceAttributes(player, preference)
	debugLog(
		string.format(
			"Updated trophy display policy userId=%d optOut=%s",
			player.UserId,
			tostring(preference.optOutOfNameDisplay)
		)
	)

	return {
		accepted = true,
		reason = "accepted",
		optOutOfNameDisplay = preference.optOutOfNameDisplay,
	}
end

local remotesFolder = ensureRemotesFolder()
local updateRequestRemote = ensureRemoteEvent(remotesFolder, UPDATE_REQUEST_REMOTE_NAME)
local updateResponseRemote = ensureRemoteEvent(remotesFolder, UPDATE_RESPONSE_REMOTE_NAME)

local function handleUpdateRequest(player: Player, payload: any)
	if isCoolingDown(player.UserId) then
		return
	end
	markRequest(player.UserId)

	if type(payload) ~= "table" then
		return
	end

	local result = setOptOutForPlayer(player, payload.optOutOfNameDisplay)
	updateResponseRemote:FireClient(player, result)
end

updateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleUpdateRequest(player, payload)
end)

Players.PlayerAdded:Connect(function(player: Player)
	syncPreferenceFromProfile(player)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		syncPreferenceFromProfile(player)
	end)
end)

for _, player in Players:GetPlayers() do
	syncPreferenceFromProfile(player)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		syncPreferenceFromProfile(player)
	end)
end

_G._TrophyDisplayPolicyService_QueryAPI = {
	GetOptOutForUserId = resolveOptOutForUserId,
	GetPreferenceForPlayer = function(player: Player): any
		return readPreferenceFromProfile(player)
	end,
	SetOptOutForPlayer = setOptOutForPlayer,
	SyncPreferenceFromProfile = syncPreferenceFromProfile,
	ResetForTests = function()
		lastRequestAtByUserId = {}
	end,
}

debugLog("TrophyDisplayPolicyService initialized")
