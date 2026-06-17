--!strict

local TinyfolkHubConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("TinyfolkHubConfig"))
	else (require :: any)("../Config/TinyfolkHubConfig")
local RoleConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("RoleConfig"))
	else (require :: any)("../Config/RoleConfig")
local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("GiantRealm"):WaitForChild("RealmAssignmentProfileState"))
	else (require :: any)("../GiantRealm/RealmAssignmentProfileState")

local TinyfolkHubState: any = {}

export type HubPresenceSnapshot = {
	inHub: boolean,
	locationCategory: string,
	safeZoneProtected: boolean,
	reason: string,
}

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

function TinyfolkHubState.ResolveTinyfolkSpawnName(preferredSpawnName: any, legacySpawnName: any): string
	if isNonEmptyString(preferredSpawnName) then
		return preferredSpawnName :: string
	end
	if isNonEmptyString(legacySpawnName) then
		return legacySpawnName :: string
	end
	return TinyfolkHubConfig.HubSpawnName
end

function TinyfolkHubState.ShouldApplyHubSafeZone(roleName: any, locationCategory: any): boolean
	if roleName ~= RoleConfig.Roles.Tinyfolk then
		return false
	end
	if locationCategory == RealmAssignmentProfileState.LocationCategory.GiantRealm then
		return false
	end
	if locationCategory == RealmAssignmentProfileState.LocationCategory.TransferInFlight then
		return false
	end
	return locationCategory == RealmAssignmentProfileState.LocationCategory.SharedHub
end

function TinyfolkHubState.ResolveActivityEligibility(
	activity: any,
	roleName: any,
	locationCategory: any
): (boolean, string)
	if roleName ~= RoleConfig.Roles.Tinyfolk then
		return false, "role_not_tinyfolk"
	end

	if not TinyfolkHubState.ShouldApplyHubSafeZone(roleName, locationCategory) then
		return false, "not_in_shared_hub"
	end

	if activity == TinyfolkHubConfig.Activities.RaidBoard then
		return true, "accepted"
	end
	if activity == TinyfolkHubConfig.Activities.Party then
		return true, "accepted"
	end
	if activity == TinyfolkHubConfig.Activities.RealmPortal then
		return true, "accepted"
	end

	return false, "activity_invalid"
end

function TinyfolkHubState.BuildHubPresenceSnapshot(roleName: any, locationCategory: any): HubPresenceSnapshot
	local category = if isNonEmptyString(locationCategory)
		then locationCategory :: string
		else RealmAssignmentProfileState.LocationCategory.SharedHub
	local safeZoneProtected = TinyfolkHubState.ShouldApplyHubSafeZone(roleName, category)
	local inHub = safeZoneProtected

	return {
		inHub = inHub,
		locationCategory = category,
		safeZoneProtected = safeZoneProtected,
		reason = if safeZoneProtected then "shared_hub_present" else "shared_hub_not_active",
	}
end

return TinyfolkHubState
