--!strict

local GiantHudStackConfig: any = {}

GiantHudStackConfig.GuiName = "GiantHudStackGui"
GiantHudStackConfig.StackName = "Stack"
GiantHudStackConfig.StackWidth = 320
GiantHudStackConfig.AnchorX = 0.98
GiantHudStackConfig.AnchorY = 0.14
GiantHudStackConfig.SectionPadding = 4
GiantHudStackConfig.HeaderHeight = 28
GiantHudStackConfig.CollapsedSummaryHeight = 20

GiantHudStackConfig.LegacyGuiNames = {
	"GiantEffectHudGui",
	"PenRationingHudGui",
	"GiantTreasuryHudGui",
	"SocialEconomyHudGui",
}

GiantHudStackConfig.SectionOrder = {
	"Treasury",
	"PenRationing",
	"SocialEconomy",
	"GiantEffects",
}

GiantHudStackConfig.PreferenceAttributes = {
	ExpandedBySectionIdJson = "GiantHudStackExpandedBySectionIdJson",
}

GiantHudStackConfig.PreferenceRemotes = {
	UpdateRequest = "GiantHudStackPreferenceUpdateRequest",
	UpdateResponse = "GiantHudStackPreferenceUpdateResponse",
}

return GiantHudStackConfig
