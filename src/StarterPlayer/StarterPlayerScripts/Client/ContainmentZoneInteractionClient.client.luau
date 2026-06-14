--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local CaptivityDurationState = require(GiantRealm:WaitForChild("CaptivityDurationState"))

local REMOTES_FOLDER_NAME = "Remotes"
local ESCAPE_REMOTE_NAME = "ContainmentEscapeRequest"
local RESCUE_REMOTE_NAME = "ContainmentRescueRequest"

local ESCAPE_KEY = Enum.KeyCode.F
local RESCUE_KEY = Enum.KeyCode.R

local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local escapeRemote = remotesFolder:WaitForChild(ESCAPE_REMOTE_NAME) :: RemoteEvent
local rescueRemote = remotesFolder:WaitForChild(RESCUE_REMOTE_NAME) :: RemoteEvent

local function isLocalPlayerContained(): boolean
	return localPlayer:GetAttribute(CaptureConfig.StateAttributes.CaptureActive) == true
		and localPlayer:GetAttribute(CaptureConfig.StateAttributes.CaptureContainmentPhase)
			== CaptivityDurationState.Phases.contained
end

local function getNearestContainedAllyTarget(): Player?
	local bestTarget: Player? = nil
	local bestDistance = math.huge
	local localCharacter = localPlayer.Character
	local localRoot = if localCharacter ~= nil then localCharacter:FindFirstChild("HumanoidRootPart") else nil
	if localRoot == nil or not localRoot:IsA("BasePart") then
		return nil
	end

	for _, candidate in Players:GetPlayers() do
		if
			candidate ~= localPlayer
			and candidate:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
			and candidate:GetAttribute(CaptureConfig.StateAttributes.CaptureActive) == true
			and candidate:GetAttribute(CaptureConfig.StateAttributes.CaptureContainmentPhase)
				== CaptivityDurationState.Phases.contained
		then
			local candidateCharacter = candidate.Character
			local candidateRoot = if candidateCharacter ~= nil
				then candidateCharacter:FindFirstChild("HumanoidRootPart")
				else nil
			if candidateRoot ~= nil and candidateRoot:IsA("BasePart") then
				local distance = ((candidateRoot :: BasePart).Position - (localRoot :: BasePart).Position).Magnitude
				if distance <= CaptureConfig.StruggleAllyRadiusStuds and distance < bestDistance then
					bestTarget = candidate
					bestDistance = distance
				end
			end
		end
	end

	return bestTarget
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == ESCAPE_KEY and isLocalPlayerContained() then
		escapeRemote:FireServer()
		return
	end

	if input.KeyCode == RESCUE_KEY and localPlayer:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
		local target = getNearestContainedAllyTarget()
		if target ~= nil then
			rescueRemote:FireServer(target.UserId)
		end
	end
end)
