--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTES_FOLDER_NAME = "Remotes"
local RESPONSE_REMOTE_NAME = "EmergencyReinforcementResponse"
local DEBUG_REQUEST_REMOTE_NAME = "EmergencyReinforcementDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "EmergencyReinforcementDebugStateResponse"

local SNAPSHOT_POLL_INTERVAL_SECONDS = 1

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EmergencyReinforcementConfig = require(Config:WaitForChild("EmergencyReinforcementConfig"))

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local responseRemote = remotesFolder:WaitForChild(RESPONSE_REMOTE_NAME) :: RemoteEvent
local debugRequestRemote = remotesFolder:WaitForChild(DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local debugResponseRemote = remotesFolder:WaitForChild(DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent

local function debugLog(message: string)
	print(string.format("[EmergencyReinforcementClient] %s", message))
end

local function reasonLabel(reason: string?): string
	if reason == nil then
		return ""
	end

	local byReason = {
		request_cooldown = "Request cooling down",
		match_not_ready = "Match warmup not complete",
		invalid_objective = "Call center objective invalid",
		objective_out_of_range = "Move to call center",
		reinforcement_spawn_missing = "Reinforcement spawn unavailable",
		reinforcement_spawn_protected = "Reinforcement spawn protected",
		reinforcement_candidate_missing = "No eligible reinforcement candidate",
		reinforcement_candidate_invalid = "Candidate data invalid",
		reinforcement_already_used = "Reinforcement already used",
		token_snapshot_failed = "Objective token check failed",
		token_lifecycle_inactive = "Objective token inactive",
		token_revoked = "Objective token revoked",
		token_unavailable = "Objective token unavailable",
		token_not_ready = "Objective token not ready",
		token_expired = "Objective token expired",
		token_not_scheduled = "Objective token outside schedule",
		token_consume_failed = "Objective token consume failed",
		reinforcement_spawn_failed = "Reinforcement spawn failed",
		accepted = "Reinforcement accepted",
	}

	local mapped = byReason[reason]
	if type(mapped) == "string" then
		return mapped
	end

	return reason
end

local function formatSeconds(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	local minutes = math.floor(clamped / 60)
	local remainderSeconds = clamped % 60
	return string.format("%02d:%02d", minutes, remainderSeconds)
end

local existingGui = playerGui:FindFirstChild("EmergencyReinforcementHud")
if existingGui ~= nil and existingGui:IsA("ScreenGui") then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EmergencyReinforcementHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Container"
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.fromScale(0.985, 0.03)
frame.Size = UDim2.fromOffset(300, 84)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Parent = screenGui

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.fromOffset(10, 8)
titleLabel.Size = UDim2.fromOffset(280, 20)
titleLabel.Font = Enum.Font.GothamSemibold
titleLabel.TextSize = 14
titleLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Radio Reinforcement"
titleLabel.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.fromOffset(10, 30)
statusLabel.Size = UDim2.fromOffset(280, 20)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 14
statusLabel.TextColor3 = Color3.fromRGB(130, 214, 132)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "Status: Loading..."
statusLabel.Parent = frame

local detailLabel = Instance.new("TextLabel")
detailLabel.Name = "Detail"
detailLabel.BackgroundTransparency = 1
detailLabel.Position = UDim2.fromOffset(10, 52)
detailLabel.Size = UDim2.fromOffset(280, 24)
detailLabel.Font = Enum.Font.Gotham
detailLabel.TextSize = 12
detailLabel.TextColor3 = Color3.fromRGB(210, 210, 218)
detailLabel.TextXAlignment = Enum.TextXAlignment.Left
detailLabel.TextWrapped = true
detailLabel.Text = ""
detailLabel.Parent = frame

local latestSnapshot: any = nil
local latestReason: string? = nil

local function applySnapshot(snapshot: any, reasonOverride: string?)
	if type(snapshot) ~= "table" then
		return
	end
	latestSnapshot = snapshot
	if type(reasonOverride) == "string" then
		latestReason = reasonOverride
	elseif type(snapshot.lastReason) == "string" then
		latestReason = snapshot.lastReason
	end
end

local function updateHud()
	local roleValue = localPlayer:GetAttribute("Role")
	frame.Visible = roleValue == "Tinyfolk"
	if not frame.Visible then
		return
	end

	if type(latestSnapshot) ~= "table" then
		statusLabel.Text = "Status: Loading..."
		statusLabel.TextColor3 = Color3.fromRGB(240, 200, 116)
		detailLabel.Text = "Awaiting reinforcement snapshot"
		return
	end

	local snapshot: any = latestSnapshot
	local nowAt = os.clock()
	local isAvailable = snapshot.available == true
	local isUsed = snapshot.used == true
	local cooldownEndsAt = if type(snapshot.cooldownEndsAt) == "number" then snapshot.cooldownEndsAt else nil
	local activeCount = if type(snapshot.activeTinyfolkCount) == "number" then snapshot.activeTinyfolkCount else nil
	local threshold = if type(snapshot.activeTinyfolkThreshold) == "number"
		then snapshot.activeTinyfolkThreshold
		else nil

	if isUsed then
		statusLabel.Text = "Status: Used"
		statusLabel.TextColor3 = Color3.fromRGB(168, 168, 175)
	elseif isAvailable then
		statusLabel.Text = "Status: Ready"
		statusLabel.TextColor3 = Color3.fromRGB(130, 214, 132)
		-- Avoid stale rejection messaging when a fresh snapshot reports ready.
		latestReason = nil
	elseif cooldownEndsAt ~= nil and cooldownEndsAt > nowAt then
		statusLabel.Text = string.format("Status: Cooldown %s", formatSeconds(cooldownEndsAt - nowAt))
		statusLabel.TextColor3 = Color3.fromRGB(240, 200, 116)
	else
		statusLabel.Text = "Status: Unavailable"
		statusLabel.TextColor3 = Color3.fromRGB(232, 126, 126)
	end

	local detailParts: { string } = {}
	local readableReason = reasonLabel(latestReason)
	if string.len(readableReason) > 0 then
		table.insert(detailParts, readableReason)
	end

	if type(snapshot.readinessReason) == "string" and snapshot.readinessReason ~= "ready" then
		table.insert(detailParts, string.format("Readiness: %s", reasonLabel(snapshot.readinessReason)))
	end

	if activeCount ~= nil and threshold ~= nil then
		table.insert(detailParts, string.format("Active Tinyfolk %d/%d", activeCount, threshold))
	end

	if not isUsed and cooldownEndsAt ~= nil and cooldownEndsAt > nowAt then
		table.insert(detailParts, string.format("Call cooldown %s", formatSeconds(cooldownEndsAt - nowAt)))
	elseif not isUsed and isAvailable == false then
		local matchStartedAt = if type(snapshot.matchStartedAt) == "number" then snapshot.matchStartedAt else nil
		if matchStartedAt ~= nil then
			local warmupEndsAt = matchStartedAt + EmergencyReinforcementConfig.MinMatchElapsedSeconds
			if warmupEndsAt > nowAt then
				table.insert(detailParts, string.format("Match warmup %s", formatSeconds(warmupEndsAt - nowAt)))
			end
		end
	end

	detailLabel.Text = table.concat(detailParts, " | ")
end

responseRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local snapshot = payload.snapshot
	local reasonOverride = if type(payload.reason) == "string" then payload.reason else nil
	applySnapshot(snapshot, reasonOverride)
end)

debugResponseRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	applySnapshot(payload, nil)
end)

RunService.RenderStepped:Connect(function()
	updateHud()
end)

task.spawn(function()
	while true do
		if localPlayer:GetAttribute("Role") == "Tinyfolk" then
			debugRequestRemote:FireServer(nil)
		end
		task.wait(SNAPSHOT_POLL_INTERVAL_SECONDS)
	end
end)

debugLog("HUD bootstrap active")
