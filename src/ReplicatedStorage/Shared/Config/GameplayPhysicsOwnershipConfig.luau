--!strict

local GameplayPhysicsOwnershipConfig = {}

export type OwnershipTier = string
export type AssemblyKind = string

GameplayPhysicsOwnershipConfig.OwnershipTier = {
	Server = "Server",
	Automatic = "Automatic",
	Client = "Client",
}

GameplayPhysicsOwnershipConfig.Assemblies = {
	CarriedTinyfolk = "CarriedTinyfolk",
	ContainedTinyfolk = "ContainedTinyfolk",
	CarryingGiant = "CarryingGiant",
	FreeCharacter = "FreeCharacter",
	ContainmentStructure = "ContainmentStructure",
	SnareTrap = "SnareTrap",
	GameplayDoor = "GameplayDoor",
	RewardLoot = "RewardLoot",
	TriggerZone = "TriggerZone",
	BuildPreview = "BuildPreview",
	WorldGeometry = "WorldGeometry",
}

GameplayPhysicsOwnershipConfig.TierAttribute = "GameplayPhysicsOwnershipTier"
GameplayPhysicsOwnershipConfig.AssemblyAttribute = "GameplayPhysicsOwnershipAssembly"
GameplayPhysicsOwnershipConfig.EnforcedAttribute = "GameplayPhysicsOwnershipEnforced"
GameplayPhysicsOwnershipConfig.LastReasonAttribute = "GameplayPhysicsOwnershipLastReason"
GameplayPhysicsOwnershipConfig.CharacterAssemblyAttribute = "GameplayPhysicsOwnershipCharacterAssembly"

GameplayPhysicsOwnershipConfig.WorldPartAssemblyAttribute = "GameplayPhysicsOwnershipAssemblyOverride"

GameplayPhysicsOwnershipConfig.SnareTrapIdAttribute = "SnareTrapId"

GameplayPhysicsOwnershipConfig.WorldPartAttributeMappings = {
	BuildPreview = GameplayPhysicsOwnershipConfig.Assemblies.BuildPreview,
	GiantOnlyRoute = GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry,
	TinyfolkOnlyRoute = GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry,
	GameplayDoor = GameplayPhysicsOwnershipConfig.Assemblies.GameplayDoor,
	RewardLoot = GameplayPhysicsOwnershipConfig.Assemblies.RewardLoot,
}

-- Outcome-critical assemblies must remain server-owned; client ownership cannot grant capture/escape/custody/reward outcomes.
GameplayPhysicsOwnershipConfig.AssemblyTier = {
	CarriedTinyfolk = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	ContainedTinyfolk = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	CarryingGiant = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	FreeCharacter = GameplayPhysicsOwnershipConfig.OwnershipTier.Automatic,
	ContainmentStructure = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	SnareTrap = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	GameplayDoor = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	RewardLoot = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	TriggerZone = GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
	BuildPreview = GameplayPhysicsOwnershipConfig.OwnershipTier.Client,
	WorldGeometry = GameplayPhysicsOwnershipConfig.OwnershipTier.Automatic,
}

GameplayPhysicsOwnershipConfig.ServerCriticalAssemblies = {
	GameplayPhysicsOwnershipConfig.Assemblies.CarriedTinyfolk,
	GameplayPhysicsOwnershipConfig.Assemblies.ContainedTinyfolk,
	GameplayPhysicsOwnershipConfig.Assemblies.CarryingGiant,
	GameplayPhysicsOwnershipConfig.Assemblies.ContainmentStructure,
	GameplayPhysicsOwnershipConfig.Assemblies.SnareTrap,
	GameplayPhysicsOwnershipConfig.Assemblies.GameplayDoor,
	GameplayPhysicsOwnershipConfig.Assemblies.RewardLoot,
	GameplayPhysicsOwnershipConfig.Assemblies.TriggerZone,
}

return GameplayPhysicsOwnershipConfig
