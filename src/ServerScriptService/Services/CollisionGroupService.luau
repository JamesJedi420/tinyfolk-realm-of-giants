--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function requireDependency(parent: any, childName: string, fallbackPath: string): any
	local requireAny: any = require
	if parent ~= nil and type(parent.WaitForChild) == "function" then
		local child = parent:WaitForChild(childName)
		if child ~= nil then
			local ok, loaded = pcall(function()
				return requireAny(child)
			end)
			if ok then
				return loaded
			end
		end
	end

	return requireAny(fallbackPath)
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Physics = Shared:WaitForChild("Physics")

local GameplayCollisionGroupConfig = requireDependency(
	Config,
	"GameplayCollisionGroupConfig",
	"../../ReplicatedStorage/Shared/Config/GameplayCollisionGroupConfig"
)
local GameplayCollisionGroupMatrix = requireDependency(
	Physics,
	"GameplayCollisionGroupMatrix",
	"../../ReplicatedStorage/Shared/Physics/GameplayCollisionGroupMatrix"
)

local ROLE_ATTRIBUTE = "Role"
local CAPTURE_ACTIVE_ATTRIBUTE = "CaptureActive"
local CARRIED_STATE_ATTRIBUTE = "CarriedState"

export type RegistrationDiagnostics = {
	registeredGroups: { string },
	appliedPairs: number,
	lastReason: string?,
}

local CollisionGroupService: any = {}

local registrationDiagnostics: RegistrationDiagnostics = {
	registeredGroups = {},
	appliedPairs = 0,
	lastReason = nil,
}

local matrixRegistered = false
local relationLookup = GameplayCollisionGroupMatrix.BuildRelationLookup()

local function isBasePart(value: any): boolean
	return type(value) == "table" and value.ClassName == "Part"
		or (type(value) == "userdata" and typeof(value) == "Instance" and value:IsA("BasePart"))
end

local function setPartCollisionGroup(part: any, groupName: string)
	if not isBasePart(part) then
		return
	end
	part.CollisionGroup = groupName
end

function CollisionGroupService.ResetForTests()
	matrixRegistered = false
	relationLookup = GameplayCollisionGroupMatrix.BuildRelationLookup()
	registrationDiagnostics = {
		registeredGroups = {},
		appliedPairs = 0,
		lastReason = "reset",
	}
end

function CollisionGroupService.GetRegistrationDiagnostics(): RegistrationDiagnostics
	return registrationDiagnostics
end

function CollisionGroupService.RegisterMatrix(physicsService: any): (boolean, string?)
	if type(physicsService) ~= "table" then
		return false, "physics_service_invalid"
	end

	local valid, reason = GameplayCollisionGroupMatrix.ValidateConfig()
	if not valid then
		return false, reason
	end

	local registerGroup = physicsService.RegisterCollisionGroup
	local setCollidable = physicsService.CollisionGroupSetCollidable
	if type(registerGroup) ~= "function" or type(setCollidable) ~= "function" then
		return false, "physics_service_missing_api"
	end

	local registeredGroups: { string } = {}
	for _, groupName in pairs(GameplayCollisionGroupConfig.Groups) do
		local ok = pcall(registerGroup, physicsService, groupName)
		if not ok then
			return false, "register_group_failed"
		end
		table.insert(registeredGroups, groupName)
	end

	local allGroups = GameplayCollisionGroupMatrix.GetAllGroups()
	local appliedPairs = 0
	for indexA = 1, #allGroups do
		for indexB = indexA, #allGroups do
			local groupA = allGroups[indexA]
			local groupB = allGroups[indexB]
			local relation = GameplayCollisionGroupMatrix.GetRelation(groupA, groupB, relationLookup)
			local collidable = GameplayCollisionGroupMatrix.IsCollidableRelation(relation)
			local ok = pcall(setCollidable, physicsService, groupA, groupB, collidable)
			if not ok then
				return false, "set_collidable_failed"
			end
			appliedPairs += 1
		end
	end

	matrixRegistered = true
	registrationDiagnostics = {
		registeredGroups = registeredGroups,
		appliedPairs = appliedPairs,
		lastReason = "registered",
	}
	return true, nil
end

function CollisionGroupService.ResolveCharacterGroupForPlayer(player: any): string
	if type(player) ~= "table" then
		return GameplayCollisionGroupConfig.Groups.Tinyfolk
	end

	local role = if type(player.GetAttribute) == "function" then player:GetAttribute(ROLE_ATTRIBUTE) else nil
	local captureActive = if type(player.GetAttribute) == "function"
		then player:GetAttribute(CAPTURE_ACTIVE_ATTRIBUTE)
		else nil
	local carriedState = if type(player.GetAttribute) == "function"
		then player:GetAttribute(CARRIED_STATE_ATTRIBUTE)
		else nil

	return GameplayCollisionGroupMatrix.ResolveCharacterGroup({
		role = if type(role) == "string" then role else nil,
		captureActive = captureActive == true,
		carriedState = if type(carriedState) == "string" then carriedState else nil,
	})
end

function CollisionGroupService.ApplyGroupToCharacter(character: any, groupName: string)
	if type(character) ~= "table" or type(character.GetDescendants) ~= "function" then
		return
	end

	for _, descendant in character:GetDescendants() do
		setPartCollisionGroup(descendant, groupName)
	end
end

function CollisionGroupService.ApplyGroupToPart(part: any, groupName: string?)
	local resolvedGroup = groupName
	if resolvedGroup == nil then
		resolvedGroup = GameplayCollisionGroupMatrix.ResolveWorldPartGroup(part)
	end
	setPartCollisionGroup(part, resolvedGroup :: string)
end

function CollisionGroupService.RefreshPlayerCharacter(player: any)
	if type(player) ~= "table" then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local groupName = CollisionGroupService.ResolveCharacterGroupForPlayer(player)
	CollisionGroupService.ApplyGroupToCharacter(character, groupName)

	if type(player.SetAttribute) == "function" then
		player:SetAttribute(GameplayCollisionGroupConfig.CharacterGroupAttribute, groupName)
	end
end

function CollisionGroupService.AssignWorldPartsUnderRoot(root: any): number
	if type(root) ~= "table" or type(root.GetDescendants) ~= "function" then
		return 0
	end

	local assignedCount = 0
	for _, descendant in root:GetDescendants() do
		if isBasePart(descendant) then
			CollisionGroupService.ApplyGroupToPart(descendant, nil)
			assignedCount += 1
		end
	end
	return assignedCount
end

function CollisionGroupService.IsMatrixRegistered(): boolean
	return matrixRegistered
end

function CollisionGroupService.GetRelation(groupA: string, groupB: string): string
	return GameplayCollisionGroupMatrix.GetRelation(groupA, groupB, relationLookup)
end

function CollisionGroupService.GetDefaultTinyfolkGroup(): string
	return GameplayCollisionGroupConfig.Groups.Tinyfolk
end

return CollisionGroupService
