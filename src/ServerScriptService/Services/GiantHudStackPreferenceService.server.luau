--!nocheck
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local GiantHudStackConfig = require(Config:WaitForChild("GiantHudStackConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local GiantHudStackPreferenceProfileState = require(GiantRealm:WaitForChild("GiantHudStackPreferenceProfileState"))
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else require("./ProfilePersistenceGateway")

local REMOTES_FOLDER_NAME = "Remotes"
local UPDATE_REQUEST_REMOTE_NAME = GiantHudStackConfig.PreferenceRemotes.UpdateRequest
local UPDATE_RESPONSE_REMOTE_NAME = GiantHudStackConfig.PreferenceRemotes.UpdateResponse
local PREFERENCE_ATTRIBUTE = GiantHudStackConfig.PreferenceAttributes.ExpandedBySectionIdJson
local REQUEST_COOLDOWN_SECONDS = 0.25

local lastRequestAtByUserId: { [number]: number? } = {}

local function debugLog(message: string)
	print(string.format("[GiantHudStackPreferenceService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GiantHudStackPreferenceService] %s", message))
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

local function isGiant(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Giant
end

local function encodePreferenceJson(preference: any): string
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(preference.expandedBySectionId)
	end)
	if not ok or type(encoded) ~= "string" then
		return HttpService:JSONEncode({})
	end
	return encoded
end

local function projectPreferenceAttributes(player: Player, preference: any)
	player:SetAttribute(PREFERENCE_ATTRIBUTE, encodePreferenceJson(preference))
end

local function readPreferenceFromProfile(player: Player): any
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
	if not profileResult.ok then
		debugWarn(
			string.format(
				"Giant HUD stack preference read failed userId=%d reason=%s",
				player.UserId,
				tostring(profileResult.reason)
			)
		)
		return GiantHudStackPreferenceProfileState.CreateDefaultPreference()
	end

	return GiantHudStackPreferenceProfileState.GetPreference(profileResult.data)
end

local function syncPreferenceFromProfile(player: Player)
	if not isGiant(player) then
		player:SetAttribute(PREFERENCE_ATTRIBUTE, nil)
		return
	end

	local preference = readPreferenceFromProfile(player)
	projectPreferenceAttributes(player, preference)
end

local function setSectionExpandedForPlayer(player: Player, sectionId: any, expanded: any): any
	if not isGiant(player) then
		return {
			accepted = false,
			reason = "giant_role_required",
			sectionId = nil,
			expanded = nil,
		}
	end

	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = GiantHudStackPreferenceProfileState.ApplySectionExpanded(currentData, sectionId, expanded)
		if transition.accepted ~= true then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		return {
			accepted = false,
			reason = updateResult.reason or "giant_hud_stack_preference_update_failed",
			sectionId = nil,
			expanded = nil,
		}
	end

	local preference = GiantHudStackPreferenceProfileState.GetPreference(updateResult.data)
	projectPreferenceAttributes(player, preference)
	debugLog(
		string.format(
			"Updated Giant HUD stack preference userId=%d sectionId=%s expanded=%s",
			player.UserId,
			tostring(sectionId),
			tostring(expanded)
		)
	)

	return {
		accepted = true,
		reason = "accepted",
		sectionId = sectionId,
		expanded = expanded,
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

	local result = setSectionExpandedForPlayer(player, payload.sectionId, payload.expanded)
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

_G._GiantHudStackPreferenceService_QueryAPI = {
	GetPreferenceForPlayer = function(player: Player): any
		return readPreferenceFromProfile(player)
	end,
	SetSectionExpandedForPlayer = setSectionExpandedForPlayer,
	SyncPreferenceFromProfile = syncPreferenceFromProfile,
	ResetForTests = function()
		lastRequestAtByUserId = {}
	end,
}

debugLog("GiantHudStackPreferenceService initialized")
