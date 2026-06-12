--!strict

local GameplayCollisionGroupConfig = require("../Config/GameplayCollisionGroupConfig")

export type RelationKind = GameplayCollisionGroupConfig.RelationKind

export type CharacterProfile = {
	role: string?,
	captureActive: boolean?,
	carriedState: string?,
}

local GameplayCollisionGroupMatrix = {}

local function normalizePair(groupA: string, groupB: string): (string, string)
	if groupA <= groupB then
		return groupA, groupB
	end
	return groupB, groupA
end

local function pairKey(groupA: string, groupB: string): string
	local left, right = normalizePair(groupA, groupB)
	return left .. "|" .. right
end

function GameplayCollisionGroupMatrix.GetAllGroups(): { string }
	local groups: { string } = {}
	for _, groupName in pairs(GameplayCollisionGroupConfig.Groups) do
		table.insert(groups, groupName)
	end
	table.sort(groups)
	return groups
end

function GameplayCollisionGroupMatrix.BuildRelationLookup(): { [string]: RelationKind }
	local lookup: { [string]: RelationKind } = {}
	for _, entry in ipairs(GameplayCollisionGroupConfig.Relations) do
		local relation: RelationKind = entry.relation
		lookup[pairKey(entry.groupA, entry.groupB)] = relation
	end
	return lookup
end

function GameplayCollisionGroupMatrix.GetRelation(
	groupA: string,
	groupB: string,
	lookup: { [string]: RelationKind }?
): RelationKind
	if groupA == groupB then
		local sameGroupRelation = if lookup ~= nil then lookup[pairKey(groupA, groupB)] else nil
		if sameGroupRelation ~= nil then
			return sameGroupRelation :: RelationKind
		end
		return "collide"
	end

	if lookup ~= nil then
		local relation = lookup[pairKey(groupA, groupB)]
		if relation ~= nil then
			return relation :: RelationKind
		end
	end
	return "collide"
end

function GameplayCollisionGroupMatrix.IsCollidableRelation(relation: RelationKind): boolean
	return relation == "collide"
end

function GameplayCollisionGroupMatrix.ValidateConfig(): (boolean, string?)
	local knownGroups: { [string]: boolean } = {}
	for _, groupName in pairs(GameplayCollisionGroupConfig.Groups) do
		knownGroups[groupName] = true
	end

	for index, entry in ipairs(GameplayCollisionGroupConfig.Relations) do
		if not knownGroups[entry.groupA] then
			return false, string.format("relation_%d_unknown_group_a", index)
		end
		if not knownGroups[entry.groupB] then
			return false, string.format("relation_%d_unknown_group_b", index)
		end
		if entry.relation ~= "collide" and entry.relation ~= "touch" and entry.relation ~= "ignore" then
			return false, string.format("relation_%d_invalid_kind", index)
		end
	end

	return true, nil
end

local function isCarriedState(carriedState: string?): boolean
	return carriedState == "Carried" or carriedState == "Counterplay"
end

function GameplayCollisionGroupMatrix.ResolveCharacterGroup(profile: CharacterProfile): string
	if isCarriedState(profile.carriedState) then
		return GameplayCollisionGroupConfig.Groups.CarriedTinyfolk
	end
	if profile.captureActive == true then
		return GameplayCollisionGroupConfig.Groups.ContainedTinyfolk
	end
	if profile.role == "Giant" then
		return GameplayCollisionGroupConfig.Groups.Giant
	end
	return GameplayCollisionGroupConfig.Groups.Tinyfolk
end

function GameplayCollisionGroupMatrix.ResolveWorldPartGroup(part: any): string
	if type(part) ~= "table" then
		return GameplayCollisionGroupConfig.Groups.WorldGeometry
	end

	if type(part.GetAttribute) == "function" then
		local explicitGroup = part:GetAttribute(GameplayCollisionGroupConfig.WorldPartGroupAttribute)
		if type(explicitGroup) == "string" and string.len(explicitGroup) > 0 then
			return explicitGroup
		end

		for attributeName, groupName in pairs(GameplayCollisionGroupConfig.WorldPartAttributeMappings) do
			local attributeValue = part:GetAttribute(attributeName)
			if attributeValue == true or attributeValue == "true" then
				return groupName
			end
		end

		local districtId = part:GetAttribute("DistrictId")
		if districtId == "Containment" then
			return GameplayCollisionGroupConfig.Groups.Containment
		end

		if part.CanCollide == false and part.CanTouch == true then
			return GameplayCollisionGroupConfig.Groups.TriggerZone
		end
	end

	return GameplayCollisionGroupConfig.Groups.WorldGeometry
end

return GameplayCollisionGroupMatrix
