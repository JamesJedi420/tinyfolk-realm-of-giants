--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SocialEconomyConfig = require(Config:WaitForChild("SocialEconomyConfig"))
local SocialEconomyPresentation = require(GiantRealm:WaitForChild("SocialEconomyPresentation"))

local GUI_NAME = "SocialEconomyHudGui"
local PANEL_NAME = "Panel"

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(151, 159, 174),
	warm = Color3.fromRGB(224, 166, 68),
	cold = Color3.fromRGB(96, 146, 214),
}

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.neutral
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.neutral
end

local function collectSnapshot(): any
	local attrs = SocialEconomyConfig.StateAttributes
	return {
		favor = localPlayer:GetAttribute(attrs.Favor),
		control = localPlayer:GetAttribute(attrs.Control),
		dominantAxis = localPlayer:GetAttribute(attrs.DominantAxis),
		favorComplianceBonus = localPlayer:GetAttribute(attrs.FavorComplianceBonus),
		controlIntimidationBonus = localPlayer:GetAttribute(attrs.ControlIntimidationBonus),
	}
end

local function hasSocialEconomyProjection(): boolean
	return type(localPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.Favor)) == "number"
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
panel.Position = UDim2.fromScale(0.98, 0.36)
panel.Size = UDim2.fromOffset(320, 88)
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
title.Text = "Realm Social Economy"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 34)
summary.Size = UDim2.fromOffset(296, 44)
summary.Font = Enum.Font.Gotham
summary.TextSize = 13
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

local function refreshHud()
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant or not hasSocialEconomyProjection() then
		panel.Visible = false
		return
	end

	local model = SocialEconomyPresentation.BuildHudModel(collectSnapshot())
	panel.Visible = model.visible
	title.Text = model.title
	summary.Text = model.summary
	accent.BackgroundColor3 = toneColor(model.tone)
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

for _, attributeName in pairs(SocialEconomyConfig.StateAttributes) do
	hookAttribute(attributeName)
end

localPlayer:GetAttributeChangedSignal("Role"):Connect(refreshHud)
refreshHud()
