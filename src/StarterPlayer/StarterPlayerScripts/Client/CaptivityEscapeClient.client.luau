--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local STRUGGLE_REMOTE_NAME = "CaptivityStruggleRequest"
local ALLY_ASSIST_REMOTE_NAME = "CaptivityAllyAssistRequest"

local STRUGGLE_KEY = Enum.KeyCode.F
local ALLY_ASSIST_KEY = Enum.KeyCode.R

local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local struggleRemote = remotesFolder:WaitForChild(STRUGGLE_REMOTE_NAME) :: RemoteEvent
local allyAssistRemote = remotesFolder:WaitForChild(ALLY_ASSIST_REMOTE_NAME) :: RemoteEvent

local function isLocalPlayerCaptured(): boolean
	return localPlayer:GetAttribute(CaptureConfig.StateAttributes.CaptureActive) == true
end

local function getNearestCapturedAllyTarget(): Player?
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

	if input.KeyCode == STRUGGLE_KEY and isLocalPlayerCaptured() then
		struggleRemote:FireServer()
		return
	end

	if input.KeyCode == ALLY_ASSIST_KEY and localPlayer:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
		local target = getNearestCapturedAllyTarget()
		if target ~= nil then
			allyAssistRemote:FireServer(target.UserId)
		end
	end
end)
