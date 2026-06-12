--!strict

local GameplayMapAuthoringConfig = require("../Config/GameplayMapAuthoringConfig")

local GameplayMapAuthoringResolver = {}

local function instanceHasTag(instance: any, tag: string): boolean
	if instance == nil then
		return false
	end

	if type(instance.HasTag) == "function" then
		local ok, hasTag = pcall(function()
			return instance:HasTag(tag)
		end)
		if ok and hasTag == true then
			return true
		end
	end

	if type(instance) == "table" and type(instance._tags) == "table" then
		for _, existingTag in instance._tags do
			if existingTag == tag then
				return true
			end
		end
	end

	local okIsInstance, isInstance = pcall(function()
		return typeof(instance) == "Instance"
	end)
	if okIsInstance and isInstance then
		local okService, collectionService = pcall(function()
			return game:GetService("CollectionService")
		end)
		if okService and collectionService ~= nil and type(collectionService.HasTag) == "function" then
			local okHasTag, hasTag = pcall(collectionService.HasTag, collectionService, instance, tag)
			if okHasTag and hasTag == true then
				return true
			end
		end
	end

	return false
end

function GameplayMapAuthoringResolver.HasTagOnSelfOrAncestor(instance: any, tag: string): boolean
	local current = instance
	while current ~= nil do
		if instanceHasTag(current, tag) then
			return true
		end
		current = current.Parent
	end
	return false
end

function GameplayMapAuthoringResolver.ResolveTag(instance: any): string?
	for _, tag in ipairs(GameplayMapAuthoringConfig.TagResolutionOrder) do
		if GameplayMapAuthoringResolver.HasTagOnSelfOrAncestor(instance, tag) then
			return tag
		end
	end
	return nil
end

function GameplayMapAuthoringResolver.ResolveCollisionGroupFromTags(instance: any): string?
	local tag = GameplayMapAuthoringResolver.ResolveTag(instance)
	if tag == nil then
		return nil
	end
	return GameplayMapAuthoringConfig.TagCollisionGroup[tag]
end

function GameplayMapAuthoringResolver.ResolveOwnershipAssemblyFromTags(instance: any): string?
	local tag = GameplayMapAuthoringResolver.ResolveTag(instance)
	if tag == nil then
		return nil
	end
	return GameplayMapAuthoringConfig.TagOwnershipAssembly[tag]
end

function GameplayMapAuthoringResolver.ValidateConfig(): (boolean, string?)
	for _, tag in ipairs(GameplayMapAuthoringConfig.TagResolutionOrder) do
		if GameplayMapAuthoringConfig.TagCollisionGroup[tag] == nil then
			return false, string.format("missing_collision_mapping_%s", tag)
		end
		if GameplayMapAuthoringConfig.TagOwnershipAssembly[tag] == nil then
			return false, string.format("missing_ownership_mapping_%s", tag)
		end
	end
	return true, nil
end

return GameplayMapAuthoringResolver
