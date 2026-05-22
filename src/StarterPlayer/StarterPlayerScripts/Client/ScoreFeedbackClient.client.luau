--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ScoreConfig = require(Config:WaitForChild("ScoreConfig"))
local ScoreFeedbackPresentation = require(Shared:WaitForChild("ScoreFeedbackPresentation"))

local GUI_NAME = "ScoreFeedbackGui"
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

local function makeLabel(
	parent: Instance,
	name: string,
	textSize: number,
	yOffset: number,
	height: number,
	font: any?
): any
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, yOffset)
	label.Size = UDim2.fromOffset(270, height)
	label.Font = font or Enum.Font.Gotham
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(231, 234, 239)
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
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.fromScale(0.98, 0.12)
panel.Size = UDim2.fromOffset(300, 100)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.22
stroke.Color = ACCENT_BY_TONE.neutral
stroke.Parent = panel

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Size = UDim2.new(1, 0, 0, 4)
accent.BackgroundColor3 = ACCENT_BY_TONE.neutral
accent.BorderSizePixel = 0
accent.Parent = panel

local title = makeLabel(panel, "Title", 15, 8, 20, Enum.Font.GothamBold)
title.Text = "Score Update"

local headline = makeLabel(panel, "Headline", 14, 28, 18, Enum.Font.GothamMedium)
headline.Text = ""

local detail = makeLabel(panel, "Detail", 12, 48, 18, Enum.Font.Gotham)
detail.TextColor3 = Color3.fromRGB(203, 208, 216)
detail.Text = ""

local total = makeLabel(panel, "Total", 12, 70, 18, Enum.Font.Gotham)
total.TextColor3 = Color3.fromRGB(180, 187, 198)
total.Text = ""

local function collectAttributes(): { [string]: any }
	local attrs = ScoreConfig.StateAttributes
	return {
		ScoreTotal = localPlayer:GetAttribute(attrs.ScoreTotal),
		ScoreLastReason = localPlayer:GetAttribute(attrs.ScoreLastReason),
		ScoreLastFeedbackKey = localPlayer:GetAttribute(attrs.ScoreLastFeedbackKey),
		ScoreLastAwardedPoints = localPlayer:GetAttribute(attrs.ScoreLastAwardedPoints),
		ScoreLastBucket = localPlayer:GetAttribute(attrs.ScoreLastBucket),
		ScoreLastCategoryCapReached = localPlayer:GetAttribute(attrs.ScoreLastCategoryCapReached),
	}
end

local latestModel: any = nil
local visibleUntilAt = 0

local function renderModel(model: any)
	if model == nil or model.visible ~= true then
		panel.Visible = false
		latestModel = nil
		return
	end

	local accentColor = toneColor(model.tone)
	latestModel = model
	visibleUntilAt = os.clock() + DISPLAY_SECONDS
	panel.Visible = true
	accent.BackgroundColor3 = accentColor
	stroke.Color = accentColor
	title.TextColor3 = accentColor
	headline.Text = model.headline
	detail.Text = model.detail
	total.Text = model.totalText
end

local function refreshHud()
	renderModel(ScoreFeedbackPresentation.BuildScoreModel(ScoreConfig, collectAttributes()))
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

hookAttribute(ScoreConfig.StateAttributes.ScoreTotal)
hookAttribute(ScoreConfig.StateAttributes.ScoreLastReason)
hookAttribute(ScoreConfig.StateAttributes.ScoreLastFeedbackKey)
hookAttribute(ScoreConfig.StateAttributes.ScoreLastAwardedPoints)
hookAttribute(ScoreConfig.StateAttributes.ScoreLastBucket)
hookAttribute(ScoreConfig.StateAttributes.ScoreLastCategoryCapReached)

RunService.RenderStepped:Connect(function()
	if latestModel == nil then
		return
	end

	if os.clock() > visibleUntilAt then
		panel.Visible = false
		return
	end

	panel.Visible = true
end)

localPlayer.CharacterAdded:Connect(refreshHud)

refreshHud()
