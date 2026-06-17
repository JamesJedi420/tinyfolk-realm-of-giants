--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local TinyfolkPartyConfig = require(Config:WaitForChild("TinyfolkPartyConfig"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local GUI_NAME = "TinyfolkPartyGui"
local PANEL_NAME = "Panel"
local MEMBERS_NAME = "Members"
local STATUS_NAME = "Status"

local currentSnapshot: any = nil

local function nextRequestId(): string
	return string.format("tinyfolk-party-%d-%d", localPlayer.UserId, math.floor(os.clock() * 1000))
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
panel.Position = UDim2.fromOffset(16, 120)
panel.Size = UDim2.fromOffset(320, 280)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.new(1, -24, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Tinyfolk Party"
title.Parent = panel

local status = Instance.new("TextLabel")
status.Name = STATUS_NAME
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(12, 34)
status.Size = UDim2.new(1, -24, 0, 36)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(151, 159, 174)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "Press P to open. Create a party to queue together."
status.Parent = panel

local members = Instance.new("TextLabel")
members.Name = MEMBERS_NAME
members.BackgroundTransparency = 1
members.Position = UDim2.fromOffset(12, 74)
members.Size = UDim2.new(1, -24, 1, -130)
members.Font = Enum.Font.Code
members.TextSize = 12
members.TextColor3 = Color3.fromRGB(196, 204, 214)
members.TextXAlignment = Enum.TextXAlignment.Left
members.TextYAlignment = Enum.TextYAlignment.Top
members.TextWrapped = true
members.Text = ""
members.Parent = panel

local buttonRow = Instance.new("Frame")
buttonRow.Name = "Buttons"
buttonRow.BackgroundTransparency = 1
buttonRow.AnchorPoint = Vector2.new(0, 1)
buttonRow.Position = UDim2.new(0, 12, 1, -12)
buttonRow.Size = UDim2.new(1, -24, 0, 28)
buttonRow.Parent = panel

local function makeButton(name: string, text: string, xOffset: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(xOffset, 0)
	button.Size = UDim2.fromOffset(92, 28)
	button.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.TextColor3 = Color3.fromRGB(231, 234, 239)
	button.Text = text
	button.Parent = buttonRow
	return button
end

local createButton = makeButton("Create", "Create", 0)
local readyButton = makeButton("Ready", "Ready", 100)
local leaveButton = makeButton("Leave", "Leave", 200)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local actionRequestRemote = remotesFolder:WaitForChild(TinyfolkPartyConfig.Remotes.ActionRequest) :: RemoteEvent
local actionResponseRemote = remotesFolder:WaitForChild(TinyfolkPartyConfig.Remotes.ActionResponse) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild(TinyfolkPartyConfig.Remotes.Notify) :: RemoteEvent

local function formatMemberLine(userId: number, snapshot: any): string
	local leaderMark = if snapshot.leaderUserId == userId then " [leader]" else ""
	local readyMark = ""
	if type(snapshot.readyUserIds) == "table" then
		for _, readyUserId in ipairs(snapshot.readyUserIds) do
			if readyUserId == userId then
				readyMark = " [ready]"
				break
			end
		end
	end
	return string.format("- %d%s%s", userId, leaderMark, readyMark)
end

local function renderSnapshot(snapshot: any)
	currentSnapshot = snapshot
	if type(snapshot) ~= "table" then
		status.Text = "No party data."
		members.Text = ""
		return
	end

	if snapshot.accepted ~= true and type(snapshot.reason) == "string" then
		status.Text = "Last action: " .. snapshot.reason
	end

	if type(snapshot.partyId) ~= "string" then
		members.Text = "No active party."
		readyButton.Text = "Ready"
		return
	end

	status.Text = string.format("Party %s", snapshot.partyId)
	local lines: { string } = {}
	if type(snapshot.memberUserIds) == "table" then
		for _, userId in ipairs(snapshot.memberUserIds) do
			table.insert(lines, formatMemberLine(userId, snapshot))
		end
	end
	if type(snapshot.pendingInviteUserIds) == "table" and #snapshot.pendingInviteUserIds > 0 then
		table.insert(lines, "Pending invites:")
		for _, userId in ipairs(snapshot.pendingInviteUserIds) do
			table.insert(lines, string.format("  invite -> %d", userId))
		end
	end
	members.Text = table.concat(lines, "\n")

	local isReady = false
	if type(snapshot.readyUserIds) == "table" then
		for _, readyUserId in ipairs(snapshot.readyUserIds) do
			if readyUserId == localPlayer.UserId then
				isReady = true
				break
			end
		end
	end
	readyButton.Text = if isReady then "Unready" else "Ready"
end

local function sendAction(action: string, extra: any?)
	local payload: any = {
		requestId = nextRequestId(),
		action = action,
	}
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	actionRequestRemote:FireServer(payload)
end

local function togglePanel()
	panel.Visible = not panel.Visible
end

createButton.MouseButton1Click:Connect(function()
	sendAction(TinyfolkPartyConfig.Actions.Create)
end)

readyButton.MouseButton1Click:Connect(function()
	local ready = true
	if type(currentSnapshot) == "table" and type(currentSnapshot.readyUserIds) == "table" then
		for _, readyUserId in ipairs(currentSnapshot.readyUserIds) do
			if readyUserId == localPlayer.UserId then
				ready = false
				break
			end
		end
	end
	sendAction(TinyfolkPartyConfig.Actions.SetReady, {
		ready = ready,
	})
end)

leaveButton.MouseButton1Click:Connect(function()
	sendAction(TinyfolkPartyConfig.Actions.Leave)
end)

actionResponseRemote.OnClientEvent:Connect(function(snapshot: any)
	renderSnapshot(snapshot)
end)

notifyRemote.OnClientEvent:Connect(function(snapshot: any)
	renderSnapshot(snapshot)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if input.KeyCode.Name == TinyfolkPartyConfig.DebugOpenKeyName then
		togglePanel()
	end
end)

localPlayer:GetAttributeChangedSignal(TinyfolkPartyConfig.OpenRequestAttribute):Connect(function()
	if localPlayer:GetAttribute(TinyfolkPartyConfig.OpenRequestAttribute) ~= true then
		return
	end
	localPlayer:SetAttribute(TinyfolkPartyConfig.OpenRequestAttribute, false)
	if not panel.Visible then
		togglePanel()
	end
end)

renderSnapshot(nil)
