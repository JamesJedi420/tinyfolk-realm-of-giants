--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local GrabConfig = require(Config:WaitForChild("GrabConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local GRAB_REMOTE_NAME = "GrabRequest"
local PLACE_REMOTE_NAME = "PlaceRequest"

local GRAB_KEY = Enum.KeyCode.G
local PLACE_KEY = Enum.KeyCode.H

local function debugLog(message: string)
	print(string.format("[GrabClient] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GrabClient] %s", message))
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local grabRemote = remotesFolder:WaitForChild(GRAB_REMOTE_NAME) :: RemoteEvent
local placeRemote = remotesFolder:WaitForChild(PLACE_REMOTE_NAME) :: RemoteEvent

local function getRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function isPlayerTinyfolk(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
end

local function isLocalPlayerGiant(): boolean
	return localPlayer:GetAttribute("Role") == RoleConfig.Roles.Giant
end

local function getNearestTinyfolkTarget(): Player?
	local localRoot = getRootPart(localPlayer.Character)
	if not localRoot then
		return nil
	end

	local bestTarget: Player? = nil
	local bestDistance = math.huge

	for _, candidate in Players:GetPlayers() do
		if candidate ~= localPlayer and isPlayerTinyfolk(candidate) then
			local candidateRoot = getRootPart(candidate.Character)
			if candidateRoot then
				local delta = candidateRoot.Position - localRoot.Position
				local distance = delta.Magnitude
				if distance <= GrabConfig.ClientTargetingRangeStuds and distance < bestDistance then
					bestTarget = candidate
					bestDistance = distance
				end
			end
		end
	end

	return bestTarget
end

local function requestGrab()
	if not isLocalPlayerGiant() then
		debugWarn("Grab rejected locally: requester is not Giant")
		return
	end

	local target = getNearestTinyfolkTarget()
	if not target then
		debugWarn("Grab request skipped: no Tinyfolk target in range")
		return
	end

	grabRemote:FireServer(target.UserId)
	debugLog(string.format("Sent GrabRequest targetUserId=%d", target.UserId))
end

local function requestPlace()
	if not isLocalPlayerGiant() then
		debugWarn("Place rejected locally: requester is not Giant")
		return
	end

	local localRoot = getRootPart(localPlayer.Character)
	if not localRoot then
		debugWarn("Place request skipped: local humanoid root part missing")
		return
	end

	local desiredPosition = localRoot.Position + localRoot.CFrame.LookVector * GrabConfig.ClientPlaceDistanceStuds
	placeRemote:FireServer(desiredPosition)
	debugLog(string.format("Sent PlaceRequest desiredPosition=(%.1f, %.1f, %.1f)", desiredPosition.X, desiredPosition.Y, desiredPosition.Z))
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == GRAB_KEY then
		requestGrab()
	elseif input.KeyCode == PLACE_KEY then
		requestPlace()
	end
end)

debugLog("Input hook active (G=Grab, H=Place)")
