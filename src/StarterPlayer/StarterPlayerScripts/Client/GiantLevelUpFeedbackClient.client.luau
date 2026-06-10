--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local GiantLevelConfig = require(Config:WaitForChild("GiantLevelConfig"))
local GiantLevelPresentation = require(GiantRealm:WaitForChild("GiantLevelPresentation"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))

local GUI_NAME = "GiantLevelUpFeedbackGui"
local PANEL_NAME = "Panel"
local DISPLAY_SECONDS = 3.5

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
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.fromScale(0.5, 0.16)
panel.Size = UDim2.fromOffset(360, 88)
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
title.Size = UDim2.fromOffset(336, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Giant Level Up"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 34)
summary.Size = UDim2.fromOffset(336, 44)
summary.Font = Enum.Font.Gotham
summary.TextSize = 14
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

local hideAt = 0
local lastSeenSignal = localPlayer:GetAttribute(GiantLevelConfig.StateAttributes.LevelUpSignal)

local function isGiantRole(): boolean
	return localPlayer:GetAttribute("Role") == RoleConfig.Roles.Giant
end

local function renderLevelUp()
	if not isGiantRole() then
		return
	end

	local model = GiantLevelPresentation.BuildLevelUpFeedbackModel({
		level = localPlayer:GetAttribute(GiantLevelConfig.StateAttributes.LastLevelUpLevel),
	})
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

local function onLevelUpSignalChanged()
	local signal = localPlayer:GetAttribute(GiantLevelConfig.StateAttributes.LevelUpSignal)
	if type(signal) ~= "number" then
		return
	end
	if lastSeenSignal == signal then
		return
	end
	lastSeenSignal = signal
	renderLevelUp()
end

localPlayer:GetAttributeChangedSignal(GiantLevelConfig.StateAttributes.LevelUpSignal):Connect(onLevelUpSignalChanged)
localPlayer:GetAttributeChangedSignal("Role"):Connect(function()
	if not isGiantRole() then
		panel.Visible = false
		hideAt = 0
	end
end)
