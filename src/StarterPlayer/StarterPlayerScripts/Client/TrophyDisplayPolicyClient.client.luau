--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TrophyConfig = require(Config:WaitForChild("TrophyConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local UPDATE_REQUEST_REMOTE_NAME = TrophyConfig.DisplayPolicyRemotes.UpdateRequest
local UPDATE_RESPONSE_REMOTE_NAME = TrophyConfig.DisplayPolicyRemotes.UpdateResponse
local OPT_OUT_ATTRIBUTE = TrophyConfig.DisplayPolicyAttributes.OptOutOfNameDisplay

local TOGGLE_KEY = Enum.KeyCode.O

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local GUI_NAME = "TinyfolkTrophyDisplayPolicyGui"
local STATUS_LABEL_NAME = "StatusLabel"
local TOGGLE_BUTTON_NAME = "ToggleButton"

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local updateRequestRemote = remotesFolder:WaitForChild(UPDATE_REQUEST_REMOTE_NAME) :: RemoteEvent
local updateResponseRemote = remotesFolder:WaitForChild(UPDATE_RESPONSE_REMOTE_NAME) :: RemoteEvent

local function debugLog(message: string)
	print(string.format("[TrophyDisplayPolicyClient] %s", message))
end

local function isTinyfolk(): boolean
	return localPlayer:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
end

local function readOptOut(): boolean
	return localPlayer:GetAttribute(OPT_OUT_ATTRIBUTE) == true
end

local function formatStatusLabel(optOut: boolean): string
	if optOut then
		return "Giant trophies show you as Private Visitor."
	end
	return "Giant trophies may show your visitor reference."
end

local function formatToggleLabel(optOut: boolean): string
	if optOut then
		return "Allow visitor reference (O)"
	end
	return "Hide from trophy summaries (O)"
end

local existing = playerGui:FindFirstChild(GUI_NAME)
if existing ~= nil and existing:IsA("ScreenGui") then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.fromScale(0.02, 0.98)
panel.Size = UDim2.fromOffset(320, 92)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.fromOffset(296, 20)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Trophy Display Privacy"
title.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = STATUS_LABEL_NAME
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.fromOffset(12, 30)
statusLabel.Size = UDim2.fromOffset(296, 36)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextColor3 = Color3.fromRGB(180, 188, 204)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextWrapped = true
statusLabel.Text = ""
statusLabel.Parent = panel

local toggleButton = Instance.new("TextButton")
toggleButton.Name = TOGGLE_BUTTON_NAME
toggleButton.Position = UDim2.fromOffset(12, 66)
toggleButton.Size = UDim2.fromOffset(296, 22)
toggleButton.BackgroundColor3 = Color3.fromRGB(44, 52, 68)
toggleButton.BorderSizePixel = 0
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 12
toggleButton.TextColor3 = Color3.fromRGB(231, 234, 239)
toggleButton.Text = ""
toggleButton.Parent = panel

local function refreshPanel()
	local visible = isTinyfolk()
	panel.Visible = visible
	if not visible then
		return
	end

	local optOut = readOptOut()
	statusLabel.Text = formatStatusLabel(optOut)
	toggleButton.Text = formatToggleLabel(optOut)
end

local function requestToggle()
	if not isTinyfolk() then
		return
	end

	local nextOptOut = not readOptOut()
	updateRequestRemote:FireServer({
		optOutOfNameDisplay = nextOptOut,
	})
	debugLog(string.format("Sent trophy display policy update optOut=%s", tostring(nextOptOut)))
end

toggleButton.MouseButton1Click:Connect(requestToggle)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if input.KeyCode ~= TOGGLE_KEY then
		return
	end
	requestToggle()
end)

updateResponseRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.accepted == true then
		refreshPanel()
		return
	end
	debugLog(string.format("Trophy display policy update rejected reason=%s", tostring(payload.reason)))
end)

localPlayer:GetAttributeChangedSignal("Role"):Connect(refreshPanel)
localPlayer:GetAttributeChangedSignal(OPT_OUT_ATTRIBUTE):Connect(refreshPanel)

refreshPanel()
