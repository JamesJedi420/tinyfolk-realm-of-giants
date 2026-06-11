--!nocheck

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = Shared:WaitForChild("Skills")
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else require("./ProfilePersistenceGateway")
local SkillsProfileState = require(Skills:WaitForChild("SkillsProfileState"))

local SkillProgressionService = {}

local function readProfileData(player: Player): any?
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
	if not profileResult.ok then
		return nil
	end
	if type(profileResult.data) ~= "table" then
		return nil
	end
	return profileResult.data
end

local function unlockSkill(player: Player, skillId: string): any
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = SkillsProfileState.ResolveUnlock(currentData, skillId)
		if not transition.accepted then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		return {
			accepted = false,
			reason = updateResult.reason or "skill_unlock_failed",
			skillId = skillId,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		skillId = skillId,
		unlockedSkillIds = SkillsProfileState.GetUnlockedSkillIds(updateResult.data),
	}
end

_G._SkillProgressionService_QueryAPI = {
	UnlockSkill = function(player: Player, skillId: string): any
		return unlockSkill(player, skillId)
	end,
	GetUnlockedSkillIds = function(player: Player): any
		local profileData = readProfileData(player)
		if profileData == nil then
			return {}
		end
		return SkillsProfileState.GetUnlockedSkillIds(profileData)
	end,
}

return SkillProgressionService
