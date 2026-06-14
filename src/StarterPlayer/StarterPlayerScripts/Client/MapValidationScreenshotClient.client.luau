--!nocheck
-- Studio-only validation camera snap for map screenshot checklist (Play mode).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local GUI_NAME = "MapValidationScreenshotGui"
local POLICY_GUI_EXEMPT = GUI_NAME
local validationPanel: Frame? = nil
local validationRestoreButton: TextButton? = nil

local function showValidationPanel(showPanel: boolean)
	if validationPanel ~= nil then
		validationPanel.Visible = showPanel
	end
	if validationRestoreButton ~= nil then
		validationRestoreButton.Visible = not showPanel
	end
end

local SHOTS = {
	{
		label = "Overhead (H)",
		keyCode = Enum.KeyCode.H,
		shotName = "Shot_Overhead_Map",
		defaultFov = 45,
	},
	{
		label = "Giant Plaza (G)",
		keyCode = Enum.KeyCode.G,
		shotName = "Shot_Giant_PlazaRoads",
		defaultFov = 60,
	},
	{
		label = "Tinyfolk Route (T)",
		keyCode = Enum.KeyCode.T,
		shotName = "Shot_Tinyfolk_RouteRead",
		defaultFov = 70,
	},
}

local SHOT_BY_KEYCODE: { [Enum.KeyCode]: string } = {}
for _, shot in SHOTS do
	SHOT_BY_KEYCODE[shot.keyCode] = shot.shotName
end

local MapScreenshotPresentationPolicy = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Map"):WaitForChild("MapScreenshotPresentationPolicy")
)

local localPlayer = Players.LocalPlayer
if localPlayer == nil then
	localPlayer = Players.PlayerAdded:Wait()
end

local function findValidationCameraRoot(): Instance?
	local map = Workspace:FindFirstChild("Map")
	if map == nil then
		return nil
	end
	local validationCameras = map:FindFirstChild("ValidationCameras")
	if validationCameras == nil then
		return nil
	end
	return validationCameras:FindFirstChild("Layout") or validationCameras
end

local function hideMapHelpersLocally()
	local map = Workspace:FindFirstChild("Map")
	if map == nil then
		return
	end
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and MapScreenshotPresentationPolicy.shouldHidePart(descendant, map) then
			descendant.LocalTransparencyModifier = 1
		end
	end
end

local function hidePresentationChrome()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if playerGui ~= nil then
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui.Name ~= POLICY_GUI_EXEMPT then
				gui.Enabled = false
			end
		end
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)

	local rolePrompt = playerGui and playerGui:FindFirstChild("RoleSelectPromptGui")
	if rolePrompt ~= nil and rolePrompt:IsA("ScreenGui") then
		rolePrompt.Enabled = false
	end

	local character = localPlayer.Character
	if character ~= nil then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			end
		end
	end
end

local function defaultFovForShot(shotName: string): number
	for _, shot in SHOTS do
		if shot.shotName == shotName then
			return shot.defaultFov
		end
	end
	return 70
end

local function snapValidationCamera(shotName: string)
	local layout = findValidationCameraRoot()
	if layout == nil then
		warn("[MapValidationScreenshotClient] ValidationCameras not found under Workspace.Map")
		return
	end

	local cam = layout:FindFirstChild(shotName)
	if cam == nil or not cam:IsA("BasePart") then
		warn(
			string.format(
				"[MapValidationScreenshotClient] Missing camera anchor %s under %s",
				shotName,
				layout:GetFullName()
			)
		)
		return
	end

	local look = Vector3.new(cam:GetAttribute("LookAtX"), cam:GetAttribute("LookAtY"), cam:GetAttribute("LookAtZ"))
	local suggestedFov = cam:GetAttribute("SuggestedFov")
	local fieldOfView = if type(suggestedFov) == "number" then suggestedFov else defaultFovForShot(shotName)

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = fieldOfView
	if shotName == "Shot_Overhead_Map" then
		camera.CFrame = CFrame.new(cam.Position) * CFrame.Angles(-math.pi / 2, 0, 0)
	else
		camera.CFrame = CFrame.lookAt(cam.Position, look)
	end

	hidePresentationChrome()
	hideMapHelpersLocally()
	showValidationPanel(false)

	print(string.format("[MapValidationScreenshotClient] Snapped to %s (FOV %.0f)", shotName, fieldOfView))
end

local function bindKeyboard()
	local function onKey(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local shotName = SHOT_BY_KEYCODE[input.KeyCode]
		if shotName ~= nil then
			snapValidationCamera(shotName)
			return
		end
		if input.KeyCode == Enum.KeyCode.V then
			showValidationPanel(true)
		end
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		onKey(input)
	end)

	local actionPriority = Enum.ContextActionPriority.High.Value + 1000
	for _, shot in SHOTS do
		ContextActionService:BindActionAtPriority(
			"MapValidationScreenshot_" .. shot.shotName,
			function(_actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
				if inputState ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				local shotName = SHOT_BY_KEYCODE[inputObject.KeyCode]
				if shotName == nil then
					return Enum.ContextActionResult.Pass
				end
				snapValidationCamera(shotName)
				return Enum.ContextActionResult.Sink
			end,
			false,
			actionPriority,
			shot.keyCode
		)
	end
end

local function createValidationGui()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 1000
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.fromScale(0.02, 0.98)
	panel.Size = UDim2.fromOffset(220, 140)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	validationPanel = panel

	local restoreButton = Instance.new("TextButton")
	restoreButton.Name = "RestorePanel"
	restoreButton.AnchorPoint = Vector2.new(0, 1)
	restoreButton.Position = UDim2.fromScale(0.02, 0.98)
	restoreButton.Size = UDim2.fromOffset(140, 24)
	restoreButton.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	restoreButton.BackgroundTransparency = 0.08
	restoreButton.BorderSizePixel = 0
	restoreButton.Font = Enum.Font.Gotham
	restoreButton.TextSize = 12
	restoreButton.TextColor3 = Color3.fromRGB(231, 234, 239)
	restoreButton.Text = "Show validation cameras"
	restoreButton.Visible = false
	restoreButton.Parent = screenGui
	validationRestoreButton = restoreButton
	restoreButton.MouseButton1Click:Connect(function()
		showValidationPanel(true)
	end)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -20, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(231, 234, 239)
	title.Text = "Validation cameras"
	title.Parent = panel

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(10, 24)
	hint.Size = UDim2.new(1, -20, 0, 16)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Color3.fromRGB(151, 159, 174)
	hint.Text = "Main panel hides; click restore or press V"
	hint.Parent = panel

	for index, shot in SHOTS do
		local button = Instance.new("TextButton")
		button.Name = shot.shotName
		button.Position = UDim2.fromOffset(10, 40 + (index - 1) * 30)
		button.Size = UDim2.new(1, -20, 0, 26)
		button.BackgroundColor3 = Color3.fromRGB(36, 42, 54)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.Gotham
		button.TextSize = 13
		button.TextColor3 = Color3.fromRGB(231, 234, 239)
		button.Text = shot.label
		button.Parent = panel
		button.MouseButton1Click:Connect(function()
			snapValidationCamera(shot.shotName)
		end)
	end

	return screenGui
end

bindKeyboard()
createValidationGui()

task.defer(function()
	local map = Workspace:WaitForChild("Map", 30)
	if map ~= nil then
		hideMapHelpersLocally()
	end
end)

print(
	"[MapValidationScreenshotClient] Ready — click bottom-left buttons, or press H/G/T (keys fail while Studio is paused)"
)
