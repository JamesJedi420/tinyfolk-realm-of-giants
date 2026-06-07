--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local ProfilePersistenceGateway = require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
local GiantTraitState = require(GiantRealm:WaitForChild("GiantTraitState"))

local GiantTraitService = {}

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

local function getRole(player: Player): string?
	local role = player:GetAttribute("Role")
	if type(role) ~= "string" then
		return nil
	end
	return role
end

local function unlockTrait(player: Player, traitId: string, unlockSource: string?): any
	local requesterRole = getRole(player)
	if requesterRole ~= "Giant" then
		return { accepted = false, reason = "requester_not_giant" }
	end

	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = GiantTraitState.ResolveUnlock(currentData, {
			traitId = traitId,
			requesterRole = requesterRole,
			unlockSource = unlockSource,
		})
		if not transition.accepted then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		return {
			accepted = false,
			reason = updateResult.reason or "trait_unlock_failed",
		}
	end

	local modifierSnapshot = GiantTraitState.ResolveModifierSnapshot(updateResult.data)
	return {
		accepted = true,
		reason = "accepted",
		traitId = traitId,
		unlockedTraitIds = modifierSnapshot.unlockedTraitIds,
		stationProductionMultiplier = modifierSnapshot.stationProductionMultiplier,
		scoreEventMultiplier = modifierSnapshot.scoreEventMultiplier,
	}
end

_G._GiantTraitService_QueryAPI = {
	UnlockTrait = function(player: Player, traitId: string, unlockSource: string?): any
		return unlockTrait(player, traitId, unlockSource)
	end,
	GetUnlockedTraitIds = function(player: Player): any
		local profileData = readProfileData(player)
		if profileData == nil then
			return {}
		end
		return GiantTraitState.GetUnlockedTraitIds(profileData)
	end,
	GetModifierSnapshot = function(player: Player): any
		local profileData = readProfileData(player)
		if profileData == nil then
			return {
				stationProductionMultiplier = 1,
				scoreEventMultiplier = 1,
				unlockedTraitIds = {},
			}
		end
		return GiantTraitState.ResolveModifierSnapshot(profileData)
	end,
}

return GiantTraitService
