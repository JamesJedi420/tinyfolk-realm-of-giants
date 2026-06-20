--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: any

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local GiantHudStackConfig = require(Config:WaitForChild("GiantHudStackConfig"))
local GiantEffectHudConfig = require(Config:WaitForChild("GiantEffectHudConfig"))
local GiantRealmTreasuryConfig = require(Config:WaitForChild("GiantRealmTreasuryConfig"))
local PenRationingConfig = require(Config:WaitForChild("PenRationingConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SocialEconomyConfig = require(Config:WaitForChild("SocialEconomyConfig"))

local GiantEffectHudPresentation = require(GiantRealm:WaitForChild("GiantEffectHudPresentation"))
local GiantRealmTreasuryPresentation = require(GiantRealm:WaitForChild("GiantRealmTreasuryPresentation"))
local PenRationingHudPresentation = require(GiantRealm:WaitForChild("PenRationingHudPresentation"))
local PenRationingState = require(GiantRealm:WaitForChild("PenRationingState"))
local SocialEconomyPresentation = require(GiantRealm:WaitForChild("SocialEconomyPresentation"))

local ACCENT_BY_TONE = {
	neutral = Color3.fromRGB(151, 159, 174),
	warning = Color3.fromRGB(224, 166, 68),
	warm = Color3.fromRGB(224, 166, 68),
	cold = Color3.fromRGB(96, 146, 214),
}

local PANEL_BACKGROUND = Color3.fromRGB(18, 20, 26)
local TITLE_COLOR = Color3.fromRGB(231, 234, 239)
local SUMMARY_COLOR = Color3.fromRGB(180, 188, 204)

local penPart: BasePart? = nil

local function toneColor(tone: string?): Color3
	if type(tone) ~= "string" then
		return ACCENT_BY_TONE.neutral
	end
	return ACCENT_BY_TONE[tone] or ACCENT_BY_TONE.neutral
end

local function firstSummaryLine(summary: string): string
	local line = string.match(summary, "([^\n]+)")
	if type(line) == "string" and line ~= "" then
		return line
	end
	return summary
end

local function findPenPart(penId: string): BasePart?
	local map = Workspace:FindFirstChild("Map")
	if map == nil then
		return nil
	end
	local stations = map:FindFirstChild("Stations")
	if stations == nil then
		return nil
	end

	for _, descendant in ipairs(stations:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == penId then
			return descendant
		end
	end
	return nil
end

local function destroyLegacyGuis()
	for _, guiName in ipairs(GiantHudStackConfig.LegacyGuiNames) do
		local existing = playerGui:FindFirstChild(guiName)
		if existing ~= nil and existing:IsA("ScreenGui") then
			existing:Destroy()
		end
	end
end

local function hasSocialEconomyProjection(): boolean
	return type(localPlayer:GetAttribute(SocialEconomyConfig.StateAttributes.Favor)) == "number"
end

local function collectTreasuryAttributes(): any
	local attributes = GiantRealmTreasuryConfig.Attributes
	return {
		LedgerEssence = localPlayer:GetAttribute(attributes.LedgerEssence),
		LedgerWood = localPlayer:GetAttribute(attributes.LedgerWood),
		LedgerStone = localPlayer:GetAttribute(attributes.LedgerStone),
		SessionEssence = localPlayer:GetAttribute(attributes.SessionEssence),
		SessionWood = localPlayer:GetAttribute(attributes.SessionWood),
		SessionStone = localPlayer:GetAttribute(attributes.SessionStone),
		SessionMetal = localPlayer:GetAttribute(attributes.SessionMetal),
		Summary = localPlayer:GetAttribute(attributes.Summary),
		UpdatedAt = localPlayer:GetAttribute(attributes.UpdatedAt),
	}
end

local function buildTreasuryPresentationInput(attributes: any)
	local ledgerInput = {
		essence = attributes.LedgerEssence,
		wood = attributes.LedgerWood,
		stone = attributes.LedgerStone,
	}
	local sessionInput = {
		essenceStored = attributes.SessionEssence,
		woodStored = attributes.SessionWood,
		stoneStored = attributes.SessionStone,
		metalStored = attributes.SessionMetal,
	}
	return ledgerInput, sessionInput
end

local function collectPenRationingSnapshot(): any
	local attrs = PenRationingConfig.StateAttributes
	local snapshot: any = {
		role = localPlayer:GetAttribute("Role"),
		captureActive = localPlayer:GetAttribute("CaptureActive") == true,
		custodianMorale = localPlayer:GetAttribute(attrs.CustodianMorale),
		captiveShortfallStreak = localPlayer:GetAttribute(attrs.CaptiveShortfallStreak),
		captiveStarving = localPlayer:GetAttribute(attrs.CaptiveStarving) == true,
		moraleDefault = PenRationingConfig.MoraleDefault,
		moraleCaptureSureThreshold = PenRationingConfig.MoraleCaptureSureThreshold,
		captureReadinessPercent = PenRationingState.ComputeCaptureReadinessPercent(
			localPlayer:GetAttribute(attrs.CustodianMorale) or PenRationingConfig.MoraleDefault,
			PenRationingConfig.MoraleCaptureSureThreshold
		),
		controlIntimidationBonus = localPlayer:GetAttribute(
			SocialEconomyConfig.StateAttributes.ControlIntimidationBonus
		),
	}

	if penPart ~= nil then
		snapshot.lastFoodShortfall = penPart:GetAttribute(attrs.LastFoodShortfall) == true
		snapshot.consecutiveShortfallTicks = penPart:GetAttribute(attrs.ConsecutiveShortfallTicks)
		snapshot.activeCaptiveCount = penPart:GetAttribute(attrs.ActiveCaptiveCount)
		snapshot.foodCostMultiplier = penPart:GetAttribute(attrs.FoodCostMultiplier)
	end

	return snapshot
end

local function collectSocialEconomySnapshot(): any
	local attrs = SocialEconomyConfig.StateAttributes
	return {
		favor = localPlayer:GetAttribute(attrs.Favor),
		control = localPlayer:GetAttribute(attrs.Control),
		dominantAxis = localPlayer:GetAttribute(attrs.DominantAxis),
		favorComplianceBonus = localPlayer:GetAttribute(attrs.FavorComplianceBonus),
		controlIntimidationBonus = localPlayer:GetAttribute(attrs.ControlIntimidationBonus),
	}
end

local function collectGiantEffectAttributes(): any
	local attributes = GiantEffectHudConfig.Attributes
	return {
		maxHealth = localPlayer:GetAttribute(attributes.MaxHealth),
		walkSpeed = localPlayer:GetAttribute(attributes.WalkSpeed),
		powerBudget = localPlayer:GetAttribute(attributes.PowerBudget),
		movementControl = localPlayer:GetAttribute(attributes.MovementControl),
		maxHealthBonus = localPlayer:GetAttribute(attributes.MaxHealthBonus),
		walkSpeedBonus = localPlayer:GetAttribute(attributes.WalkSpeedBonus),
		powerBudgetBonus = localPlayer:GetAttribute(attributes.PowerBudgetBonus),
		movementControlBonus = localPlayer:GetAttribute(attributes.MovementControlBonus),
	}
end

type SectionModel = {
	visible: boolean,
	title: string,
	summary: string,
	tone: string?,
}

type SectionHandle = {
	frame: Frame,
	accent: Frame?,
	title: TextLabel,
	toggle: TextButton,
	collapsedSummary: TextLabel,
	detailSummary: TextLabel,
	expanded: boolean,
	buildModel: () -> SectionModel?,
	refresh: () -> (),
}

local sectionsById: { [string]: SectionHandle } = {}

local function applySectionLayout(section: SectionHandle)
	section.collapsedSummary.Visible = not section.expanded
	section.detailSummary.Visible = section.expanded
	section.toggle.Text = if section.expanded then "−" else "+"
end

local function refreshSection(section: SectionHandle)
	local buildModel = section.buildModel
	if type(buildModel) ~= "function" then
		section.frame.Visible = false
		return
	end

	local model = buildModel()
	if type(model) ~= "table" then
		section.frame.Visible = false
		return
	end

	section.frame.Visible = model.visible == true
	if model.visible ~= true then
		return
	end

	section.title.Text = model.title
	section.collapsedSummary.Text = firstSummaryLine(model.summary)
	section.detailSummary.Text = model.summary
	if section.accent ~= nil then
		section.accent.BackgroundColor3 = toneColor(model.tone)
	end
end

local function createSection(parent: Frame, sectionId: string, defaultTitle: string, withAccent: boolean): SectionHandle
	local sectionFrame = Instance.new("Frame")
	sectionFrame.Name = sectionId
	sectionFrame.BackgroundColor3 = PANEL_BACKGROUND
	sectionFrame.BackgroundTransparency = 0.08
	sectionFrame.BorderSizePixel = 0
	sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	sectionFrame.Size = UDim2.new(1, 0, 0, 0)
	sectionFrame.Visible = false
	sectionFrame.Parent = parent

	local accent: Frame? = nil
	if withAccent then
		local accentFrame = Instance.new("Frame")
		accentFrame.Name = "Accent"
		accentFrame.BackgroundColor3 = ACCENT_BY_TONE.neutral
		accentFrame.BorderSizePixel = 0
		accentFrame.Size = UDim2.new(0, 4, 1, 0)
		accentFrame.Parent = sectionFrame
		accent = accentFrame
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, if withAccent then -4 else 0, 0, 0)
	content.Position = UDim2.fromOffset(if withAccent then 4 else 0, 0)
	content.Parent = sectionFrame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 2)
	contentLayout.Parent = content

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, -8, 0, GiantHudStackConfig.HeaderHeight)
	header.Parent = content

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(4, 4)
	title.Size = UDim2.new(1, -36, 1, -4)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = TITLE_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = defaultTitle
	title.Parent = header

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -4, 0, 4)
	toggle.Size = UDim2.fromOffset(24, 20)
	toggle.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
	toggle.BorderSizePixel = 0
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 16
	toggle.TextColor3 = TITLE_COLOR
	toggle.Text = "+"
	toggle.Parent = header

	local collapsedSummary = Instance.new("TextLabel")
	collapsedSummary.Name = "CollapsedSummary"
	collapsedSummary.BackgroundTransparency = 1
	collapsedSummary.LayoutOrder = 2
	collapsedSummary.Size = UDim2.new(1, -8, 0, GiantHudStackConfig.CollapsedSummaryHeight)
	collapsedSummary.Font = Enum.Font.Gotham
	collapsedSummary.TextSize = 13
	collapsedSummary.TextColor3 = SUMMARY_COLOR
	collapsedSummary.TextXAlignment = Enum.TextXAlignment.Left
	collapsedSummary.TextYAlignment = Enum.TextYAlignment.Top
	collapsedSummary.TextWrapped = true
	collapsedSummary.Text = ""
	collapsedSummary.Parent = content

	local detailSummary = Instance.new("TextLabel")
	detailSummary.Name = "DetailSummary"
	detailSummary.BackgroundTransparency = 1
	detailSummary.LayoutOrder = 3
	detailSummary.Size = UDim2.new(1, -8, 0, 0)
	detailSummary.AutomaticSize = Enum.AutomaticSize.Y
	detailSummary.Font = Enum.Font.Gotham
	detailSummary.TextSize = 13
	detailSummary.TextColor3 = SUMMARY_COLOR
	detailSummary.TextXAlignment = Enum.TextXAlignment.Left
	detailSummary.TextYAlignment = Enum.TextYAlignment.Top
	detailSummary.TextWrapped = true
	detailSummary.Visible = false
	detailSummary.Text = ""
	detailSummary.Parent = content

	local section: SectionHandle = {
		frame = sectionFrame,
		accent = accent,
		title = title,
		toggle = toggle,
		collapsedSummary = collapsedSummary,
		detailSummary = detailSummary,
		expanded = false,
		buildModel = nil,
		refresh = function() end,
	}

	section.refresh = function()
		refreshSection(section)
	end

	toggle.MouseButton1Click:Connect(function()
		section.expanded = not section.expanded
		applySectionLayout(section)
		section.refresh()
	end)

	applySectionLayout(section)
	return section
end

destroyLegacyGuis()

local existingStack = playerGui:FindFirstChild(GiantHudStackConfig.GuiName)
if existingStack ~= nil and existingStack:IsA("ScreenGui") then
	existingStack:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GiantHudStackConfig.GuiName
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local stackFrame = Instance.new("Frame")
stackFrame.Name = GiantHudStackConfig.StackName
stackFrame.AnchorPoint = Vector2.new(1, 0)
stackFrame.Position = UDim2.fromScale(GiantHudStackConfig.AnchorX, GiantHudStackConfig.AnchorY)
stackFrame.Size = UDim2.fromOffset(GiantHudStackConfig.StackWidth, 0)
stackFrame.AutomaticSize = Enum.AutomaticSize.Y
stackFrame.BackgroundTransparency = 1
stackFrame.BorderSizePixel = 0
stackFrame.Parent = screenGui

local stackLayout = Instance.new("UIListLayout")
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Padding = UDim.new(0, GiantHudStackConfig.SectionPadding)
stackLayout.Parent = stackFrame

penPart = findPenPart(PenRationingConfig.DefaultPenId)

local treasurySection = createSection(stackFrame, "Treasury", "Giant Realm Treasury", false)
treasurySection.buildModel = function(): SectionModel?
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
		return { visible = false, title = "", summary = "" }
	end
	local attributes = collectTreasuryAttributes()
	local ledgerInput, sessionInput = buildTreasuryPresentationInput(attributes)
	local model = GiantRealmTreasuryPresentation.BuildHudModel(ledgerInput, sessionInput)
	return {
		visible = model.visible,
		title = model.title,
		summary = model.summary,
	}
end
sectionsById.Treasury = treasurySection

local penSection = createSection(stackFrame, "PenRationing", "Pen Rationing", true)
penSection.buildModel = function(): SectionModel?
	local model = PenRationingHudPresentation.BuildHudModel(collectPenRationingSnapshot())
	return {
		visible = model.visible,
		title = model.title,
		summary = model.summary,
		tone = model.tone,
	}
end
sectionsById.PenRationing = penSection

local socialSection = createSection(stackFrame, "SocialEconomy", "Realm Social Economy", true)
socialSection.buildModel = function(): SectionModel?
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant or not hasSocialEconomyProjection() then
		return { visible = false, title = "", summary = "" }
	end
	local model = SocialEconomyPresentation.BuildHudModel(collectSocialEconomySnapshot())
	return {
		visible = model.visible,
		title = model.title,
		summary = model.summary,
		tone = model.tone,
	}
end
sectionsById.SocialEconomy = socialSection

local effectsSection = createSection(stackFrame, "GiantEffects", "Giant Effects", false)
effectsSection.buildModel = function(): SectionModel?
	if localPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
		return { visible = false, title = "", summary = "" }
	end
	local model = GiantEffectHudPresentation.BuildHudModel(collectGiantEffectAttributes())
	return {
		visible = model.visible,
		title = model.title,
		summary = model.summary,
	}
end
sectionsById.GiantEffects = effectsSection

local function refreshAllSections()
	for _, sectionId in ipairs(GiantHudStackConfig.SectionOrder) do
		local section = sectionsById[sectionId]
		if section ~= nil then
			section.refresh()
		end
	end
end

local function hookPlayerAttribute(attributeName: string)
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshAllSections)
end

hookPlayerAttribute("Role")
hookPlayerAttribute("CaptureActive")

for _, attributeName in pairs(GiantRealmTreasuryConfig.Attributes) do
	hookPlayerAttribute(attributeName)
end

local penAttrs = PenRationingConfig.StateAttributes
hookPlayerAttribute(penAttrs.CustodianMorale)
hookPlayerAttribute(penAttrs.CaptiveShortfallStreak)
hookPlayerAttribute(penAttrs.CaptiveStarving)
hookPlayerAttribute(SocialEconomyConfig.StateAttributes.ControlIntimidationBonus)

for _, attributeName in pairs(SocialEconomyConfig.StateAttributes) do
	hookPlayerAttribute(attributeName)
end

for _, attributeName in pairs(GiantEffectHudConfig.Attributes) do
	hookPlayerAttribute(attributeName)
end

if penPart ~= nil then
	local penPartAny = penPart :: any
	penPartAny:GetAttributeChangedSignal(penAttrs.LastFoodShortfall):Connect(refreshAllSections)
	penPartAny:GetAttributeChangedSignal(penAttrs.ConsecutiveShortfallTicks):Connect(refreshAllSections)
	penPartAny:GetAttributeChangedSignal(penAttrs.ActiveCaptiveCount):Connect(refreshAllSections)
	penPartAny:GetAttributeChangedSignal(penAttrs.FoodCostMultiplier):Connect(refreshAllSections)
end

refreshAllSections()
