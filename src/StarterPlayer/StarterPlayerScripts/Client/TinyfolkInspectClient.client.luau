--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TinyfolkInspectConfig = require(Config:WaitForChild("TinyfolkInspectConfig"))
local TinyfolkInspectState = require(GiantRealm:WaitForChild("TinyfolkInspectState"))
local TinyfolkInspectPresentation = require(GiantRealm:WaitForChild("TinyfolkInspectPresentation"))

local GUI_NAME = TinyfolkInspectConfig.GuiName
local PANEL_NAME = TinyfolkInspectConfig.PanelName
local MAX_SELECT_RANGE = TinyfolkInspectConfig.MaxSelectRangeStuds
local RAYCAST_DISTANCE = 1000

local PANEL_ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(151, 159, 174),
	warning = Color3.fromRGB(224, 166, 68),
	critical = Color3.fromRGB(214, 88, 88),
}

local function highlightColorForTone(tone: string?): Color3
	if type(tone) ~= "string" then
		tone = TinyfolkInspectConfig.Tones.Neutral
	end
	local rgb = TinyfolkInspectConfig.HighlightAccentRgbByTone[tone]
	if type(rgb) == "table" and #rgb >= 3 then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return Color3.fromRGB(151, 159, 174)
end

local selectedTarget: Player? = nil
local targetAttributeConnections: { any } = {}
local targetCharacterConnections: { any } = {}
local activeHighlight: Highlight? = nil
local activeHighlightCharacter: Model? = nil

local refreshPanel: () -> ()

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function panelAccentColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return PANEL_ACCENT_BY_TONE.neutral
	end
	return PANEL_ACCENT_BY_TONE[tone] or PANEL_ACCENT_BY_TONE.neutral
end

local function isLocalPlayerGiant(): boolean
	return localPlayer:GetAttribute("Role") == RoleConfig.Roles.Giant
end

local function isPlayerTinyfolk(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
end

local function getRootPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getCharacterFromPart(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if model == nil then
		return nil
	end
	if model:FindFirstChildOfClass("Humanoid") ~= nil then
		return model
	end
	return nil
end

local function collectTargetAttributes(target: Player): { [string]: any }
	local attributes: { [string]: any } = {}
	for _, attributeName in pairs(TinyfolkInspectConfig.Attributes) do
		attributes[attributeName] = target:GetAttribute(attributeName)
	end
	return attributes
end

local function buildSnapshotForTarget(target: Player): any
	return TinyfolkInspectState.CollectAttributeInput(target.DisplayName, collectTargetAttributes(target))
end

local function disconnectTargetConnections()
	for _, connection in ipairs(targetAttributeConnections) do
		connection:Disconnect()
	end
	for _, connection in ipairs(targetCharacterConnections) do
		connection:Disconnect()
	end
	table.clear(targetAttributeConnections)
	table.clear(targetCharacterConnections)
end

local function clearHighlight()
	if activeHighlight ~= nil then
		activeHighlight:Destroy()
		activeHighlight = nil
	end
	activeHighlightCharacter = nil
end

local function applyHighlightTone(highlight: Highlight, tone: string?)
	local color = highlightColorForTone(tone)
	highlight.FillColor = color
	highlight.OutlineColor = color
end

local function applyHighlight(character: Model?, tone: string?)
	clearHighlight()
	if character == nil then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = TinyfolkInspectConfig.HighlightName
	highlight.Adornee = character
	highlight.FillTransparency = TinyfolkInspectConfig.HighlightFillTransparency
	highlight.OutlineTransparency = TinyfolkInspectConfig.HighlightOutlineTransparency
	highlight.DepthMode = TinyfolkInspectConfig.HighlightDepthMode
	applyHighlightTone(highlight, tone)
	highlight.Parent = character

	activeHighlight = highlight
	activeHighlightCharacter = character
end

local function syncHighlight(character: Model?, tone: string?)
	if character == nil then
		clearHighlight()
		return
	end

	if activeHighlight ~= nil and activeHighlightCharacter == character then
		applyHighlightTone(activeHighlight, tone)
		return
	end

	applyHighlight(character, tone)
end

local function clearSelection()
	disconnectTargetConnections()
	clearHighlight()
	selectedTarget = nil
end

local function isTargetInspectable(target: Player): boolean
	if not isPlayerTinyfolk(target) then
		return false
	end

	local localRoot = getRootPart(localPlayer.Character)
	local targetRoot = getRootPart(target.Character)
	if localRoot == nil or targetRoot == nil then
		return false
	end

	local distance = (targetRoot.Position - localRoot.Position).Magnitude
	return distance <= MAX_SELECT_RANGE
end

local function hookTarget(target: Player)
	disconnectTargetConnections()

	for _, attributeName in pairs(TinyfolkInspectConfig.Attributes) do
		local connection = target:GetAttributeChangedSignal(attributeName):Connect(refreshPanel)
		table.insert(targetAttributeConnections, connection)
	end

	local characterRemovingConnection = target.CharacterRemoving:Connect(function()
		clearSelection()
		refreshPanel()
	end)
	table.insert(targetCharacterConnections, characterRemovingConnection)

	local characterAddedConnection = target.CharacterAdded:Connect(refreshPanel)
	table.insert(targetCharacterConnections, characterAddedConnection)
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
panel.Position = UDim2.fromScale(0.02, 0.58)
panel.Size = UDim2.fromOffset(360, 168)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.BackgroundColor3 = PANEL_ACCENT_BY_TONE.neutral
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
title.Text = "Tinyfolk Inspect"
title.Parent = panel

local summary = Instance.new("TextLabel")
summary.Name = "Summary"
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(12, 36)
summary.Size = UDim2.fromOffset(336, 124)
summary.Font = Enum.Font.Gotham
summary.TextSize = 15
summary.TextColor3 = Color3.fromRGB(180, 188, 204)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.TextWrapped = true
summary.Text = ""
summary.Parent = panel

function refreshPanel()
	if not isLocalPlayerGiant() then
		panel.Visible = false
		clearSelection()
		return
	end

	local target = selectedTarget
	if target == nil or not target.Parent then
		panel.Visible = false
		clearHighlight()
		return
	end

	if not isTargetInspectable(target) then
		clearSelection()
		panel.Visible = false
		return
	end

	local attributeInput = buildSnapshotForTarget(target)
	local model = TinyfolkInspectPresentation.BuildPanelModel(attributeInput)
	local highlightTone = TinyfolkInspectState.ResolveHighlightTone(attributeInput)
	panel.Visible = model.visible
	title.Text = model.title
	summary.Text = model.summary
	accent.BackgroundColor3 = panelAccentColor(model.tone)
	syncHighlight(target.Character, highlightTone)
end

local function selectTarget(target: Player?)
	if target == nil then
		clearSelection()
		refreshPanel()
		return
	end

	if not isTargetInspectable(target) then
		clearSelection()
		refreshPanel()
		return
	end

	selectedTarget = target
	hookTarget(target)
	refreshPanel()
end

local function resolveTinyfolkFromRaycast(): Player?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	raycastParams.FilterDescendantsInstances = { localPlayer.Character or localPlayer }

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE, raycastParams)
	if result == nil then
		return nil
	end

	local hitPart = result.Instance
	if not hitPart:IsA("BasePart") then
		return nil
	end

	local character = getCharacterFromPart(hitPart)
	if character == nil then
		return nil
	end

	local target = Players:GetPlayerFromCharacter(character)
	if target == nil or target == localPlayer then
		return nil
	end

	if not isPlayerTinyfolk(target) then
		return nil
	end

	return target
end

local function onMouseClick(input: any, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if not isLocalPlayerGiant() then
		return
	end

	local target = resolveTinyfolkFromRaycast()
	if target == nil then
		selectTarget(nil)
		return
	end

	if selectedTarget == target then
		selectTarget(nil)
		return
	end

	selectTarget(target)
end

UserInputService.InputBegan:Connect(onMouseClick)

Players.PlayerRemoving:Connect(function(player: Player)
	if selectedTarget == player then
		clearSelection()
		refreshPanel()
	end
end)

localPlayer:GetAttributeChangedSignal("Role"):Connect(refreshPanel)
refreshPanel()
