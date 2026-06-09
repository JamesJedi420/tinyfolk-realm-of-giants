--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local GiantEffectHudConfig = require(Config:WaitForChild("GiantEffectHudConfig"))
local GiantEffectHudPresentation = require(GiantRealm:WaitForChild("GiantEffectHudPresentation"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))

local GUI_NAME = "GiantEffectHudGui"
local PANEL_NAME = "Panel"

local function collectAttributes(): any
	local attributes = GiantEffectHudConfig.Attributes
	return {
		maxHealth = localPlayer:GetAttribute(attributes.MaxHealth),
		walkSpeed = localPlayer:GetAttribute(attributes.WalkSpeed),
		powerBudget = localPlayer:GetAttribute(attributes.PowerBudget),
		movementControl = localPlayer:GetAttribute(attributes.MovementControl),
		maxHealthBonus = localPlayer:GetAttribute(attributes.MaxHealthBonus),
		walkSpeedBonus = localPlayer:GetAttribute(attributes.WalkSpeedBonus),
		powerBudgetBonus = localPlayer:GetAttribute(attributes.PowerBudgetBonus),
		movementControlBonus = localPlayer:GetAttribute(attributes.MovementControlBonus),
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
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.fromScale(0.98, 0.14)
panel.Size = UDim2.fromOffset(320, 72)
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
title.Text = "Giant Effects"
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

local function refreshHud()
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
		panel.Visible = false
		return
	end

	local model = GiantEffectHudPresentation.BuildHudModel(collectAttributes())
	panel.Visible = model.visible
	title.Text = model.title
	summary.Text = model.summary
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

for _, attributeName in pairs(GiantEffectHudConfig.Attributes) do
	hookAttribute(attributeName)
end

localPlayer:GetAttributeChangedSignal("Role"):Connect(refreshHud)
refreshHud()
