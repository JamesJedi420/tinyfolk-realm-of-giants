--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local PartyMatchmakingQueueConfig = require(Config:WaitForChild("PartyMatchmakingQueueConfig"))
local PartyMatchmakingHubPresentation = require(GiantRealm:WaitForChild("PartyMatchmakingHubPresentation"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local GUI_NAME = "PartyMatchmakingGui"
local PANEL_NAME = "Panel"
local STATUS_NAME = "Status"

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(72, 118, 168),
	warning = Color3.fromRGB(224, 166, 68),
	success = Color3.fromRGB(72, 148, 108),
}

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.neutral
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.neutral
end

local function nextRequestId(): string
	return string.format("party-matchmaking-%d-%d", localPlayer.UserId, math.floor(os.clock() * 1000))
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
panel.Size = UDim2.fromOffset(420, 320)
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
title.Size = UDim2.new(1, -52, 0, 24)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(231, 234, 239)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Party Matchmaking"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(14, 34)
subtitle.Size = UDim2.new(1, -24, 0, 18)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 13
subtitle.TextColor3 = Color3.fromRGB(151, 159, 174)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "Queue your party for a shared activity"
subtitle.Parent = panel

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
status.Size = UDim2.new(1, -24, 0, 36)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(180, 188, 204)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "Select an activity and join the queue."
status.Parent = panel

local activityRow = Instance.new("Frame")
activityRow.Name = "Activities"
activityRow.BackgroundTransparency = 1
activityRow.Position = UDim2.fromOffset(14, 98)
activityRow.Size = UDim2.new(1, -24, 0, 120)
activityRow.Parent = panel

local activityLayout = Instance.new("UIGridLayout")
activityLayout.CellPadding = UDim2.fromOffset(8, 8)
activityLayout.CellSize = UDim2.fromOffset(188, 28)
activityLayout.Parent = activityRow

local queueButton = Instance.new("TextButton")
queueButton.Name = "JoinQueue"
queueButton.AnchorPoint = Vector2.new(0, 1)
queueButton.Position = UDim2.new(0, 14, 1, -12)
queueButton.Size = UDim2.fromOffset(140, 32)
queueButton.BackgroundColor3 = Color3.fromRGB(72, 118, 168)
queueButton.BorderSizePixel = 0
queueButton.Font = Enum.Font.GothamBold
queueButton.TextSize = 13
queueButton.TextColor3 = Color3.fromRGB(231, 234, 239)
queueButton.Text = "Join Queue"
queueButton.Parent = panel

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local enqueueRequestRemote =
	remotesFolder:WaitForChild(PartyMatchmakingQueueConfig.Remotes.EnqueueRequest) :: RemoteEvent
local enqueueResponseRemote =
	remotesFolder:WaitForChild(PartyMatchmakingQueueConfig.Remotes.EnqueueResponse) :: RemoteEvent
local pollRequestRemote = remotesFolder:WaitForChild(PartyMatchmakingQueueConfig.Remotes.PollRequest) :: RemoteEvent
local pollResponseRemote = remotesFolder:WaitForChild(PartyMatchmakingQueueConfig.Remotes.PollResponse) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild(PartyMatchmakingQueueConfig.Remotes.Notify) :: RemoteEvent

local selectedActivity = PartyMatchmakingQueueConfig.Activities.Raid
local activeQueueSnapshot: any = nil
local pollToken = 0
local lastPollRequestAt = 0
local activityButtons: { [string]: TextButton } = {}

local function setAccentTone(tone: string?)
	accent.BackgroundColor3 = toneColor(tone)
end

local function hidePanel()
	panel.Visible = false
end

local function showPanel()
	if localPlayer:GetAttribute("Role") ~= "Tinyfolk" then
		status.Text = "Party matchmaking is available to Tinyfolk only."
		setAccentTone("warning")
		panel.Visible = true
		return
	end
	panel.Visible = true
	setAccentTone("neutral")
end

local function refreshActivityButtons()
	for activity, button in pairs(activityButtons) do
		local selected = activity == selectedActivity
		button.BackgroundColor3 = if selected then Color3.fromRGB(72, 118, 168) else Color3.fromRGB(34, 38, 48)
	end
end

local function renderQueueSnapshot(snapshot: any)
	activeQueueSnapshot = snapshot
	if type(snapshot) ~= "table" then
		queueButton.Text = "Join Queue"
		queueButton.Active = true
		queueButton.AutoButtonColor = true
		queueButton.BackgroundTransparency = 0
		setAccentTone("neutral")
		return
	end

	status.Text = PartyMatchmakingHubPresentation.BuildQueueSnapshotStatus(snapshot)
	if snapshot.status == "pending" then
		queueButton.Text = "Searching..."
		queueButton.Active = false
		queueButton.AutoButtonColor = false
		queueButton.BackgroundTransparency = 0.35
		setAccentTone("neutral")
		return
	end

	queueButton.Text = "Join Queue"
	queueButton.Active = true
	queueButton.AutoButtonColor = true
	queueButton.BackgroundTransparency = 0
	if snapshot.status == "matched" then
		setAccentTone("success")
	else
		setAccentTone("warning")
	end
end

local function stopPolling()
	pollToken += 1
end

local function requestPoll(force: boolean?)
	if type(activeQueueSnapshot) ~= "table" then
		return
	end
	if not PartyMatchmakingHubPresentation.ShouldContinuePolling(activeQueueSnapshot) then
		return
	end

	local at = os.clock()
	if force ~= true and (at - lastPollRequestAt) < PartyMatchmakingQueueConfig.PollCoalesceSeconds then
		return
	end
	lastPollRequestAt = at

	pollRequestRemote:FireServer({
		requestId = nextRequestId(),
		operationId = activeQueueSnapshot.operationId,
		partyId = activeQueueSnapshot.partyId,
	})
end

local function startPolling()
	stopPolling()
	local token = pollToken
	task.spawn(function()
		while token == pollToken do
			if type(activeQueueSnapshot) ~= "table" then
				return
			end
			if not PartyMatchmakingHubPresentation.ShouldContinuePolling(activeQueueSnapshot) then
				return
			end
			requestPoll(true)
			task.wait(PartyMatchmakingQueueConfig.PollCoalesceSeconds + 0.15)
		end
	end)
end

local function requestEnqueue()
	if localPlayer:GetAttribute("Role") ~= "Tinyfolk" then
		status.Text = "Party matchmaking is available to Tinyfolk only."
		setAccentTone("warning")
		return
	end
	if type(activeQueueSnapshot) == "table" and activeQueueSnapshot.status == "pending" then
		return
	end

	enqueueRequestRemote:FireServer({
		requestId = nextRequestId(),
		desiredActivity = selectedActivity,
		skillBand = 0,
		toolTier = 0,
		timeoutSeconds = PartyMatchmakingQueueConfig.DefaultTimeoutSeconds,
	})
	status.Text =
		string.format("Joining %s queue...", PartyMatchmakingHubPresentation.GetActivityLabel(selectedActivity))
	setAccentTone("neutral")
end

for index, activity in ipairs(PartyMatchmakingHubPresentation.ListActivities()) do
	local button = Instance.new("TextButton")
	button.Name = "Activity_" .. activity
	button.LayoutOrder = index
	button.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = Color3.fromRGB(231, 234, 239)
	button.Text = PartyMatchmakingHubPresentation.GetActivityLabel(activity)
	button.Parent = activityRow
	activityButtons[activity] = button

	button.MouseButton1Click:Connect(function()
		if type(activeQueueSnapshot) == "table" and activeQueueSnapshot.status == "pending" then
			return
		end
		selectedActivity = activity
		refreshActivityButtons()
	end)
end
refreshActivityButtons()

closeButton.MouseButton1Click:Connect(hidePanel)
queueButton.MouseButton1Click:Connect(requestEnqueue)

UserInputService.InputBegan:Connect(function(input: any, gameProcessedEvent: boolean)
	if input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
		hidePanel()
		return
	end
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == (Enum.KeyCode[PartyMatchmakingQueueConfig.DebugOpenKeyName] or Enum.KeyCode.M) then
		if panel.Visible then
			hidePanel()
		else
			showPanel()
		end
	end
end)

localPlayer:GetAttributeChangedSignal(PartyMatchmakingQueueConfig.OpenRequestAttribute):Connect(function()
	if localPlayer:GetAttribute(PartyMatchmakingQueueConfig.OpenRequestAttribute) ~= true then
		return
	end
	localPlayer:SetAttribute(PartyMatchmakingQueueConfig.OpenRequestAttribute, false)
	showPanel()
end)

enqueueResponseRemote.OnClientEvent:Connect(function(payload: any)
	status.Text = PartyMatchmakingHubPresentation.BuildEnqueueStatusMessage(payload)
	if type(payload) == "table" and payload.accepted == true and type(payload.queueSnapshot) == "table" then
		renderQueueSnapshot(payload.queueSnapshot)
		if PartyMatchmakingHubPresentation.ShouldContinuePolling(payload.queueSnapshot) then
			startPolling()
		else
			stopPolling()
		end
		return
	end
	setAccentTone("warning")
	stopPolling()
end)

pollResponseRemote.OnClientEvent:Connect(function(payload: any)
	status.Text = PartyMatchmakingHubPresentation.BuildPollStatusMessage(payload)
	if type(payload) ~= "table" or payload.accepted ~= true or type(payload.queueSnapshot) ~= "table" then
		setAccentTone("warning")
		return
	end

	renderQueueSnapshot(payload.queueSnapshot)
	if PartyMatchmakingHubPresentation.ShouldContinuePolling(payload.queueSnapshot) then
		return
	end
	stopPolling()
end)

notifyRemote.OnClientEvent:Connect(function(payload: any)
	status.Text = PartyMatchmakingHubPresentation.BuildNotifyStatusMessage(payload)
	if type(payload) == "table" and type(payload.queueSnapshot) == "table" then
		renderQueueSnapshot(payload.queueSnapshot)
		if not PartyMatchmakingHubPresentation.ShouldContinuePolling(payload.queueSnapshot) then
			stopPolling()
		end
	end
end)

renderQueueSnapshot(nil)
