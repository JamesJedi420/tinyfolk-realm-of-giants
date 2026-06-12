--!strict

local GameplayCollisionGroupConfig = {}

export type RelationKind = "collide" | "touch" | "ignore"

export type RelationEntry = {
	groupA: string,
	groupB: string,
	relation: RelationKind,
}

GameplayCollisionGroupConfig.Groups = {
	Giant = "Gameplay_Giant",
	Tinyfolk = "Gameplay_Tinyfolk",
	CarriedTinyfolk = "Gameplay_CarriedTinyfolk",
	ContainedTinyfolk = "Gameplay_ContainedTinyfolk",
	GiantRoute = "Gameplay_GiantRoute",
	TinyfolkRoute = "Gameplay_TinyfolkRoute",
	TriggerZone = "Gameplay_TriggerZone",
	BuildPreview = "Gameplay_BuildPreview",
	Containment = "Gameplay_Containment",
	WorldGeometry = "Gameplay_WorldGeometry",
}

GameplayCollisionGroupConfig.CharacterGroupAttribute = "GameplayCollisionGroup"

GameplayCollisionGroupConfig.WorldPartGroupAttribute = "GameplayCollisionGroup"

GameplayCollisionGroupConfig.WorldPartAttributeMappings = {
	TinyfolkOnlyRoute = GameplayCollisionGroupConfig.Groups.TinyfolkRoute,
	GiantOnlyRoute = GameplayCollisionGroupConfig.Groups.GiantRoute,
	BuildPreview = GameplayCollisionGroupConfig.Groups.BuildPreview,
}

-- Explicit symmetric matrix. Unlisted pairs default to collide.
GameplayCollisionGroupConfig.Relations = {
	{ groupA = "Gameplay_Giant", groupB = "Gameplay_Tinyfolk", relation = "collide" },
	{ groupA = "Gameplay_Giant", groupB = "Gameplay_CarriedTinyfolk", relation = "ignore" },
	{ groupA = "Gameplay_Giant", groupB = "Gameplay_ContainedTinyfolk", relation = "ignore" },
	{ groupA = "Gameplay_Giant", groupB = "Gameplay_TinyfolkRoute", relation = "ignore" },
	{ groupA = "Gameplay_Giant", groupB = "Gameplay_TriggerZone", relation = "touch" },
	{ groupA = "Gameplay_Giant", groupB = "Gameplay_BuildPreview", relation = "ignore" },

	{ groupA = "Gameplay_Tinyfolk", groupB = "Gameplay_CarriedTinyfolk", relation = "ignore" },
	{ groupA = "Gameplay_Tinyfolk", groupB = "Gameplay_ContainedTinyfolk", relation = "ignore" },
	{ groupA = "Gameplay_Tinyfolk", groupB = "Gameplay_GiantRoute", relation = "ignore" },
	{ groupA = "Gameplay_Tinyfolk", groupB = "Gameplay_TriggerZone", relation = "touch" },
	{ groupA = "Gameplay_Tinyfolk", groupB = "Gameplay_BuildPreview", relation = "ignore" },

	{ groupA = "Gameplay_CarriedTinyfolk", groupB = "Gameplay_CarriedTinyfolk", relation = "ignore" },
	{ groupA = "Gameplay_CarriedTinyfolk", groupB = "Gameplay_ContainedTinyfolk", relation = "ignore" },
	{ groupA = "Gameplay_CarriedTinyfolk", groupB = "Gameplay_GiantRoute", relation = "ignore" },
	{ groupA = "Gameplay_CarriedTinyfolk", groupB = "Gameplay_TinyfolkRoute", relation = "ignore" },
	{ groupA = "Gameplay_CarriedTinyfolk", groupB = "Gameplay_TriggerZone", relation = "touch" },
	{ groupA = "Gameplay_CarriedTinyfolk", groupB = "Gameplay_BuildPreview", relation = "ignore" },
	{ groupA = "Gameplay_CarriedTinyfolk", groupB = "Gameplay_Containment", relation = "ignore" },

	{ groupA = "Gameplay_ContainedTinyfolk", groupB = "Gameplay_ContainedTinyfolk", relation = "ignore" },
	{ groupA = "Gameplay_ContainedTinyfolk", groupB = "Gameplay_GiantRoute", relation = "ignore" },
	{ groupA = "Gameplay_ContainedTinyfolk", groupB = "Gameplay_TinyfolkRoute", relation = "ignore" },
	{ groupA = "Gameplay_ContainedTinyfolk", groupB = "Gameplay_TriggerZone", relation = "touch" },
	{ groupA = "Gameplay_ContainedTinyfolk", groupB = "Gameplay_BuildPreview", relation = "ignore" },
	{ groupA = "Gameplay_ContainedTinyfolk", groupB = "Gameplay_Containment", relation = "ignore" },
	{ groupA = "Gameplay_ContainedTinyfolk", groupB = "Gameplay_WorldGeometry", relation = "ignore" },

	{ groupA = "Gameplay_GiantRoute", groupB = "Gameplay_TinyfolkRoute", relation = "ignore" },
	{ groupA = "Gameplay_GiantRoute", groupB = "Gameplay_TriggerZone", relation = "touch" },
	{ groupA = "Gameplay_GiantRoute", groupB = "Gameplay_BuildPreview", relation = "ignore" },

	{ groupA = "Gameplay_TinyfolkRoute", groupB = "Gameplay_TriggerZone", relation = "touch" },
	{ groupA = "Gameplay_TinyfolkRoute", groupB = "Gameplay_BuildPreview", relation = "ignore" },

	{ groupA = "Gameplay_TriggerZone", groupB = "Gameplay_TriggerZone", relation = "ignore" },
	{ groupA = "Gameplay_TriggerZone", groupB = "Gameplay_BuildPreview", relation = "ignore" },
	{ groupA = "Gameplay_TriggerZone", groupB = "Gameplay_Containment", relation = "touch" },
	{ groupA = "Gameplay_TriggerZone", groupB = "Gameplay_WorldGeometry", relation = "touch" },

	{ groupA = "Gameplay_BuildPreview", groupB = "Gameplay_BuildPreview", relation = "ignore" },
	{ groupA = "Gameplay_BuildPreview", groupB = "Gameplay_Containment", relation = "ignore" },
	{ groupA = "Gameplay_BuildPreview", groupB = "Gameplay_WorldGeometry", relation = "ignore" },
} :: { RelationEntry }

return GameplayCollisionGroupConfig
