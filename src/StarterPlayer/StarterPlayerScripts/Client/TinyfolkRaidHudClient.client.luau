--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TinyfolkStatusConfig = require(Config:WaitForChild("TinyfolkStatusConfig"))
local RaidHudPresentation = require(Shared:WaitForChild("TinyfolkStatus"):WaitForChild("TinyfolkRaidHudPresentation"))

local GUI_NAME = "TinyfolkRaidHudGui"
local PANEL_NAME = "Panel"
local TITLE_NAME = "Title"
local STATUS_NAME = "Status"
local SUMMARY_NAME = "Summary"
local CUSTODY_NAME = "Custody"
local EFFECTS_NAME = "Effects"
local TEAM_NAME = "Team"
local SCORE_NAME = "Score"
local SUPPORT_NAME = "Support"
local UPDATED_NAME = "Updated"

local ACCENT_BY_TONE = {
	none = Color3.fromRGB(102, 113, 132),
	low = Color3.fromRGB(74, 160, 102),
	medium = Color3.fromRGB(224, 166, 68),
	high = Color3.fromRGB(220, 94, 94),
}

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.none
	end

	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.none
end

local function makeLabel(parent: Instance, name: string, textSize: number, yOffset: number, height: number): any
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, yOffset)
	label.Size = UDim2.fromOffset(352, height)
	label.Font = Enum.Font.Gotham
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(224, 228, 235)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = false
	label.Parent = parent
	return label
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
panel.Position = UDim2.fromScale(0.02, 0.14)
panel.Size = UDim2.fromOffset(380, 210)
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(78, 86, 102)
stroke.Transparency = 0.2
stroke.Parent = panel

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Size = UDim2.new(1, 0, 0, 4)
accent.BackgroundColor3 = ACCENT_BY_TONE.none
accent.BorderSizePixel = 0
accent.Parent = panel

local title = makeLabel(panel, TITLE_NAME, 17, 10, 22)
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(242, 244, 248)
title.Text = "Tinyfolk Raid Status"

local status = makeLabel(panel, STATUS_NAME, 14, 36, 18)
status.Font = Enum.Font.GothamMedium
status.TextColor3 = Color3.fromRGB(224, 166, 68)
status.Text = "Threat: --"

local summary = makeLabel(panel, SUMMARY_NAME, 12, 60, 34)
summary.TextColor3 = Color3.fromRGB(210, 214, 222)
summary.Text = "Summary: --"

local custody = makeLabel(panel, CUSTODY_NAME, 12, 96, 18)
custody.Text = "Custody: --"

local effects = makeLabel(panel, EFFECTS_NAME, 12, 118, 18)
effects.Text = "Effects: --"

local team = makeLabel(panel, TEAM_NAME, 12, 140, 18)
team.Text = "Team: --"

local score = makeLabel(panel, SCORE_NAME, 12, 162, 18)
score.Text = "Score: --"

local support = makeLabel(panel, SUPPORT_NAME, 12, 182, 18)
support.TextColor3 = Color3.fromRGB(156, 196, 224)
support.Text = "Support: --"

local updated = makeLabel(panel, UPDATED_NAME, 11, 202, 14)
updated.TextColor3 = Color3.fromRGB(156, 164, 176)
updated.Text = "Updated at --"

local function collectAttributes(): { [string]: any }
	local attributes = TinyfolkStatusConfig.Attributes
	return {
		Role = localPlayer:GetAttribute("Role"),
		RaidHudSummary = localPlayer:GetAttribute(attributes.RaidHudSummary),
		RaidHudThreatLevel = localPlayer:GetAttribute(attributes.RaidHudThreatLevel),
		RaidHudThreatStage = localPlayer:GetAttribute(attributes.RaidHudThreatStage),
		RaidHudCustodyState = localPlayer:GetAttribute(attributes.RaidHudCustodyState),
		RaidHudPersonalEffects = localPlayer:GetAttribute(attributes.RaidHudPersonalEffects),
		RaidHudTeammateActivity = localPlayer:GetAttribute(attributes.RaidHudTeammateActivity),
		RaidHudScoreFeedback = localPlayer:GetAttribute(attributes.RaidHudScoreFeedback),
		RaidHudUpdatedAt = localPlayer:GetAttribute(attributes.RaidHudUpdatedAt),
	}
end

local function refreshHud()
	local model = RaidHudPresentation.BuildHudModel(TinyfolkStatusConfig, collectAttributes())
	panel.Visible = model.visible
	if not model.visible then
		return
	end

	local accentColor = toneColor(model.accentTone)
	accent.BackgroundColor3 = accentColor
	stroke.Color = accentColor
	title.Text = model.title
	status.Text = model.status
	status.TextColor3 = accentColor
	summary.Text = model.summary
	custody.Text = model.custody
	effects.Text = model.personalEffects
	team.Text = model.teammateActivity
	score.Text = model.scoreFeedback
	support.Text = model.support
	updated.Text = model.updatedAt
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

hookAttribute("Role")
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudSummary)
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudThreatLevel)
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudThreatStage)
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudCustodyState)
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudPersonalEffects)
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudTeammateActivity)
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudScoreFeedback)
hookAttribute(TinyfolkStatusConfig.Attributes.RaidHudUpdatedAt)

localPlayer.CharacterAdded:Connect(refreshHud)

refreshHud()
