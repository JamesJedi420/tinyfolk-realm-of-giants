--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoleLoadout = Shared:WaitForChild("RoleLoadout")
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else require("./ProfilePersistenceGateway")
local RoleLoadoutState = if script ~= nil and script.Parent ~= nil
	then require(RoleLoadout:WaitForChild("RoleLoadoutState"))
	else require("../../ReplicatedStorage/Shared/RoleLoadout/RoleLoadoutState")

local RoleLoadoutService = {}

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

local function selectLoadout(player: Player, selectedTraitIds: any, registry: any?): any
	local requesterRole = getRole(player)
	if type(requesterRole) ~= "string" then
		return {
			accepted = false,
			reason = "invalid_role",
			selectedBySlot = {},
		}
	end

	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = RoleLoadoutState.ResolveSelection(currentData, {
			requesterRole = requesterRole,
			selectedTraitIds = selectedTraitIds,
		}, registry)
		if not transition.accepted then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		return {
			accepted = false,
			reason = updateResult.reason or "loadout_select_failed",
			selectedBySlot = {},
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		selectedBySlot = RoleLoadoutState.GetSelectedLoadout(updateResult.data, requesterRole),
	}
end

_G._RoleLoadoutService_QueryAPI = {
	SelectLoadout = function(player: Player, selectedTraitIds: any, registry: any?): any
		return selectLoadout(player, selectedTraitIds, registry)
	end,
	GetSelectedLoadout = function(player: Player): any
		local requesterRole = getRole(player)
		if type(requesterRole) ~= "string" then
			return {}
		end
		local profileData = readProfileData(player)
		if profileData == nil then
			return {}
		end
		return RoleLoadoutState.GetSelectedLoadout(profileData, requesterRole)
	end,
	GetDefaultLoadout = function(player: Player, registry: any?): any
		local requesterRole = getRole(player)
		if type(requesterRole) ~= "string" then
			return {}
		end
		local profileData = readProfileData(player)
		return RoleLoadoutState.BuildDefaultLoadout(profileData or {}, requesterRole, registry)
	end,
}

return RoleLoadoutService
