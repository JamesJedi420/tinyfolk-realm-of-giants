--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TinyfolkTools = Shared:WaitForChild("TinyfolkTools")
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else require("./ProfilePersistenceGateway")
local TinyfolkToolLoadoutState = if script ~= nil and script.Parent ~= nil
	then require(TinyfolkTools:WaitForChild("TinyfolkToolLoadoutState"))
	else require("../../ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolLoadoutState")
local TinyfolkToolEntryPayload = if script ~= nil and script.Parent ~= nil
	then require(TinyfolkTools:WaitForChild("TinyfolkToolEntryPayload"))
	else require("../../ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolEntryPayload")
local TinyfolkToolCatalogSchema = if script ~= nil and script.Parent ~= nil
	then require(Shared:WaitForChild("Config"):WaitForChild("TinyfolkToolCatalogSchema"))
	else require("../../ReplicatedStorage/Shared/Config/TinyfolkToolCatalogSchema")

local TinyfolkToolLoadoutService = {}
local CANONICAL_CATALOG = TinyfolkToolCatalogSchema.DEFAULT_TOOL_CATALOG

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

local function selectLoadout(player: Player, selectedToolIds: any, catalog: any?): any
	local requesterRole = getRole(player)
	if requesterRole ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			selectedBySlot = {},
		}
	end

	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = TinyfolkToolLoadoutState.ResolveSelection(currentData, {
			requesterRole = requesterRole,
			selectedToolIds = selectedToolIds,
		}, catalog)
		if not transition.accepted then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		return {
			accepted = false,
			reason = updateResult.reason or "tool_loadout_select_failed",
			selectedBySlot = {},
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		selectedBySlot = TinyfolkToolLoadoutState.GetSelectedLoadout(updateResult.data, requesterRole),
	}
end

local function buildEntryPayload(player: Player, operationId: any, catalog: any?, nowAt: any): any
	local requesterRole = getRole(player)
	if requesterRole ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			payload = nil,
		}
	end
	local profileData = readProfileData(player)
	if profileData == nil then
		return {
			accepted = false,
			reason = "player_profile_not_loaded",
			payload = nil,
		}
	end

	local selectedBySlot = TinyfolkToolLoadoutState.GetSelectedLoadout(profileData, requesterRole)
	return TinyfolkToolEntryPayload.Build({
		ownerUserId = player.UserId,
		operationId = operationId,
		selectedBySlot = selectedBySlot,
		catalog = catalog,
		now = nowAt,
		loadoutStateVersion = 1,
	})
end

_G._TinyfolkToolLoadoutService_QueryAPI = {
	SelectLoadout = function(player: Player, selectedToolIds: any, _catalog: any?): any
		return selectLoadout(player, selectedToolIds, CANONICAL_CATALOG)
	end,
	GetSelectedLoadout = function(player: Player): any
		local requesterRole = getRole(player)
		if requesterRole ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
			return {}
		end
		local profileData = readProfileData(player)
		if profileData == nil then
			return {}
		end
		return TinyfolkToolLoadoutState.GetSelectedLoadout(profileData, requesterRole)
	end,
	GetDefaultLoadout = function(player: Player, _catalog: any?): any
		local requesterRole = getRole(player)
		if requesterRole ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
			return {}
		end
		local profileData = readProfileData(player)
		return TinyfolkToolLoadoutState.BuildDefaultLoadout(profileData or {}, requesterRole, CANONICAL_CATALOG)
	end,
	BuildEntryPayload = function(player: Player, operationId: any, _catalog: any?, nowAt: any): any
		return buildEntryPayload(player, operationId, CANONICAL_CATALOG, nowAt)
	end,

	-- Explicit test/internal seam. Do not use in public/external request paths.
	SelectLoadoutForTests = function(player: Player, selectedToolIds: any, catalogOverride: any?): any
		return selectLoadout(player, selectedToolIds, catalogOverride)
	end,
	-- Explicit test/internal seam. Do not use in public/external request paths.
	BuildEntryPayloadForTests = function(player: Player, operationId: any, catalogOverride: any?, nowAt: any): any
		return buildEntryPayload(player, operationId, catalogOverride, nowAt)
	end,
}

return TinyfolkToolLoadoutService
