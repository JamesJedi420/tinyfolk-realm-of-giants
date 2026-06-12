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

local GameplayPhysicsOwnershipConfig = requireDependency(
	Config,
	"GameplayPhysicsOwnershipConfig",
	"../../ReplicatedStorage/Shared/Config/GameplayPhysicsOwnershipConfig"
)
local GameplayPhysicsOwnershipPolicy = requireDependency(
	Physics,
	"GameplayPhysicsOwnershipPolicy",
	"../../ReplicatedStorage/Shared/Physics/GameplayPhysicsOwnershipPolicy"
)

local ROLE_ATTRIBUTE = "Role"
local CAPTURE_ACTIVE_ATTRIBUTE = "CaptureActive"
local CARRIED_STATE_ATTRIBUTE = "CarriedState"
local HELD_TARGET_ATTRIBUTE = "HeldTargetUserId"
local HELD_BY_ATTRIBUTE = "HeldByUserId"

export type ApplyDiagnostics = {
	tier: string,
	assemblyKind: string,
	reason: string,
	enforced: boolean,
}

export type ServiceDiagnostics = {
	partsEnforced: number,
	charactersRefreshed: number,
	worldPartsAssigned: number,
	lastReason: string?,
}

local PhysicsOwnershipService: any = {}

local diagnostics: ServiceDiagnostics = {
	partsEnforced = 0,
	charactersRefreshed = 0,
	worldPartsAssigned = 0,
	lastReason = nil,
}

local function isBasePart(value: any): boolean
	return type(value) == "table" and value.ClassName == "Part"
		or (type(value) == "userdata" and typeof(value) == "Instance" and value:IsA("BasePart"))
end

local function setDebugAttributes(part: any, applyDiagnostics: ApplyDiagnostics)
	if type(part.SetAttribute) ~= "function" then
		return
	end

	part:SetAttribute(GameplayPhysicsOwnershipConfig.TierAttribute, applyDiagnostics.tier)
	part:SetAttribute(GameplayPhysicsOwnershipConfig.AssemblyAttribute, applyDiagnostics.assemblyKind)
	part:SetAttribute(GameplayPhysicsOwnershipConfig.EnforcedAttribute, applyDiagnostics.enforced)
	part:SetAttribute(GameplayPhysicsOwnershipConfig.LastReasonAttribute, applyDiagnostics.reason)
end

function PhysicsOwnershipService.ResetForTests()
	diagnostics = {
		partsEnforced = 0,
		charactersRefreshed = 0,
		worldPartsAssigned = 0,
		lastReason = "reset",
	}
end

function PhysicsOwnershipService.GetDiagnostics(): ServiceDiagnostics
	return diagnostics
end

function PhysicsOwnershipService.ApplyOwnershipToPart(
	part: any,
	tier: string,
	ownerPlayer: any?,
	reason: string,
	assemblyKind: string?
): ApplyDiagnostics
	if not isBasePart(part) then
		local skippedDiagnostics: ApplyDiagnostics = {
			tier = tier,
			assemblyKind = assemblyKind or "Unknown",
			reason = "not_base_part",
			enforced = false,
		}
		return skippedDiagnostics
	end

	local resolvedAssembly: string = assemblyKind or GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(part)

	local enforced = false
	if tier == GameplayPhysicsOwnershipConfig.OwnershipTier.Server then
		if type(part.SetNetworkOwner) == "function" then
			part:SetNetworkOwner(nil)
			enforced = true
		end
	elseif tier == GameplayPhysicsOwnershipConfig.OwnershipTier.Client then
		if type(part.SetNetworkOwner) == "function" and ownerPlayer ~= nil then
			part:SetNetworkOwner(ownerPlayer)
			enforced = true
		end
	elseif tier == GameplayPhysicsOwnershipConfig.OwnershipTier.Automatic then
		if type(part.SetNetworkOwner) == "function" then
			if ownerPlayer ~= nil then
				part:SetNetworkOwner(ownerPlayer)
			else
				part:SetNetworkOwner(nil)
			end
			enforced = true
		end
	end

	local applyDiagnostics: ApplyDiagnostics = {
		tier = tier,
		assemblyKind = resolvedAssembly,
		reason = reason,
		enforced = enforced,
	}
	setDebugAttributes(part, applyDiagnostics)
	if enforced then
		diagnostics.partsEnforced += 1
	end
	diagnostics.lastReason = reason
	return applyDiagnostics
end

function PhysicsOwnershipService.ApplyOwnershipToCharacter(
	character: any,
	tier: string,
	ownerPlayer: any?,
	reason: string,
	assemblyKind: string
)
	if type(character) ~= "table" or type(character.GetDescendants) ~= "function" then
		return
	end

	for _, descendant in character:GetDescendants() do
		if isBasePart(descendant) then
			PhysicsOwnershipService.ApplyOwnershipToPart(descendant, tier, ownerPlayer, reason, assemblyKind)
		end
	end
end

function PhysicsOwnershipService.ResolveCharacterProfileForPlayer(player: any): any
	if type(player) ~= "table" then
		return {
			role = nil,
			captureActive = false,
			carriedState = nil,
			heldTargetUserId = nil,
			heldByUserId = nil,
		}
	end

	local role = if type(player.GetAttribute) == "function" then player:GetAttribute(ROLE_ATTRIBUTE) else nil
	local captureActive = if type(player.GetAttribute) == "function"
		then player:GetAttribute(CAPTURE_ACTIVE_ATTRIBUTE)
		else nil
	local carriedState = if type(player.GetAttribute) == "function"
		then player:GetAttribute(CARRIED_STATE_ATTRIBUTE)
		else nil
	local heldTargetUserId = if type(player.GetAttribute) == "function"
		then player:GetAttribute(HELD_TARGET_ATTRIBUTE)
		else nil
	local heldByUserId = if type(player.GetAttribute) == "function" then player:GetAttribute(HELD_BY_ATTRIBUTE) else nil

	return {
		role = if type(role) == "string" then role else nil,
		captureActive = captureActive == true,
		carriedState = if type(carriedState) == "string" then carriedState else nil,
		heldTargetUserId = if type(heldTargetUserId) == "number" then heldTargetUserId else nil,
		heldByUserId = if type(heldByUserId) == "number" then heldByUserId else nil,
	}
end

function PhysicsOwnershipService.RefreshPlayerCharacter(player: any)
	if type(player) ~= "table" then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local profile = PhysicsOwnershipService.ResolveCharacterProfileForPlayer(player)
	local assemblyKind = GameplayPhysicsOwnershipPolicy.ResolveCharacterAssembly(profile)
	local tier = GameplayPhysicsOwnershipPolicy.ResolveCharacterTier(profile)
	PhysicsOwnershipService.ApplyOwnershipToCharacter(character, tier, player, "character_refresh", assemblyKind)

	if type(player.SetAttribute) == "function" then
		player:SetAttribute(GameplayPhysicsOwnershipConfig.CharacterAssemblyAttribute, assemblyKind)
		player:SetAttribute(GameplayPhysicsOwnershipConfig.TierAttribute, tier)
	end

	diagnostics.charactersRefreshed += 1
	diagnostics.lastReason = "character_refresh"
end

function PhysicsOwnershipService.ApplyGroupToPart(part: any, assemblyKind: string?)
	local resolvedAssembly = assemblyKind
	if resolvedAssembly == nil then
		resolvedAssembly = GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(part)
	end
	local tier = GameplayPhysicsOwnershipPolicy.ResolveAssemblyTier(resolvedAssembly :: any)
	PhysicsOwnershipService.ApplyOwnershipToPart(part, tier, nil, "world_part_assign", resolvedAssembly)
end

function PhysicsOwnershipService.AssignWorldPartsUnderRoot(root: any): number
	if type(root) ~= "table" or type(root.GetDescendants) ~= "function" then
		return 0
	end

	local assignedCount = 0
	local rootAssembly = GameplayPhysicsOwnershipPolicy.ResolveModelAssembly(root)
	for _, descendant in root:GetDescendants() do
		if isBasePart(descendant) then
			local assemblyKind = rootAssembly
			if assemblyKind == GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry then
				assemblyKind = GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(descendant)
			end
			PhysicsOwnershipService.ApplyGroupToPart(descendant, assemblyKind)
			assignedCount += 1
		end
	end

	diagnostics.worldPartsAssigned += assignedCount
	diagnostics.lastReason = "world_assign"
	return assignedCount
end

function PhysicsOwnershipService.GetCharacterAssemblyForPlayer(player: any): string
	local profile = PhysicsOwnershipService.ResolveCharacterProfileForPlayer(player)
	return GameplayPhysicsOwnershipPolicy.ResolveCharacterAssembly(profile)
end

function PhysicsOwnershipService.GetCharacterTierForPlayer(player: any): string
	local profile = PhysicsOwnershipService.ResolveCharacterProfileForPlayer(player)
	return GameplayPhysicsOwnershipPolicy.ResolveCharacterTier(profile)
end

function PhysicsOwnershipService.RequiresServerOwnershipForPlayer(player: any): boolean
	local tier = PhysicsOwnershipService.GetCharacterTierForPlayer(player)
	return GameplayPhysicsOwnershipPolicy.RequiresServerOwnership(tier :: any)
end

return PhysicsOwnershipService
