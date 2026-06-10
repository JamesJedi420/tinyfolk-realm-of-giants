--!strict

local SpecialistVisualConfig: any = {}

SpecialistVisualConfig.CharacterFolderName = "SpecialistVisualPlaceholder"

SpecialistVisualConfig.ApplyReasons = {
	Initial = "Initial",
	Assigned = "Assigned",
	Cleared = "Cleared",
	ClearedRoleChange = "ClearedRoleChange",
	CharacterRespawn = "CharacterRespawn",
}

SpecialistVisualConfig.Attributes = {
	Applied = "SpecialistVisualApplied",
	ActiveRole = "SpecialistVisualActiveRole",
	OutfitId = "SpecialistVisualOutfitId",
	ToolId = "SpecialistVisualToolId",
	LastApplyReason = "SpecialistVisualLastApplyReason",
	LastAppliedAt = "SpecialistVisualLastAppliedAt",
}

SpecialistVisualConfig.OutfitAttachPartNames = { "UpperTorso", "Torso", "HumanoidRootPart" }
SpecialistVisualConfig.ToolAttachPartNames = { "RightHand", "Right Arm" }

SpecialistVisualConfig.PlaceholderBySpecialistRole = {
	Woodcutter = {
		outfitId = "woodcutter_vest",
		toolId = "woodcutter_axe",
		outfitColor = { r = 0.55, g = 0.35, b = 0.15 },
		toolColor = { r = 0.65, g = 0.65, b = 0.65 },
	},
	Miner = {
		outfitId = "miner_tunic",
		toolId = "miner_pick",
		outfitColor = { r = 0.35, g = 0.4, b = 0.45 },
		toolColor = { r = 0.5, g = 0.5, b = 0.55 },
	},
	Farmer = {
		outfitId = "farmer_apron",
		toolId = "farmer_hoe",
		outfitColor = { r = 0.45, g = 0.55, b = 0.2 },
		toolColor = { r = 0.55, g = 0.4, b = 0.2 },
	},
	Worshipper = {
		outfitId = "worshipper_robe",
		toolId = "worshipper_relic",
		outfitColor = { r = 0.55, g = 0.25, b = 0.65 },
		toolColor = { r = 0.85, g = 0.75, b = 0.2 },
	},
}

return SpecialistVisualConfig
