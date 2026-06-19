--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local TinyfolkHaulLogisticsConfig = require(Config:WaitForChild("TinyfolkHaulLogisticsConfig"))
local TinyfolkJobSchedulingConfig = require(Config:WaitForChild("TinyfolkJobSchedulingConfig"))
local TinyfolkLaborJobHudConfig = require(Config:WaitForChild("TinyfolkLaborJobHudConfig"))
local TinyfolkLaborJobHudPresentation = require(GiantRealm:WaitForChild("TinyfolkLaborJobHudPresentation"))

local GUI_NAME = TinyfolkLaborJobHudConfig.GuiName
local PANEL_NAME = TinyfolkLaborJobHudConfig.PanelName
local BILLBOARD_NAME = TinyfolkLaborJobHudConfig.BillboardName

local ACCENT_BY_TONE = {
	[TinyfolkLaborJobHudConfig.Tones.None] = Color3.fromRGB(102, 113, 132),
	[TinyfolkLaborJobHudConfig.Tones.Neutral] = Color3.fromRGB(102, 113, 132),
	[TinyfolkLaborJobHudConfig.Tones.Active] = Color3.fromRGB(74, 160, 102),
	[TinyfolkLaborJobHudConfig.Tones.Complete] = Color3.fromRGB(130, 196, 224),
	[TinyfolkLaborJobHudConfig.Tones.Warning] = Color3.fromRGB(224, 166, 68),
}

local completionFlashUntil = 0
local lastScheduledJobKind: string? = nil
local activeBillboard: Instance? = nil
local activeBillboardAdornee: BasePart? = nil

local function debugLog(message: string)
	print(string.format("[TinyfolkLaborJobHudClient] %s", message))
end

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE[TinyfolkLaborJobHudConfig.Tones.Neutral]
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE[TinyfolkLaborJobHudConfig.Tones.Neutral]
end

local function getHumanoidRootPart(): BasePart?
	local character = localPlayer.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function findTargetPart(targetId: string?): BasePart?
	if type(targetId) ~= "string" or targetId == "" then
		return nil
	end

	local map = Workspace:FindFirstChild("Map")
	if map == nil then
		return nil
	end
	local stations = map:FindFirstChild("Stations")
	if stations == nil then
		return nil
	end

	for _, descendant in ipairs(stations:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == targetId then
			return descendant
		end
	end
	return nil
end

local function collectSnapshot(): any
	return {
		role = localPlayer:GetAttribute("Role"),
		scheduledJobKind = localPlayer:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute),
		scheduledMaterial = localPlayer:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute),
		scheduledSourceStationId = localPlayer:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute),
		scheduledLastReason = localPlayer:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobLastReasonAttribute),
		specialistRole = localPlayer:GetAttribute("SpecialistRole"),
		haulPhase = localPlayer:GetAttribute(TinyfolkHaulLogisticsConfig.PhaseAttribute),
		haulRouteSourceId = localPlayer:GetAttribute(TinyfolkHaulLogisticsConfig.RouteSourceIdAttribute),
		haulRouteDeliveryId = localPlayer:GetAttribute(TinyfolkHaulLogisticsConfig.RouteDeliveryIdAttribute),
		haulMaterial = localPlayer:GetAttribute(TinyfolkHaulLogisticsConfig.MaterialAttribute),
		haulLastReason = localPlayer:GetAttribute(TinyfolkHaulLogisticsConfig.LastReasonAttribute),
		haulInteractionActive = localPlayer:GetAttribute(StationConfig.HaulInteractionActiveAttribute) == true,
		completionFlashActive = os.clock() < completionFlashUntil,
	}
end

local function buildProximity(targetId: string?): any
	if type(targetId) ~= "string" or targetId == "" then
		return {
			targetId = targetId,
			inRange = false,
			targetFound = false,
		}
	end

	local targetPart = findTargetPart(targetId)
	if targetPart == nil then
		return {
			targetId = targetId,
			inRange = false,
			targetFound = false,
		}
	end

	local root = getHumanoidRootPart()
	if root == nil then
		return {
			targetId = targetId,
			inRange = false,
			targetFound = true,
		}
	end

	local distance = ((targetPart.Position :: any) - (root.Position :: any)).Magnitude
	return {
		targetId = targetId,
		inRange = distance <= TinyfolkLaborJobHudPresentation.GetActivationRangeStuds(),
		targetFound = true,
	}
end

local function clearBillboard()
	if activeBillboard ~= nil then
		(activeBillboard :: any):Destroy()
		activeBillboard = nil
	end
	activeBillboardAdornee = nil
end

local function applyBillboard(model: any)
	if model.showBillboard ~= true or type(model.billboardTargetId) ~= "string" then
		clearBillboard()
		return
	end

	local targetPart = findTargetPart(model.billboardTargetId)
	if targetPart == nil then
		clearBillboard()
		return
	end

	if activeBillboard ~= nil and activeBillboardAdornee == targetPart then
		local label = activeBillboard:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = if type(model.billboardLabel) == "string"
				then model.billboardLabel
				else model.billboardTargetId
			label.TextColor3 = if model.tone == TinyfolkLaborJobHudConfig.Tones.Active
				then Color3.fromRGB(130, 214, 132)
				else Color3.fromRGB(231, 234, 239)
		end
		return
	end

	clearBillboard()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = BILLBOARD_NAME
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(180, 48)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.Adornee = targetPart
	billboard.Parent = targetPart

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	background.BackgroundTransparency = 0.15
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = if model.tone == TinyfolkLaborJobHudConfig.Tones.Active
		then Color3.fromRGB(130, 214, 132)
		else Color3.fromRGB(231, 234, 239)
	label.Text = if type(model.billboardLabel) == "string" then model.billboardLabel else model.billboardTargetId
	label.Parent = background

	activeBillboard = billboard
	activeBillboardAdornee = targetPart
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
panel.Position = UDim2.fromScale(0.02, 0.34)
panel.Size = UDim2.fromOffset(360, 88)
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.BackgroundColor3 = ACCENT_BY_TONE[TinyfolkLaborJobHudConfig.Tones.Neutral]
accent.BorderSizePixel = 0
accent.Size = UDim2.new(0, 4, 1, 0)
accent.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.fromOffset(336, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(242, 244, 248)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Labor Job"
title.Parent = panel

local instruction = Instance.new("TextLabel")
instruction.Name = "Instruction"
instruction.BackgroundTransparency = 1
instruction.Position = UDim2.fromOffset(12, 34)
instruction.Size = UDim2.fromOffset(336, 44)
instruction.Font = Enum.Font.Gotham
instruction.TextSize = 13
instruction.TextColor3 = Color3.fromRGB(210, 214, 222)
instruction.TextXAlignment = Enum.TextXAlignment.Left
instruction.TextYAlignment = Enum.TextYAlignment.Top
instruction.TextWrapped = true
instruction.Text = ""
instruction.Parent = panel

local function maybeTriggerCompletionFlash(snapshot: any)
	local currentKind = snapshot.scheduledJobKind
	if type(currentKind) ~= "string" then
		currentKind = TinyfolkJobSchedulingConfig.JobKinds.None
	end

	if lastScheduledJobKind == nil then
		lastScheduledJobKind = currentKind
		return
	end

	local hadActiveJob = lastScheduledJobKind ~= TinyfolkJobSchedulingConfig.JobKinds.None
	local nowInactive = currentKind == TinyfolkJobSchedulingConfig.JobKinds.None
	if hadActiveJob and nowInactive then
		completionFlashUntil = os.clock() + TinyfolkLaborJobHudConfig.CompletionFlashSeconds
		debugLog(string.format("Completion flash until=%.2f", completionFlashUntil))
	end

	lastScheduledJobKind = currentKind
end

local function refreshHud()
	local snapshot = collectSnapshot()
	maybeTriggerCompletionFlash(snapshot)

	local targetId = TinyfolkLaborJobHudPresentation.ResolveBillboardTarget(snapshot)
	local proximity = buildProximity(targetId)
	local model = TinyfolkLaborJobHudPresentation.BuildHudModel(snapshot, proximity)

	panel.Visible = model.visible
	title.Text = model.title
	instruction.Text = model.instruction
	accent.BackgroundColor3 = toneColor(model.tone)
	applyBillboard(model)
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshHud)
end

hookAttribute("Role")
hookAttribute("SpecialistRole")
hookAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute)
hookAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute)
hookAttribute(TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute)
hookAttribute(TinyfolkJobSchedulingConfig.ScheduledJobLastReasonAttribute)
hookAttribute(TinyfolkHaulLogisticsConfig.PhaseAttribute)
hookAttribute(TinyfolkHaulLogisticsConfig.RouteSourceIdAttribute)
hookAttribute(TinyfolkHaulLogisticsConfig.RouteDeliveryIdAttribute)
hookAttribute(TinyfolkHaulLogisticsConfig.MaterialAttribute)
hookAttribute(TinyfolkHaulLogisticsConfig.LastReasonAttribute)
hookAttribute(TinyfolkHaulLogisticsConfig.LastMovedAmountAttribute)
hookAttribute(StationConfig.HaulInteractionActiveAttribute)

RunService.RenderStepped:Connect(function()
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
		if panel.Visible then
			panel.Visible = false
			clearBillboard()
		end
		return
	end

	local completionActive = os.clock() < completionFlashUntil
	local scheduledKind = localPlayer:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute)
	local hasScheduledJob = scheduledKind ~= nil and scheduledKind ~= TinyfolkJobSchedulingConfig.JobKinds.None

	if not hasScheduledJob and not completionActive then
		if panel.Visible then
			panel.Visible = false
			clearBillboard()
		end
		return
	end

	refreshHud()
end)

refreshHud()
debugLog("Labor job HUD bootstrap active")
