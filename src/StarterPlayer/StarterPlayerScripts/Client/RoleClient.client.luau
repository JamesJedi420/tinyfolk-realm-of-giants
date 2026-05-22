--!nocheck
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_CHANGE_REMOTE_NAME = "RoleChangeRequest"
local ROLE_DEBUG_REQUEST_REMOTE_NAME = "RoleDebugStateRequest"
local ROLE_DEBUG_RESPONSE_REMOTE_NAME = "RoleDebugStateResponse"
local ROLE_ATTRIBUTE = "Role"
local SELECTED_ROLE_ATTRIBUTE = "SelectedRole"
local ROLE_LOCKED_ATTRIBUTE = "RoleLocked"

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local PROMPT_GUI_NAME = "RoleSelectPromptGui"
local PROMPT_LABEL_NAME = "RoleSelectPromptLabel"

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local roleChangeRemote = remotesFolder:WaitForChild(ROLE_CHANGE_REMOTE_NAME) :: RemoteEvent
local roleDebugRequestRemote = remotesFolder:WaitForChild(ROLE_DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local roleDebugResponseRemote = remotesFolder:WaitForChild(ROLE_DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent

local function getOrCreatePromptGui(): ScreenGui
	local existing = playerGui:FindFirstChild(PROMPT_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = PROMPT_GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = PROMPT_LABEL_NAME
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.08)
	label.Size = UDim2.fromOffset(460, 72)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.6
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = "Select role to spawn: 1 = Tinyfolk, 2 = Giant"
	label.Parent = gui

	return gui
end

local rolePromptGui = getOrCreatePromptGui()

local function setPromptVisible(isVisible: boolean)
	rolePromptGui.Enabled = isVisible
end

local function isRoleLocked(): boolean
	return localPlayer:GetAttribute(ROLE_LOCKED_ATTRIBUTE) == true
end

local function shouldShowPrompt(): boolean
	if isRoleLocked() then
		return false
	end

	local selectedRole = localPlayer:GetAttribute(SELECTED_ROLE_ATTRIBUTE)
	if type(selectedRole) == "string" and selectedRole ~= "" then
		return false
	end

	return true
end

local function refreshPromptVisibility()
	setPromptVisible(shouldShowPrompt())
end

local function emitSelectionPrompt()
	if isRoleLocked() then
		refreshPromptVisibility()
		return
	end

	refreshPromptVisibility()
	print("[RoleClient] Select role before spawn: press 1 for Tinyfolk, 2 for Giant")
end

local function requestRole(roleName: string)
	if isRoleLocked() then
		refreshPromptVisibility()
		print("[RoleClient] Role is locked for this session; ignoring role request")
		return
	end

	roleChangeRemote:FireServer(roleName)
	print(string.format("[RoleClient] Requested pre-spawn role selection -> %s", roleName))
end

local function requestDebugState()
	roleDebugRequestRemote:FireServer(nil)
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.One then
		requestRole("Tinyfolk")
	elseif input.KeyCode == Enum.KeyCode.Two then
		requestRole("Giant")
	elseif input.KeyCode == Enum.KeyCode.Zero then
		requestDebugState()
	end
end)

roleDebugResponseRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		warn("[RoleClient] Received malformed role debug payload")
		return
	end

	print(
		string.format(
			"[RoleClient] Debug role=%s selectedRole=%s roleLocked=%s",
			tostring(payload.role),
			tostring(payload.selectedRole),
			tostring(payload.roleLocked)
		)
	)
end)

localPlayer:GetAttributeChangedSignal(ROLE_LOCKED_ATTRIBUTE):Connect(function()
	if isRoleLocked() then
		refreshPromptVisibility()
		print(
			string.format(
				"[RoleClient] Role locked: selectedRole=%s activeRole=%s",
				tostring(localPlayer:GetAttribute(SELECTED_ROLE_ATTRIBUTE)),
				tostring(localPlayer:GetAttribute(ROLE_ATTRIBUTE))
			)
		)
		return
	end

	emitSelectionPrompt()
end)

localPlayer:GetAttributeChangedSignal(SELECTED_ROLE_ATTRIBUTE):Connect(function()
	refreshPromptVisibility()
end)

localPlayer.CharacterAdded:Connect(function()
	refreshPromptVisibility()
end)

emitSelectionPrompt()
print("[RoleClient] Input hook active (1=Tinyfolk, 2=Giant, 0=Role debug)")
