--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local VillageWorksiteUpgradePresentation = require(GiantRealm:WaitForChild("VillageWorksiteUpgradePresentation"))

local REMOTES_FOLDER_NAME = "Remotes"
local RESPONSE_REMOTE_NAME = "VillageWorksiteUpgradeResponse"
local DISPLAY_SECONDS = 3.5

local GUI_NAME = "GiantWorksiteUpgradeFeedbackGui"
local PANEL_NAME = "Panel"

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(151, 159, 174),
	positive = Color3.fromRGB(74, 160, 102),
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
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.fromScale(0.98, 0.42)
panel.Size = UDim2.fromOffset(320, 88)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
panel.BackgroundTransparency = 0.08
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
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.fromOffset(296, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Worksite Upgrade"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 34)
summary.Size = UDim2.fromOffset(296, 44)
summary.Font = Enum.Font.Gotham
summary.TextSize = 14
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

local hideAt = 0

local function renderPayload(payload: any)
	local model = VillageWorksiteUpgradePresentation.BuildFeedbackModel(payload)
	panel.Visible = model.visible
	title.Text = model.title
	summary.Text = model.summary
	accent.BackgroundColor3 = toneColor(model.tone)
	if model.visible then
		hideAt = os.clock() + DISPLAY_SECONDS
	end
end

RunService.RenderStepped:Connect(function()
	if hideAt > 0 and os.clock() >= hideAt then
		hideAt = 0
		panel.Visible = false
	end
end)

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local responseRemote = remotesFolder:WaitForChild(RESPONSE_REMOTE_NAME) :: RemoteEvent
responseRemote.OnClientEvent:Connect(function(payload: any)
	renderPayload(payload)
end)
