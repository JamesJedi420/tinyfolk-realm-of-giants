--!strict

local GameplayPhysicsOwnershipConfig = require("../Config/GameplayPhysicsOwnershipConfig")
local GameplayMapAuthoringResolver = require("./GameplayMapAuthoringResolver")

export type OwnershipTier = GameplayPhysicsOwnershipConfig.OwnershipTier
export type AssemblyKind = GameplayPhysicsOwnershipConfig.AssemblyKind

export type CharacterProfile = {
	role: string?,
	captureActive: boolean?,
	carriedState: string?,
	heldTargetUserId: number?,
	heldByUserId: number?,
}

local GameplayPhysicsOwnershipPolicy = {}

local function isCarriedState(carriedState: string?): boolean
	return carriedState == "Carried" or carriedState == "Counterplay"
end

function GameplayPhysicsOwnershipPolicy.ValidateConfig(): (boolean, string?)
	local assemblies = GameplayPhysicsOwnershipConfig.Assemblies
	for assemblyKind, tier in pairs(GameplayPhysicsOwnershipConfig.AssemblyTier) do
		if assemblies[assemblyKind] == nil then
			return false, string.format("unknown_assembly_tier_%s", tostring(assemblyKind))
		end
		if tier ~= "Server" and tier ~= "Automatic" and tier ~= "Client" then
			return false, string.format("invalid_tier_%s", tostring(assemblyKind))
		end
	end

	for _, assemblyKind in ipairs(GameplayPhysicsOwnershipConfig.ServerCriticalAssemblies) do
		local tier = GameplayPhysicsOwnershipConfig.AssemblyTier[assemblyKind :: AssemblyKind]
		if tier ~= GameplayPhysicsOwnershipConfig.OwnershipTier.Server then
			return false, string.format("critical_assembly_not_server_%s", assemblyKind)
		end
	end

	return true, nil
end

function GameplayPhysicsOwnershipPolicy.ResolveAssemblyTier(assemblyKind: AssemblyKind): OwnershipTier
	local tier = GameplayPhysicsOwnershipConfig.AssemblyTier[assemblyKind]
	if tier ~= nil then
		return tier :: OwnershipTier
	end
	return GameplayPhysicsOwnershipConfig.OwnershipTier.Automatic :: OwnershipTier
end

function GameplayPhysicsOwnershipPolicy.RequiresServerOwnership(tier: OwnershipTier): boolean
	return tier == GameplayPhysicsOwnershipConfig.OwnershipTier.Server
end

function GameplayPhysicsOwnershipPolicy.IsServerCriticalAssembly(assemblyKind: AssemblyKind): boolean
	for _, criticalAssembly in ipairs(GameplayPhysicsOwnershipConfig.ServerCriticalAssemblies) do
		if criticalAssembly == assemblyKind then
			return true
		end
	end
	return false
end

function GameplayPhysicsOwnershipPolicy.ResolveCharacterAssembly(profile: CharacterProfile): AssemblyKind
	if isCarriedState(profile.carriedState) or type(profile.heldByUserId) == "number" then
		return GameplayPhysicsOwnershipConfig.Assemblies.CarriedTinyfolk :: AssemblyKind
	end
	if profile.captureActive == true then
		return GameplayPhysicsOwnershipConfig.Assemblies.ContainedTinyfolk :: AssemblyKind
	end
	if type(profile.heldTargetUserId) == "number" then
		return GameplayPhysicsOwnershipConfig.Assemblies.CarryingGiant :: AssemblyKind
	end
	return GameplayPhysicsOwnershipConfig.Assemblies.FreeCharacter :: AssemblyKind
end

function GameplayPhysicsOwnershipPolicy.ResolveCharacterTier(profile: CharacterProfile): OwnershipTier
	local assemblyKind = GameplayPhysicsOwnershipPolicy.ResolveCharacterAssembly(profile)
	return GameplayPhysicsOwnershipPolicy.ResolveAssemblyTier(assemblyKind)
end

function GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(part: any): AssemblyKind
	if type(part) ~= "table" then
		return GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry :: AssemblyKind
	end

	if type(part.GetAttribute) == "function" then
		local explicitAssembly = part:GetAttribute(GameplayPhysicsOwnershipConfig.WorldPartAssemblyAttribute)
		if type(explicitAssembly) == "string" and string.len(explicitAssembly) > 0 then
			return explicitAssembly :: AssemblyKind
		end

		local taggedAssembly = GameplayMapAuthoringResolver.ResolveOwnershipAssemblyFromTags(part)
		if taggedAssembly ~= nil then
			return taggedAssembly :: AssemblyKind
		end

		local snareTrapId = part:GetAttribute(GameplayPhysicsOwnershipConfig.SnareTrapIdAttribute)
		if type(snareTrapId) == "string" and string.len(snareTrapId) > 0 then
			return GameplayPhysicsOwnershipConfig.Assemblies.SnareTrap :: AssemblyKind
		end

		for attributeName, assemblyKind in pairs(GameplayPhysicsOwnershipConfig.WorldPartAttributeMappings) do
			local attributeValue = part:GetAttribute(attributeName)
			if attributeValue == true or attributeValue == "true" then
				return assemblyKind :: AssemblyKind
			end
		end

		local districtId = part:GetAttribute("DistrictId")
		if districtId == "Containment" then
			return GameplayPhysicsOwnershipConfig.Assemblies.ContainmentStructure :: AssemblyKind
		end

		if part.CanCollide == false and part.CanTouch == true then
			return GameplayPhysicsOwnershipConfig.Assemblies.TriggerZone :: AssemblyKind
		end
	end

	return GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry :: AssemblyKind
end

function GameplayPhysicsOwnershipPolicy.ResolveWorldPartTier(part: any): OwnershipTier
	local assemblyKind = GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(part)
	return GameplayPhysicsOwnershipPolicy.ResolveAssemblyTier(assemblyKind)
end

function GameplayPhysicsOwnershipPolicy.ResolveModelAssembly(model: any): AssemblyKind
	if type(model) ~= "table" then
		return GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry :: AssemblyKind
	end

	if type(model.GetAttribute) == "function" then
		local assemblyFromModel = GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(model)
		if assemblyFromModel ~= GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry then
			return assemblyFromModel
		end
	end

	return GameplayPhysicsOwnershipConfig.Assemblies.WorldGeometry :: AssemblyKind
end

return GameplayPhysicsOwnershipPolicy
