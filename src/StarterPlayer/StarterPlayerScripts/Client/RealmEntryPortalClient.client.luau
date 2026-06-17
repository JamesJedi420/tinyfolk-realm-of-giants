--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RealmEntryPortalConfig = require(Config:WaitForChild("RealmEntryPortalConfig"))
local RealmEntryPortalHubPresentation = require(GiantRealm:WaitForChild("RealmEntryPortalHubPresentation"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local GUI_NAME = "RealmEntryPortalGui"
local PANEL_NAME = "Panel"
local ROWS_NAME = "Rows"
local STATUS_NAME = "Status"

local function nextRequestId(): string
	return string.format("realm-portal-%d-%d", localPlayer.UserId, math.floor(os.clock() * 1000))
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
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(620, 460)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 10)
title.Size = UDim2.new(1, -180, 0, 24)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Realm Portal"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(14, 34)
subtitle.Size = UDim2.new(1, -180, 0, 18)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 13
subtitle.TextColor3 = Color3.fromRGB(151, 159, 174)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = ""
subtitle.Parent = panel

local refreshButton = Instance.new("TextButton")
refreshButton.Name = "Refresh"
refreshButton.AnchorPoint = Vector2.new(1, 0)
refreshButton.Position = UDim2.new(1, -46, 0, 8)
refreshButton.Size = UDim2.fromOffset(72, 28)
refreshButton.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
refreshButton.BorderSizePixel = 0
refreshButton.Font = Enum.Font.GothamBold
refreshButton.TextSize = 12
refreshButton.TextColor3 = Color3.fromRGB(231, 234, 239)
refreshButton.Text = "Refresh"
refreshButton.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 8)
closeButton.Size = UDim2.fromOffset(28, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.TextColor3 = Color3.fromRGB(231, 234, 239)
closeButton.Text = "×"
closeButton.Parent = panel

local status = Instance.new("TextLabel")
status.Name = STATUS_NAME
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(14, 58)
status.Size = UDim2.new(1, -24, 0, 18)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(151, 159, 174)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ""
status.Parent = panel

local rowsFrame = Instance.new("ScrollingFrame")
rowsFrame.Name = ROWS_NAME
rowsFrame.BackgroundTransparency = 1
rowsFrame.BorderSizePixel = 0
rowsFrame.Position = UDim2.fromOffset(14, 80)
rowsFrame.Size = UDim2.new(1, -24, 1, -92)
rowsFrame.CanvasSize = UDim2.fromOffset(0, 0)
rowsFrame.ScrollBarThickness = 6
rowsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
rowsFrame.Parent = panel

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Parent = rowsFrame

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local listRequestRemote = remotesFolder:WaitForChild(RealmEntryPortalConfig.Remotes.ListRequest) :: RemoteEvent
local listResponseRemote = remotesFolder:WaitForChild(RealmEntryPortalConfig.Remotes.ListResponse) :: RemoteEvent
local enterRequestRemote = remotesFolder:WaitForChild(RealmEntryPortalConfig.Remotes.EnterRequest) :: RemoteEvent
local enterResponseRemote = remotesFolder:WaitForChild(RealmEntryPortalConfig.Remotes.EnterResponse) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild(RealmEntryPortalConfig.Remotes.Notify) :: RemoteEvent

local lastListRequestAt = 0

local function hidePanel()
	panel.Visible = false
end

local function showPanel()
	if localPlayer:GetAttribute("Role") ~= "Tinyfolk" then
		status.Text = "Realm portal is available to Tinyfolk only."
		panel.Visible = true
		return
	end
	panel.Visible = true
end

local function clearRows()
	for _, child in ipairs(rowsFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
			child:Destroy()
		end
	end
end

local function requestList(force: boolean?)
	local at = os.clock()
	if force ~= true and (at - lastListRequestAt) < RealmEntryPortalConfig.RefreshCoalesceSeconds then
		return
	end
	lastListRequestAt = at
	listRequestRemote:FireServer({
		requestId = nextRequestId(),
		limit = RealmEntryPortalConfig.DefaultListLimit,
		entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
	})
	status.Text = "Loading realm entries..."
end

local function togglePanelFromInteraction()
	if panel.Visible then
		hidePanel()
		return
	end

	showPanel()
	requestList(true)
end

local function enterRealm(targetRealmId: string, entryMethod: string?)
	enterRequestRemote:FireServer({
		requestId = nextRequestId(),
		targetRealmId = targetRealmId,
		entryMethod = entryMethod or RealmEntryPortalConfig.EntryMethods.Portal,
	})
	status.Text = string.format("Entering %s...", targetRealmId)
end

local function renderListingRow(row: any, layoutOrder: number)
	local rowFrame = Instance.new("Frame")
	rowFrame.Name = string.format("Row_%s", tostring(row.realmId))
	rowFrame.BackgroundColor3 = Color3.fromRGB(24, 28, 36)
	rowFrame.BorderSizePixel = 0
	rowFrame.Size = UDim2.new(1, 0, 0, 64)
	rowFrame.LayoutOrder = layoutOrder
	rowFrame.Parent = rowsFrame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(10, 8)
	label.Size = UDim2.new(1, -110, 0, 20)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(231, 234, 239)
	label.Text = row.realmDisplayName or row.realmId
	label.Parent = rowFrame

	local meta = Instance.new("TextLabel")
	meta.BackgroundTransparency = 1
	meta.Position = UDim2.fromOffset(10, 30)
	meta.Size = UDim2.new(1, -110, 0, 18)
	meta.Font = Enum.Font.Gotham
	meta.TextSize = 11
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.TextColor3 = Color3.fromRGB(151, 159, 174)
	meta.Text = string.format("%s | %s", row.entryRoleLabel or "Guest", row.accessModeLabel or "Open")
	meta.Parent = rowFrame

	local enterButton = Instance.new("TextButton")
	enterButton.AnchorPoint = Vector2.new(1, 0.5)
	enterButton.Position = UDim2.new(1, -8, 0.5, 0)
	enterButton.Size = UDim2.fromOffset(88, 28)
	enterButton.BackgroundColor3 = Color3.fromRGB(52, 96, 140)
	enterButton.BorderSizePixel = 0
	enterButton.Font = Enum.Font.GothamBold
	enterButton.TextSize = 12
	enterButton.TextColor3 = Color3.fromRGB(231, 234, 239)
	enterButton.Text = if row.isEnterable == true then "Enter" else "Unavailable"
	enterButton.AutoButtonColor = row.isEnterable == true
	enterButton.Active = row.isEnterable == true
	enterButton.Parent = rowFrame

	if row.isEnterable == true then
		enterButton.MouseButton1Click:Connect(function()
			enterRealm(row.realmId, row.entryMethod)
		end)
	end
end

local function renderListings(listings: { any })
	clearRows()
	for index, row in ipairs(listings) do
		renderListingRow(row, index)
	end
end

listResponseRemote.OnClientEvent:Connect(function(response: any)
	local model = RealmEntryPortalHubPresentation.BuildPanelModel(response)
	title.Text = model.title
	subtitle.Text = model.subtitle
	status.Text = model.bodyText
	renderListings(model.listings)
end)

enterResponseRemote.OnClientEvent:Connect(function(response: any)
	status.Text = RealmEntryPortalHubPresentation.BuildEnterStatusMessage(response)
end)

notifyRemote.OnClientEvent:Connect(function(_payload: any)
	requestList(true)
end)

refreshButton.MouseButton1Click:Connect(function()
	requestList(true)
end)

closeButton.MouseButton1Click:Connect(function()
	hidePanel()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == (Enum.KeyCode[RealmEntryPortalConfig.DebugOpenKeyName] or Enum.KeyCode.P) then
		togglePanelFromInteraction()
	end
end)

localPlayer:GetAttributeChangedSignal(RealmEntryPortalConfig.OpenRequestAttribute):Connect(function()
	if localPlayer:GetAttribute(RealmEntryPortalConfig.OpenRequestAttribute) ~= true then
		return
	end
	localPlayer:SetAttribute(RealmEntryPortalConfig.OpenRequestAttribute, false)
	togglePanelFromInteraction()
end)
