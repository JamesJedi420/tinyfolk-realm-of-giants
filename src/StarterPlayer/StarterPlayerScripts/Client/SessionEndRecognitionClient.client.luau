--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local ScoreConfig = require(Config:WaitForChild("ScoreConfig"))
local SessionEndRecognitionPresentation = require(Shared:WaitForChild("SessionEndRecognitionPresentation"))

local GUI_NAME = "SessionEndRecognitionGui"
local PANEL_NAME = "Panel"
local DISPLAY_SECONDS = 4.5
local REFRESH_INTERVAL = 0.2

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(164, 171, 180),
	positive = Color3.fromRGB(226, 188, 95),
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
	label.Position = UDim2.fromOffset(14, yOffset)
	label.Size = UDim2.fromOffset(282, height)
	label.Font = font or Enum.Font.Gotham
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(239, 240, 244)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = false
	label.Parent = parent
	return label
end

local function findRoutesRoot(): Instance?
	local mapFolder = Workspace:FindFirstChild("Map")
	if mapFolder == nil then
		return nil
	end

	local routesFolder = mapFolder:FindFirstChild("EscapeRoutes")
	if routesFolder == nil then
		return nil
	end

	return routesFolder
end

local function stringValue(value: any): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function finiteNonNegativeNumber(value: any): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value < 0 then
		return nil
	end
	return value
end

local function collectResolvedRouteSnapshot(): any
	local routesRoot = findRoutesRoot()
	local routesRootAny: any = routesRoot
	if routesRootAny == nil or type(routesRootAny.GetDescendants) ~= "function" then
		return nil
	end

	local candidates = {}
	for _, descendant in routesRootAny:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and string.match(descendant.Name, "^" .. EscapeConfig.EscapeRouteNamePrefix) ~= nil
		then
			local finalExitManaged = descendant:GetAttribute(EscapeConfig.FinalExitManagedAttribute)
			if finalExitManaged ~= false then
				local phase = stringValue(descendant:GetAttribute(EscapeConfig.FinalExitPhaseAttribute))
				if phase == "Resolved" then
					table.insert(candidates, {
						routeId = descendant.Name,
						finalExitPhase = phase,
						finalExitResolvedAt = descendant:GetAttribute(EscapeConfig.FinalExitResolvedAtAttribute),
					})
				end
			end
		end
	end

	if #candidates == 0 then
		return nil
	end

	table.sort(candidates, function(a: any, b: any)
		local aResolvedAt = finiteNonNegativeNumber(a.finalExitResolvedAt) or -1
		local bResolvedAt = finiteNonNegativeNumber(b.finalExitResolvedAt) or -1
		if aResolvedAt ~= bResolvedAt then
			return aResolvedAt > bResolvedAt
		end
		return tostring(a.routeId) < tostring(b.routeId)
	end)

	return candidates[1]
end

local function collectScoreAttributes(): { [string]: any }
	local attrs = ScoreConfig.StateAttributes
	return {
		ScoreTotal = localPlayer:GetAttribute(attrs.ScoreTotal),
		ScoreLastFeedbackKey = localPlayer:GetAttribute(attrs.ScoreLastFeedbackKey),
		ScoreLastAwardedPoints = localPlayer:GetAttribute(attrs.ScoreLastAwardedPoints),
		ScoreLastBucket = localPlayer:GetAttribute(attrs.ScoreLastBucket),
		ScoreLastCategoryCapReached = localPlayer:GetAttribute(attrs.ScoreLastCategoryCapReached),
	}
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
panel.Position = UDim2.fromScale(0.5, 0.08)
panel.Size = UDim2.fromOffset(326, 124)
panel.BackgroundColor3 = Color3.fromRGB(13, 15, 19)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.2
stroke.Color = ACCENT_BY_TONE.neutral
stroke.Parent = panel

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Size = UDim2.new(1, 0, 0, 4)
accent.BackgroundColor3 = ACCENT_BY_TONE.neutral
accent.BorderSizePixel = 0
accent.Parent = panel

local title = makeLabel(panel, "Title", 15, 9, 20, Enum.Font.GothamBold)
title.Text = "Session Complete"

local headline = makeLabel(panel, "Headline", 14, 31, 20, Enum.Font.GothamMedium)
headline.Text = ""

local detail = makeLabel(panel, "Detail", 12, 55, 20, Enum.Font.Gotham)
detail.TextColor3 = Color3.fromRGB(201, 206, 213)
detail.Text = ""

local footer = makeLabel(panel, "Footer", 12, 79, 20, Enum.Font.Gotham)
footer.TextColor3 = Color3.fromRGB(176, 183, 193)
footer.Text = ""

local latestModel: any = nil
local visibleUntilAt = 0
local lastDisplayedRouteKey: string? = nil
local nextRefreshAt = 0

local function buildRouteKey(model: any): string
	return string.format("%s@%s", tostring(model.routeId or "unknown"), tostring(model.resolvedAt or "unknown"))
end

local function renderModel(model: any)
	if model == nil or model.visible ~= true then
		panel.Visible = false
		latestModel = nil
		return
	end

	local accentColor = toneColor(model.tone)
	latestModel = model
	visibleUntilAt = os.clock() + DISPLAY_SECONDS
	lastDisplayedRouteKey = buildRouteKey(model)
	panel.Visible = true
	accent.BackgroundColor3 = accentColor
	stroke.Color = accentColor
	title.TextColor3 = accentColor
	headline.Text = model.headline
	detail.Text = model.detail
	footer.Text = model.footer
end

local function refreshHud()
	local model = SessionEndRecognitionPresentation.BuildSessionEndRecognitionModel(
		collectResolvedRouteSnapshot(),
		collectScoreAttributes()
	)

	if model.visible ~= true then
		if latestModel ~= nil then
			panel.Visible = false
			latestModel = nil
		end
		return
	end

	local routeKey = buildRouteKey(model)
	if routeKey == lastDisplayedRouteKey then
		return
	end

	renderModel(model)
end

RunService.RenderStepped:Connect(function()
	local currentTime = os.clock()
	if latestModel ~= nil and currentTime > visibleUntilAt then
		panel.Visible = false
		latestModel = nil
	end

	if currentTime >= nextRefreshAt then
		nextRefreshAt = currentTime + REFRESH_INTERVAL
		refreshHud()
	end
end)

localPlayer.CharacterAdded:Connect(refreshHud)

refreshHud()
