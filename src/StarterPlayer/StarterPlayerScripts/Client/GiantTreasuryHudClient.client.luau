--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local GiantRealmTreasuryConfig = require(Config:WaitForChild("GiantRealmTreasuryConfig"))
local GiantRealmTreasuryPresentation = require(GiantRealm:WaitForChild("GiantRealmTreasuryPresentation"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))

local GUI_NAME = "GiantTreasuryHudGui"
local PANEL_NAME = "Panel"

local function collectAttributes(): any
	local attributes = GiantRealmTreasuryConfig.Attributes
	return {
		LedgerEssence = localPlayer:GetAttribute(attributes.LedgerEssence),
		LedgerWood = localPlayer:GetAttribute(attributes.LedgerWood),
		LedgerStone = localPlayer:GetAttribute(attributes.LedgerStone),
		SessionEssence = localPlayer:GetAttribute(attributes.SessionEssence),
		SessionWood = localPlayer:GetAttribute(attributes.SessionWood),
		SessionStone = localPlayer:GetAttribute(attributes.SessionStone),
		Summary = localPlayer:GetAttribute(attributes.Summary),
		UpdatedAt = localPlayer:GetAttribute(attributes.UpdatedAt),
	}
end

local function buildPresentationInput(attributes: any)
	local ledgerInput = {
		essence = attributes.LedgerEssence,
		wood = attributes.LedgerWood,
		stone = attributes.LedgerStone,
	}
	local sessionInput = {
		essenceStored = attributes.SessionEssence,
		woodStored = attributes.SessionWood,
		stoneStored = attributes.SessionStone,
	}
	return ledgerInput, sessionInput
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
panel.Position = UDim2.fromScale(0.98, 0.28)
panel.Size = UDim2.fromOffset(320, 96)
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
title.Text = "Giant Realm Treasury"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 34)
summary.Size = UDim2.fromOffset(296, 52)
summary.Font = Enum.Font.Gotham
summary.TextSize = 14
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

local function refreshHud()
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
		panel.Visible = false
		return
	end

	local attributes = collectAttributes()
	local ledgerInput, sessionInput = buildPresentationInput(attributes)
	local model = GiantRealmTreasuryPresentation.BuildHudModel(ledgerInput, sessionInput)
	panel.Visible = model.visible
	title.Text = model.title
	summary.Text = model.summary
end

local function hookAttribute(attributeName: string)
	local attributeChanged = localPlayer:GetAttributeChangedSignal(attributeName)
	attributeChanged:Connect(refreshHud)
end

for _, attributeName in pairs(GiantRealmTreasuryConfig.Attributes) do
	hookAttribute(attributeName)
end

localPlayer:GetAttributeChangedSignal("Role"):Connect(refreshHud)
refreshHud()
