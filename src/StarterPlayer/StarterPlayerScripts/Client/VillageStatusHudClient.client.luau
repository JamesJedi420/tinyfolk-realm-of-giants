--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local VillageStatusHudConfig = require(Config:WaitForChild("VillageStatusHudConfig"))
local VillageStatusHudPresentation = require(GiantRealm:WaitForChild("VillageStatusHudPresentation"))

local GUI_NAME = VillageStatusHudConfig.GuiName
local PANEL_NAME = VillageStatusHudConfig.PanelName

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(151, 159, 174),
	warning = Color3.fromRGB(224, 166, 68),
	critical = Color3.fromRGB(214, 88, 88),
}

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.neutral
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.neutral
end

local function collectSnapshot(): any
	local attrs = VillageStatusHudConfig.Attributes
	return {
		activeRaiderCount = localPlayer:GetAttribute(attrs.ActiveRaiderCount),
		workerCount = localPlayer:GetAttribute(attrs.WorkerCount),
		activeCaptiveCount = localPlayer:GetAttribute(attrs.ActiveCaptiveCount),
		foodStored = localPlayer:GetAttribute(attrs.FoodStored),
		foodInTransit = localPlayer:GetAttribute(attrs.FoodInTransit),
		morale = localPlayer:GetAttribute(attrs.Morale),
		lastFoodShortfall = localPlayer:GetAttribute(attrs.LastFoodShortfall),
		consecutiveShortfallTicks = localPlayer:GetAttribute(attrs.ConsecutiveShortfallTicks),
		woodProduced = localPlayer:GetAttribute(attrs.WoodProduced),
		stoneProduced = localPlayer:GetAttribute(attrs.StoneProduced),
		activeJobCount = localPlayer:GetAttribute(attrs.ActiveJobCount),
	}
end

local function hasVillageStatusProjection(): boolean
	return type(localPlayer:GetAttribute(VillageStatusHudConfig.Attributes.Summary)) == "string"
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
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromScale(0.02, 0.12)
panel.Size = UDim2.fromOffset(360, 128)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
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
title.Size = UDim2.fromOffset(336, 24)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Village Status"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 36)
summary.Size = UDim2.fromOffset(336, 84)
summary.Font = Enum.Font.Gotham
summary.TextSize = 15
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

local function refreshHud()
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant or not hasVillageStatusProjection() then
		panel.Visible = false
		return
	end

	local model = VillageStatusHudPresentation.BuildHudModel(collectSnapshot())
	panel.Visible = model.visible
	title.Text = model.title
	summary.Text = model.summary
	accent.BackgroundColor3 = toneColor(model.tone)
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

for _, attributeName in pairs(VillageStatusHudConfig.Attributes) do
	hookAttribute(attributeName)
end

localPlayer:GetAttributeChangedSignal("Role"):Connect(refreshHud)
refreshHud()
