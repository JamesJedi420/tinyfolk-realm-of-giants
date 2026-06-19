--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local SocialEconomyConfig = require(Config:WaitForChild("SocialEconomyConfig"))
local PenRationingConfig = require(Config:WaitForChild("PenRationingConfig"))
local PenRationingHudPresentation = require(GiantRealm:WaitForChild("PenRationingHudPresentation"))
local PenRationingState = require(GiantRealm:WaitForChild("PenRationingState"))

local GUI_NAME = "PenRationingHudGui"
local PANEL_NAME = "Panel"
local DEFAULT_PEN_ID = PenRationingConfig.DefaultPenId

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(151, 159, 174),
	warning = Color3.fromRGB(224, 166, 68),
}

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.neutral
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.neutral
end

local function findPenPart(penId: string): BasePart?
	local map = Workspace:FindFirstChild("Map")
	if map == nil then
		return nil
	end
	local stations = map:FindFirstChild("Stations")
	if stations == nil then
		return nil
	end

	for _, descendant in ipairs(stations:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == penId then
			return descendant
		end
	end
	return nil
end

local penPart = findPenPart(DEFAULT_PEN_ID)

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
panel.Position = UDim2.fromScale(0.98, 0.24)
panel.Size = UDim2.fromOffset(320, 72)
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
title.Size = UDim2.fromOffset(296, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Pen Rationing"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 34)
summary.Size = UDim2.fromOffset(296, 32)
summary.Font = Enum.Font.Gotham
summary.TextSize = 13
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

local attrs = PenRationingConfig.StateAttributes

local function collectSnapshot(): any
	local role = localPlayer:GetAttribute("Role")
	local snapshot: any = {
		role = role,
		captureActive = localPlayer:GetAttribute("CaptureActive") == true,
		custodianMorale = localPlayer:GetAttribute(attrs.CustodianMorale),
		captiveShortfallStreak = localPlayer:GetAttribute(attrs.CaptiveShortfallStreak),
		captiveStarving = localPlayer:GetAttribute(attrs.CaptiveStarving) == true,
		moraleDefault = PenRationingConfig.MoraleDefault,
		moraleCaptureSureThreshold = PenRationingConfig.MoraleCaptureSureThreshold,
		captureReadinessPercent = PenRationingState.ComputeCaptureReadinessPercent(
			localPlayer:GetAttribute(attrs.CustodianMorale) or PenRationingConfig.MoraleDefault,
			PenRationingConfig.MoraleCaptureSureThreshold
		),
		controlIntimidationBonus = localPlayer:GetAttribute(
			SocialEconomyConfig.StateAttributes.ControlIntimidationBonus
		),
	}

	if penPart ~= nil then
		snapshot.lastFoodShortfall = penPart:GetAttribute(attrs.LastFoodShortfall) == true
		snapshot.consecutiveShortfallTicks = penPart:GetAttribute(attrs.ConsecutiveShortfallTicks)
		snapshot.activeCaptiveCount = penPart:GetAttribute(attrs.ActiveCaptiveCount)
		snapshot.foodCostMultiplier = penPart:GetAttribute(attrs.FoodCostMultiplier)
	end

	return snapshot
end

local function refreshHud()
	local model = PenRationingHudPresentation.BuildHudModel(collectSnapshot())
	panel.Visible = model.visible
	title.Text = model.title
	summary.Text = model.summary
	accent.BackgroundColor3 = toneColor(model.tone)
end

local function hookPlayerAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

hookPlayerAttribute("Role")
hookPlayerAttribute("CaptureActive")
hookPlayerAttribute(attrs.CustodianMorale)
hookPlayerAttribute(attrs.CaptiveShortfallStreak)
hookPlayerAttribute(attrs.CaptiveStarving)
hookPlayerAttribute(SocialEconomyConfig.StateAttributes.ControlIntimidationBonus)

if penPart ~= nil then
	local penPartAny = penPart :: any
	penPartAny:GetAttributeChangedSignal(attrs.LastFoodShortfall):Connect(refreshHud)
	penPartAny:GetAttributeChangedSignal(attrs.ConsecutiveShortfallTicks):Connect(refreshHud)
	penPartAny:GetAttributeChangedSignal(attrs.ActiveCaptiveCount):Connect(refreshHud)
	penPartAny:GetAttributeChangedSignal(attrs.FoodCostMultiplier):Connect(refreshHud)
end

refreshHud()
