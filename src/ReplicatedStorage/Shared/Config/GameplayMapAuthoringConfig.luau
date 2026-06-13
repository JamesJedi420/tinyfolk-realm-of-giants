--!strict

local GameplayCollisionGroupConfig = require("./GameplayCollisionGroupConfig")
local GameplayPhysicsOwnershipConfig = require("./GameplayPhysicsOwnershipConfig")

local GameplayMapAuthoringConfig = {}

GameplayMapAuthoringConfig.Tags = {
	Containment = "GameplayTag_Containment",
	Door = "GameplayTag_Door",
	RewardLoot = "GameplayTag_RewardLoot",
	TriggerZone = "GameplayTag_TriggerZone",
	TinyfolkRoute = "GameplayTag_TinyfolkRoute",
	GiantRoute = "GameplayTag_GiantRoute",
	BuildPreview = "GameplayTag_BuildPreview",
}

-- First matching tag wins when multiple tags appear on self or ancestors.
GameplayMapAuthoringConfig.TagResolutionOrder = {
	GameplayMapAuthoringConfig.Tags.BuildPreview,
	GameplayMapAuthoringConfig.Tags.Containment,
	GameplayMapAuthoringConfig.Tags.Door,
	GameplayMapAuthoringConfig.Tags.RewardLoot,
	GameplayMapAuthoringConfig.Tags.TriggerZone,
	GameplayMapAuthoringConfig.Tags.TinyfolkRoute,
	GameplayMapAuthoringConfig.Tags.GiantRoute,
}

GameplayMapAuthoringConfig.TagCollisionGroup = {
	[GameplayMapAuthoringConfig.Tags.Containment] = GameplayCollisionGroupConfig.Groups.Containment,
	[GameplayMapAuthoringConfig.Tags.Door] = GameplayCollisionGroupConfig.Groups.WorldGeometry,
	[GameplayMapAuthoringConfig.Tags.RewardLoot] = GameplayCollisionGroupConfig.Groups.WorldGeometry,
	[GameplayMapAuthoringConfig.Tags.TriggerZone] = GameplayCollisionGroupConfig.Groups.TriggerZone,
	[GameplayMapAuthoringConfig.Tags.TinyfolkRoute] = GameplayCollisionGroupConfig.Groups.TinyfolkRoute,
	[GameplayMapAuthoringConfig.Tags.GiantRoute] = GameplayCollisionGroupConfig.Groups.GiantRoute,
	[GameplayMapAuthoringConfig.Tags.BuildPreview] = GameplayCollisionGroupConfig.Groups.BuildPreview,
}

GameplayMapAuthoringConfig.TagOwnershipAssembly = {
	[GameplayMapAuthoringConfig.Tags.Containment] = GameplayPhysicsOwnershipConfig.Assemblies.ContainmentStructure,
	[GameplayMapAuthoringConfig.Tags.Door] = GameplayPhysicsOwnershipConfig.Assemblies.GameplayDoor,
	[GameplayMapAuthoringConfig.Tags.RewardLoot] = GameplayPhysicsOwnershipConfig.Assemblies.RewardLoot,
	[GameplayMapAuthoringConfig.Tags.TriggerZone] = GameplayPhysicsOwnershipConfig.Assemblies.TriggerZone,
	[GameplayMapAuthoringConfig.Tags.TinyfolkRoute] = GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry,
	[GameplayMapAuthoringConfig.Tags.GiantRoute] = GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry,
	[GameplayMapAuthoringConfig.Tags.BuildPreview] = GameplayPhysicsOwnershipConfig.Assemblies.BuildPreview,
}

-- Authored map folders expected to carry gameplay tags (validated by tests).
GameplayMapAuthoringConfig.RequiredTaggedRoots = {
	{
		layoutPath = "src/Workspace/Map/Stations/Pen/Layout.model.json",
		tag = GameplayMapAuthoringConfig.Tags.Containment,
	},
	{
		layoutPath = "src/Workspace/Map/CaptureZones/Layout.model.json",
		tag = GameplayMapAuthoringConfig.Tags.TriggerZone,
	},
	{
		layoutPath = "src/Workspace/Map/GiantRoutes/Layout.model.json",
		tag = GameplayMapAuthoringConfig.Tags.GiantRoute,
	},
	{
		layoutPath = "src/Workspace/Map/Stations/Granary/Layout.model.json",
		childName = "GiantLoadingFace",
		tag = GameplayMapAuthoringConfig.Tags.Door,
	},
	{
		layoutPath = "src/Workspace/Map/Stations/Warehouse/Layout.model.json",
		childName = "Warehouse_DoorFrame",
		tag = GameplayMapAuthoringConfig.Tags.Door,
		attribute = "GameplayDoor",
	},
	{
		layoutPath = "src/Workspace/Map/ExternalDressingPlaceholder/Layout.model.json",
		childName = "Dressing_Containment_PenOutline_A",
		tag = GameplayMapAuthoringConfig.Tags.Containment,
	},
	{
		layoutPath = "src/Workspace/Map/ExternalDressingPlaceholder/Layout.model.json",
		childName = "Dressing_TradeDock_CrateCluster_A",
		tag = GameplayMapAuthoringConfig.Tags.RewardLoot,
		attribute = "RewardLoot",
	},
}

return GameplayMapAuthoringConfig
