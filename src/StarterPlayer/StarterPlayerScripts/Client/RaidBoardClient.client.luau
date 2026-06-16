--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RaidBoardConfig = require(Config:WaitForChild("RaidBoardConfig"))
local RaidBoardHubPresentation = require(GiantRealm:WaitForChild("RaidBoardHubPresentation"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local GUI_NAME = "RaidBoardGui"
local PANEL_NAME = "Panel"
local ROWS_NAME = "Rows"
local STATUS_NAME = "Status"

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(196, 118, 118),
	warning = Color3.fromRGB(224, 166, 68),
}

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.neutral
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.neutral
end

local function nextRequestId(): string
	return string.format("raid-board-%d-%d", localPlayer.UserId, math.floor(os.clock() * 1000))
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

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.BackgroundColor3 = ACCENT_BY_TONE.neutral
accent.BorderSizePixel = 0
accent.Size = UDim2.new(0, 4, 1, 0)
accent.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 10)
title.Size = UDim2.new(1, -180, 0, 24)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Raid Board"
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
status.Position = UDim2.fromOffset(14, 56)
status.Size = UDim2.new(1, -24, 0, 18)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(180, 188, 204)
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
local listRequestRemote = remotesFolder:WaitForChild(RaidBoardConfig.Remotes.ListRequest) :: RemoteEvent
local listResponseRemote = remotesFolder:WaitForChild(RaidBoardConfig.Remotes.ListResponse) :: RemoteEvent
local queueRequestRemote = remotesFolder:WaitForChild(RaidBoardConfig.Remotes.QueueRequest) :: RemoteEvent
local queueResponseRemote = remotesFolder:WaitForChild(RaidBoardConfig.Remotes.QueueResponse) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild(RaidBoardConfig.Remotes.Notify) :: RemoteEvent

local currentListings: { any } = {}
local lastListRequestAt = 0

local function hidePanel()
	panel.Visible = false
end

local function showPanel()
	if localPlayer:GetAttribute("Role") ~= "Tinyfolk" then
		status.Text = "Raid board is available to Tinyfolk only."
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
	if force ~= true and (at - lastListRequestAt) < RaidBoardConfig.RefreshCoalesceSeconds then
		return
	end
	lastListRequestAt = at
	listRequestRemote:FireServer({
		requestId = nextRequestId(),
		limit = RaidBoardConfig.DefaultListLimit,
	})
	status.Text = "Loading realm listings..."
end

local function togglePanelFromInteraction()
	if panel.Visible then
		hidePanel()
		return
	end

	showPanel()
	requestList(true)
end

local function queueForRealm(targetRealmId: string)
	queueRequestRemote:FireServer({
		requestId = nextRequestId(),
		targetRealmId = targetRealmId,
	})
	status.Text = string.format("Queueing for %s...", targetRealmId)
end

local function renderListingRow(row: any, layoutOrder: number)
	local rowFrame = Instance.new("Frame")
	rowFrame.Name = string.format("Row_%s", tostring(row.realmId))
	rowFrame.BackgroundColor3 = Color3.fromRGB(24, 28, 36)
	rowFrame.BorderSizePixel = 0
	rowFrame.Size = UDim2.new(1, -4, 0, 80)
	rowFrame.LayoutOrder = layoutOrder
	rowFrame.Parent = rowsFrame

	local rowTitle = Instance.new("TextLabel")
	rowTitle.BackgroundTransparency = 1
	rowTitle.Position = UDim2.fromOffset(10, 8)
	rowTitle.Size = UDim2.new(1, -120, 0, 20)
	rowTitle.Font = Enum.Font.GothamBold
	rowTitle.TextSize = 14
	rowTitle.TextColor3 = Color3.fromRGB(231, 234, 239)
	rowTitle.TextXAlignment = Enum.TextXAlignment.Left
	rowTitle.Text = row.realmDisplayName or row.realmId or "Unknown Realm"
	rowTitle.Parent = rowFrame

	local rowMeta = Instance.new("TextLabel")
	rowMeta.BackgroundTransparency = 1
	rowMeta.Position = UDim2.fromOffset(10, 30)
	rowMeta.Size = UDim2.new(1, -120, 0, 34)
	rowMeta.Font = Enum.Font.Gotham
	rowMeta.TextSize = 12
	rowMeta.TextColor3 = Color3.fromRGB(151, 159, 174)
	rowMeta.TextXAlignment = Enum.TextXAlignment.Left
	rowMeta.TextYAlignment = Enum.TextYAlignment.Top
	rowMeta.TextWrapped = true
	rowMeta.Text = string.format(
		"Owner: %s | Danger %.2f | %s | %s | %d/%d",
		row.ownerDisplayName or "Unknown",
		row.dangerRating or 0,
		row.rewardTierLabel or "Unknown",
		row.entryTypeLabel or "Unknown",
		row.playerCount or 0,
		row.capacity or 0
	)
	rowMeta.Parent = rowFrame

	local queueButton = Instance.new("TextButton")
	queueButton.Name = "Queue"
	queueButton.AnchorPoint = Vector2.new(1, 0.5)
	queueButton.Position = UDim2.new(1, -10, 0.5, 0)
	queueButton.Size = UDim2.fromOffset(88, 30)
	queueButton.BackgroundColor3 = Color3.fromRGB(118, 72, 72)
	queueButton.BorderSizePixel = 0
	queueButton.Font = Enum.Font.GothamBold
	queueButton.TextSize = 12
	queueButton.TextColor3 = Color3.fromRGB(231, 234, 239)
	queueButton.Text = "Queue"
	queueButton.Active = row.isQueueable == true
	queueButton.AutoButtonColor = row.isQueueable == true
	queueButton.BackgroundTransparency = if row.isQueueable == true then 0 else 0.45
	queueButton.Parent = rowFrame

	if row.isQueueable == true and type(row.realmId) == "string" then
		queueButton.MouseButton1Click:Connect(function()
			queueForRealm(row.realmId)
		end)
	end
end

local function renderListResponse(response: any)
	local model = RaidBoardHubPresentation.BuildPanelModel(response)
	panel.Visible = model.visible
	title.Text = model.title
	subtitle.Text = model.subtitle or ""
	accent.BackgroundColor3 = toneColor(model.tone)

	clearRows()
	currentListings = if type(model.listings) == "table" then model.listings else {}
	if #currentListings == 0 then
		status.Text = model.bodyText or "No listings available."
		return
	end

	status.Text = "Select a realm to queue."
	for index, row in ipairs(currentListings) do
		renderListingRow(row, index)
	end
end

closeButton.MouseButton1Click:Connect(hidePanel)
refreshButton.MouseButton1Click:Connect(function()
	requestList(true)
end)

UserInputService.InputBegan:Connect(function(input: any, gameProcessedEvent: boolean)
	if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
		hidePanel()
		return
	end
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == (Enum.KeyCode[RaidBoardConfig.DebugOpenKeyName] or Enum.KeyCode.B) then
		if panel.Visible then
			hidePanel()
		else
			showPanel()
			requestList(true)
		end
	end
end)

localPlayer:GetAttributeChangedSignal(RaidBoardConfig.OpenRequestAttribute):Connect(function()
	if localPlayer:GetAttribute(RaidBoardConfig.OpenRequestAttribute) ~= true then
		return
	end
	localPlayer:SetAttribute(RaidBoardConfig.OpenRequestAttribute, false)
	togglePanelFromInteraction()
end)

listResponseRemote.OnClientEvent:Connect(function(payload: any)
	renderListResponse(payload)
end)

queueResponseRemote.OnClientEvent:Connect(function(payload: any)
	status.Text = RaidBoardHubPresentation.BuildQueueStatusMessage(payload)
end)

notifyRemote.OnClientEvent:Connect(function(_payload: any)
	if panel.Visible then
		requestList(false)
	end
end)
