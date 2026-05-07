--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local ACTIVATE_REMOTE_NAME = "ShrineActivateRequest"
local DEBUG_REQUEST_REMOTE_NAME = "ShrineDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "ShrineDebugStateResponse"

local ACTIVATE_KEY = Enum.KeyCode.Unknown
local DEBUG_KEY = Enum.KeyCode.K
local ACTIVATE_KEY_ENABLED = false

local localPlayer = Players.LocalPlayer

local function debugLog(message: string)
	print(string.format("[ShrineClient] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[ShrineClient] %s", message))
end

debugLog("Booting LocalScript")

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local shrineActivateRequestRemote = remotesFolder:WaitForChild(ACTIVATE_REMOTE_NAME) :: RemoteEvent
local shrineDebugStateRequestRemote = remotesFolder:WaitForChild(DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local shrineDebugStateResponseRemote = remotesFolder:WaitForChild(DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent

local function getHumanoidRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function shouldTrackShrinePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. ShrineConfig.ShrineNamePrefix) ~= nil
end

local function getNearestShrineId(): string?
	local localRoot = getHumanoidRootPart(localPlayer.Character)
	if not localRoot then
		return nil
	end

	local stationsRoot = Workspace:FindFirstChild("Map")
	if not stationsRoot then
		return nil
	end

	local bestId: string? = nil
	local bestDistance = math.huge

	for _, descendant in stationsRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackShrinePart(descendant) then
			local distance = (descendant.Position - localRoot.Position).Magnitude
			if distance <= ShrineConfig.ActivationRangeStuds and distance < bestDistance then
				bestDistance = distance
				bestId = descendant.Name
			end
		end
	end

	return bestId
end

local function requestActivate()
	local shrineId = getNearestShrineId()
	if not shrineId then
		return
	end

	shrineActivateRequestRemote:FireServer(shrineId)
	debugLog(string.format("Sent ShrineActivateRequest shrineId=%s", shrineId))
end

local function requestDebugState()
	local shrineId = getNearestShrineId()
	shrineDebugStateRequestRemote:FireServer(shrineId)
	if shrineId then
		debugLog(string.format("Sent ShrineDebugStateRequest shrineId=%s", shrineId))
	else
		debugLog("Sent ShrineDebugStateRequest snapshot")
	end
end

shrineDebugStateResponseRemote.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and payload.shrineId ~= nil then
		debugLog(string.format(
			"Debug state id=%s active=%s essenceTotal=%s tickCount=%s activatedBy=%s",
			tostring(payload.shrineId),
			tostring(payload.isActive),
			tostring(payload.essenceTotal),
			tostring(payload.tickCount),
			tostring(payload.activatedByUserId)
		))
		return
	end

	if type(payload) == "table" then
		for _, item in payload do
			if type(item) == "table" then
				debugLog(string.format(
					"Debug snapshot id=%s active=%s essenceTotal=%s tickCount=%s activatedBy=%s",
					tostring(item.shrineId),
					tostring(item.isActive),
					tostring(item.essenceTotal),
					tostring(item.tickCount),
					tostring(item.activatedByUserId)
				))
			end
		end
		return
	end

	debugWarn("Received malformed shrine debug response payload")
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if ACTIVATE_KEY_ENABLED and input.KeyCode == ACTIVATE_KEY then
		requestActivate()
	elseif input.KeyCode == DEBUG_KEY then
		requestDebugState()
	end
end)

debugLog("Input hook active (K=Request Shrine Debug State)")