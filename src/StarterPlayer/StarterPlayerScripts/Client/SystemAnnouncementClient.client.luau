--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local GUI_NAME = "SystemAnnouncementGui"
local PANEL_NAME = "Panel"

local ATTR_ACTIVE = "SystemAnnouncementActive"
local ATTR_ID = "SystemAnnouncementId"
local ATTR_MESSAGE = "SystemAnnouncementMessage"
local ATTR_SEVERITY = "SystemAnnouncementSeverity"
local ATTR_STARTS_AT = "SystemAnnouncementStartsAt"
local ATTR_ENDS_AT = "SystemAnnouncementEndsAt"

local ACCENT_BY_SEVERITY = {
	info = Color3.fromRGB(113, 178, 236),
	warning = Color3.fromRGB(239, 181, 85),
	critical = Color3.fromRGB(234, 102, 102),
}

local function resolveAccent(severity: any): Color3
	if type(severity) == "string" then
		local mapped = ACCENT_BY_SEVERITY[severity]
		if mapped ~= nil then
			return mapped
		end
	end
	return Color3.fromRGB(151, 159, 174)
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function formatSeconds(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	local minutes = math.floor(clamped / 60)
	local remainderSeconds = clamped % 60
	return string.format("%02d:%02d", minutes, remainderSeconds)
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
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.fromScale(0.5, 0.03)
panel.Size = UDim2.fromOffset(560, 84)
panel.BackgroundColor3 = Color3.fromRGB(12, 14, 19)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Transparency = 0.2
stroke.Color = Color3.fromRGB(151, 159, 174)
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.fromOffset(536, 20)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(236, 239, 244)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "System Announcement"
title.Parent = panel

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "Message"
messageLabel.BackgroundTransparency = 1
messageLabel.Position = UDim2.fromOffset(12, 30)
messageLabel.Size = UDim2.fromOffset(536, 32)
messageLabel.Font = Enum.Font.Gotham
messageLabel.TextSize = 14
messageLabel.TextColor3 = Color3.fromRGB(223, 227, 234)
messageLabel.TextXAlignment = Enum.TextXAlignment.Left
messageLabel.TextWrapped = true
messageLabel.Text = ""
messageLabel.Parent = panel

local footer = Instance.new("TextLabel")
footer.Name = "Footer"
footer.BackgroundTransparency = 1
footer.Position = UDim2.fromOffset(12, 64)
footer.Size = UDim2.fromOffset(536, 14)
footer.Font = Enum.Font.Gotham
footer.TextSize = 11
footer.TextColor3 = Color3.fromRGB(181, 187, 198)
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = ""
footer.Parent = panel

local current = {
	active = false,
	announcementId = nil,
	message = nil,
	severity = nil,
	startsAt = nil,
	endsAt = nil,
}

local function refreshFromAttributes()
	current.active = localPlayer:GetAttribute(ATTR_ACTIVE) == true
	current.announcementId = localPlayer:GetAttribute(ATTR_ID)
	current.message = localPlayer:GetAttribute(ATTR_MESSAGE)
	current.severity = localPlayer:GetAttribute(ATTR_SEVERITY)
	current.startsAt = localPlayer:GetAttribute(ATTR_STARTS_AT)
	current.endsAt = localPlayer:GetAttribute(ATTR_ENDS_AT)
end

local function render()
	local nowAt = os.clock()
	local message = if type(current.message) == "string" then current.message else nil
	local startsAt = if isFiniteNumber(current.startsAt) then current.startsAt else nil
	local endsAt = if isFiniteNumber(current.endsAt) then current.endsAt else nil

	local activeByWindow = true
	if startsAt ~= nil and nowAt < startsAt then
		activeByWindow = false
	end
	if endsAt ~= nil and nowAt >= endsAt then
		activeByWindow = false
	end

	local visible = current.active == true and activeByWindow and type(message) == "string" and message ~= ""
	panel.Visible = visible
	if not visible then
		return
	end
	local messageText = if type(message) == "string" then message else ""

	local accent = resolveAccent(current.severity)
	stroke.Color = accent
	title.TextColor3 = accent
	messageLabel.Text = messageText

	if endsAt ~= nil and endsAt > nowAt then
		footer.Text = string.format("Expires in %s", formatSeconds(endsAt - nowAt))
	elseif type(current.announcementId) == "string" and current.announcementId ~= "" then
		footer.Text = string.format("Announcement %s", current.announcementId)
	else
		footer.Text = ""
	end
end

local function hookAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(function()
		refreshFromAttributes()
		render()
	end)
end

hookAttribute(ATTR_ACTIVE)
hookAttribute(ATTR_ID)
hookAttribute(ATTR_MESSAGE)
hookAttribute(ATTR_SEVERITY)
hookAttribute(ATTR_STARTS_AT)
hookAttribute(ATTR_ENDS_AT)

RunService.RenderStepped:Connect(function()
	render()
end)

refreshFromAttributes()
render()
