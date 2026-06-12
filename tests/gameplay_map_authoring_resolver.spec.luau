--!strict

local GameplayCollisionGroupConfig = require("../src/ReplicatedStorage/Shared/Config/GameplayCollisionGroupConfig")
local GameplayMapAuthoringConfig = require("../src/ReplicatedStorage/Shared/Config/GameplayMapAuthoringConfig")
local GameplayPhysicsOwnershipConfig = require("../src/ReplicatedStorage/Shared/Config/GameplayPhysicsOwnershipConfig")
local GameplayCollisionGroupMatrix = require("../src/ReplicatedStorage/Shared/Physics/GameplayCollisionGroupMatrix")
local GameplayMapAuthoringResolver = require("../src/ReplicatedStorage/Shared/Physics/GameplayMapAuthoringResolver")
local GameplayPhysicsOwnershipPolicy = require("../src/ReplicatedStorage/Shared/Physics/GameplayPhysicsOwnershipPolicy")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local valid, reason = GameplayMapAuthoringResolver.ValidateConfig()
	assertTrue(valid, "authoring config validates")
	assertEqual(reason, nil, "authoring validation reason nil")
end

local containmentFolder: any = {
	Name = "PenRoot",
	_tags = { GameplayMapAuthoringConfig.Tags.Containment },
	Parent = nil,
}

local penWall: any = {
	Name = "Pen_A",
	ClassName = "Part",
	CanCollide = true,
	CanTouch = false,
	Parent = containmentFolder,
	GetAttribute = function(_self: any, _name: string): any
		return nil
	end,
}

assertEqual(
	GameplayMapAuthoringResolver.ResolveCollisionGroupFromTags(penWall),
	GameplayCollisionGroupConfig.Groups.Containment,
	"ancestor containment tag maps collision group"
)
assertEqual(
	GameplayMapAuthoringResolver.ResolveOwnershipAssemblyFromTags(penWall),
	GameplayPhysicsOwnershipConfig.Assemblies.ContainmentStructure,
	"ancestor containment tag maps ownership assembly"
)
assertEqual(
	GameplayCollisionGroupMatrix.ResolveWorldPartGroup(penWall),
	GameplayCollisionGroupConfig.Groups.Containment,
	"collision matrix resolves tagged pen wall"
)
assertEqual(
	GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(penWall),
	GameplayPhysicsOwnershipConfig.Assemblies.ContainmentStructure,
	"ownership policy resolves tagged pen wall"
)

local doorFolder: any = {
	Name = "GiantLoadingFace",
	_tags = { GameplayMapAuthoringConfig.Tags.Door },
	Parent = nil,
}

local doorSlab: any = {
	Name = "Door_LeftSlab",
	ClassName = "Part",
	CanCollide = false,
	CanTouch = false,
	Parent = doorFolder,
	GetAttribute = function(_self: any, _name: string): any
		return nil
	end,
}

assertEqual(
	GameplayMapAuthoringResolver.ResolveOwnershipAssemblyFromTags(doorSlab),
	GameplayPhysicsOwnershipConfig.Assemblies.GameplayDoor,
	"ancestor door tag maps gameplay door assembly"
)

local lootFolder: any = {
	Name = "Dressing_TradeDock_CrateCluster_A",
	_tags = { GameplayMapAuthoringConfig.Tags.RewardLoot },
	Parent = nil,
}

local lootCrate: any = {
	Name = "TradeCrate_01",
	ClassName = "Part",
	CanCollide = false,
	CanTouch = false,
	Parent = lootFolder,
	GetAttribute = function(_self: any, name: string): any
		if name == "RewardLoot" then
			return true
		end
		return nil
	end,
}

assertEqual(
	GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(lootCrate),
	GameplayPhysicsOwnershipConfig.Assemblies.RewardLoot,
	"reward loot tag resolves before attribute heuristics"
)

print("gameplay_map_authoring_resolver.spec.luau: all checks passed")
