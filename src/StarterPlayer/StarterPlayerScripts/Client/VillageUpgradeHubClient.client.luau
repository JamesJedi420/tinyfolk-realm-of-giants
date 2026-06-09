--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local VillageUpgradeHubPresentation = require(GiantRealm:WaitForChild("VillageUpgradeHubPresentation"))

local REMOTES_FOLDER_NAME = "Remotes"
local RESPONSE_REMOTE_NAME = "VillageUpgradeHubResponse"

local GUI_NAME = "VillageUpgradeHubGui"
local PANEL_NAME = "Panel"

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(118, 142, 196),
	warning = Color3.fromRGB(224, 166, 68),
}

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.neutral
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.neutral
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
panel.Name = PANEL_NAME
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(520, 420)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.BackgroundColor3 = ACCENT_BY_TONE.neutral
accent.BorderSizePixel = 0
accent.Size = UDim2.new(0, 4, 1, 0)
accent.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 10)
title.Size = UDim2.new(1, -54, 0, 24)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Village Upgrade Hub"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(14, 34)
subtitle.Size = UDim2.new(1, -54, 0, 18)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 13
subtitle.TextColor3 = Color3.fromRGB(151, 159, 174)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = ""
subtitle.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 8)
closeButton.Size = UDim2.fromOffset(28, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.TextColor3 = Color3.fromRGB(231, 234, 239)
closeButton.Text = "×"
closeButton.Parent = panel

local body = Instance.new("TextLabel")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(14, 58)
body.Size = UDim2.new(1, -24, 1, -68)
body.Font = Enum.Font.Gotham
body.TextSize = 13
body.TextColor3 = Color3.fromRGB(180, 188, 204)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true
body.Text = ""
body.Parent = panel

local function hidePanel()
	panel.Visible = false
end

closeButton.MouseButton1Click:Connect(hidePanel)

UserInputService.InputBegan:Connect(function(input: any, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
		hidePanel()
	end
end)

local function renderSnapshot(snapshot: any)
	local model = VillageUpgradeHubPresentation.BuildPanelModel(snapshot)
	panel.Visible = model.visible
	title.Text = model.title
	subtitle.Text = model.subtitle or ""
	body.Text = model.bodyText or ""
	accent.BackgroundColor3 = toneColor(model.tone)
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local responseRemote = remotesFolder:WaitForChild(RESPONSE_REMOTE_NAME) :: RemoteEvent
responseRemote.OnClientEvent:Connect(function(payload: any)
	renderSnapshot(payload)
end)
