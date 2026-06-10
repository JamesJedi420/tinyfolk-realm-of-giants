--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local RescueContractConfig = require(Config:WaitForChild("RescueContractConfig"))
local TrophyConfig = require(Config:WaitForChild("TrophyConfig"))
local TrophyCasePresentation = require(GiantRealm:WaitForChild("TrophyCasePresentation"))
local GiantReputationConfig = require(Config:WaitForChild("GiantReputationConfig"))

local GUI_NAME = "GiantTrophyCaseHudGui"
local PANEL_NAME = "Panel"
local SURFACE_GUI_NAME = "TrophyCaseSurfaceGui"

local surfaceBindings: { [Instance]: { header: any, body: any } } = {}

local function isActiveGiantRealmOwner(): boolean
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
		return false
	end
	local ownerUserId = localPlayer:GetAttribute(RescueContractConfig.TargetRealmOwnerUserIdAttribute)
	return type(ownerUserId) == "number" and ownerUserId == localPlayer.UserId
end

local function collectHudAttributes(): any
	local trophyAttrs = TrophyConfig.StateAttributes
	local reputationAttrs = GiantReputationConfig.StateAttributes
	return {
		trophies = {
			count = localPlayer:GetAttribute(trophyAttrs.Count),
			caseHeader = localPlayer:GetAttribute(trophyAttrs.CaseHeader),
			caseSummary = localPlayer:GetAttribute(trophyAttrs.CaseSummary),
			caseUpdatedAt = localPlayer:GetAttribute(trophyAttrs.CaseUpdatedAt),
		},
		reputation = {
			score = localPlayer:GetAttribute(reputationAttrs.Score),
			rank = localPlayer:GetAttribute(reputationAttrs.Rank),
			rankTitle = localPlayer:GetAttribute(reputationAttrs.RankTitle),
			scoreToNextRank = localPlayer:GetAttribute(reputationAttrs.ScoreToNextRank),
		},
	}
end

local function buildHudModel(attributes: any): any
	if type(attributes.trophies.caseHeader) == "string" and type(attributes.trophies.caseSummary) == "string" then
		return {
			visible = true,
			title = "Giant Trophy Case",
			header = attributes.trophies.caseHeader,
			body = attributes.trophies.caseSummary,
			count = if type(attributes.trophies.count) == "number" then attributes.trophies.count else 0,
		}
	end

	return TrophyCasePresentation.BuildCaseModel({}, attributes.reputation, TrophyConfig.CaseDisplayMaxEntries)
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
panel.Size = UDim2.fromOffset(320, 148)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.fromOffset(296, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Giant Trophy Case"
title.Parent = panel

local header = Instance.new("TextLabel")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(12, 32)
header.Size = UDim2.fromOffset(296, 20)
header.Font = Enum.Font.Gotham
header.TextSize = 13
header.TextColor3 = Color3.fromRGB(200, 176, 120)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = ""
header.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 54)
summary.Size = UDim2.fromOffset(296, 86)
summary.Font = Enum.Font.Gotham
summary.TextSize = 13
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

local function refreshHud()
	if not isActiveGiantRealmOwner() then
		panel.Visible = false
		return
	end

	local model = buildHudModel(collectHudAttributes())
	panel.Visible = model.visible
	title.Text = model.title
	header.Text = model.header
	summary.Text = model.body
end

local function ensureSurfaceGui(part: BasePart): { header: any, body: any }
	local existingSurface = part:FindFirstChild(SURFACE_GUI_NAME)
	if existingSurface ~= nil and existingSurface:IsA("SurfaceGui") then
		local existingHeader = existingSurface:FindFirstChild("Header")
		local existingBody = existingSurface:FindFirstChild("Body")
		if
			existingHeader ~= nil
			and existingHeader:IsA("TextLabel")
			and existingBody ~= nil
			and existingBody:IsA("TextLabel")
		then
			return { header = existingHeader, body = existingBody }
		end
		existingSurface:Destroy()
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = SURFACE_GUI_NAME
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 40
	surfaceGui.LightInfluence = 0
	surfaceGui.Parent = part

	local surfaceHeader = Instance.new("TextLabel")
	surfaceHeader.Name = "Header"
	surfaceHeader.BackgroundTransparency = 1
	surfaceHeader.Position = UDim2.fromOffset(8, 8)
	surfaceHeader.Size = UDim2.new(1, -16, 0, 24)
	surfaceHeader.Font = Enum.Font.GothamBold
	surfaceHeader.TextSize = 18
	surfaceHeader.TextColor3 = Color3.fromRGB(231, 234, 239)
	surfaceHeader.TextXAlignment = Enum.TextXAlignment.Left
	surfaceHeader.Text = "Giant Trophy Case"
	surfaceHeader.Parent = surfaceGui

	local surfaceBody = Instance.new("TextLabel")
	surfaceBody.Name = "Body"
	surfaceBody.BackgroundTransparency = 1
	surfaceBody.Position = UDim2.fromOffset(8, 34)
	surfaceBody.Size = UDim2.new(1, -16, 1, -42)
	surfaceBody.Font = Enum.Font.Gotham
	surfaceBody.TextSize = 14
	surfaceBody.TextColor3 = Color3.fromRGB(180, 188, 204)
	surfaceBody.TextXAlignment = Enum.TextXAlignment.Left
	surfaceBody.TextYAlignment = Enum.TextYAlignment.Top
	surfaceBody.TextWrapped = true
	surfaceBody.Text = ""
	surfaceBody.Parent = surfaceGui

	return { header = surfaceHeader, body = surfaceBody }
end

local function refreshMapSurface(part: any)
	local mapAttrs = TrophyConfig.MapSurfaceAttributes
	local headerText = part:GetAttribute(mapAttrs.Header)
	local summaryText = part:GetAttribute(mapAttrs.Summary)
	if type(headerText) ~= "string" or type(summaryText) ~= "string" then
		return
	end

	local labels = surfaceBindings[part]
	if labels == nil then
		labels = ensureSurfaceGui(part)
		surfaceBindings[part] = labels
	end

	labels.header.Text = headerText
	labels.body.Text = summaryText
end

local function bindMapSurface(part: any)
	if surfaceBindings[part] ~= nil then
		return
	end

	local labels = ensureSurfaceGui(part)
	surfaceBindings[part] = labels

	local mapAttrs = TrophyConfig.MapSurfaceAttributes
	part:GetAttributeChangedSignal(mapAttrs.Header):Connect(function()
		refreshMapSurface(part)
	end)
	part:GetAttributeChangedSignal(mapAttrs.Summary):Connect(function()
		refreshMapSurface(part)
	end)
	part:GetAttributeChangedSignal(mapAttrs.UpdatedAt):Connect(function()
		refreshMapSurface(part)
	end)

	refreshMapSurface(part)
end

local function scanMapSurfaces(root: any)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(TrophyConfig.TrophyCaseSurfaceAttribute) == true then
			bindMapSurface(descendant :: BasePart)
		end
	end
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

for _, attributeName in pairs(TrophyConfig.StateAttributes) do
	hookAttribute(attributeName)
end
for _, attributeName in pairs(GiantReputationConfig.StateAttributes) do
	hookAttribute(attributeName)
end

localPlayer:GetAttributeChangedSignal("Role"):Connect(refreshHud)
localPlayer:GetAttributeChangedSignal(RescueContractConfig.TargetRealmOwnerUserIdAttribute):Connect(refreshHud)

scanMapSurfaces(Workspace)
Workspace.DescendantAdded:Connect(function(descendant: Instance)
	if descendant:IsA("BasePart") and descendant:GetAttribute(TrophyConfig.TrophyCaseSurfaceAttribute) == true then
		bindMapSurface(descendant)
	end
end)

refreshHud()
