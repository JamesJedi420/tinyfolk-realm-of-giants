--!nocheck

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local TinyfolkHubConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkHubConfig")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")
local TinyfolkHubState = require("../src/ReplicatedStorage/Shared/TinyfolkHub/TinyfolkHubState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

assertEqual(
	TinyfolkHubState.ResolveTinyfolkSpawnName(TinyfolkHubConfig.HubSpawnName, TinyfolkHubConfig.LegacyTinyfolkSpawnName),
	TinyfolkHubConfig.HubSpawnName,
	"hub spawn name prefers hub spawn"
)

assertTrue(
	TinyfolkHubState.ShouldApplyHubSafeZone(
		RoleConfig.Roles.Tinyfolk,
		RealmAssignmentProfileState.LocationCategory.SharedHub
	),
	"tinyfolk shared hub gets safe zone"
)

assertEqual(
	TinyfolkHubState.ShouldApplyHubSafeZone(
		RoleConfig.Roles.Tinyfolk,
		RealmAssignmentProfileState.LocationCategory.GiantRealm
	),
	false,
	"tinyfolk giant realm assignment skips hub safe zone"
)

assertEqual(
	TinyfolkHubState.ShouldApplyHubSafeZone(
		RoleConfig.Roles.Giant,
		RealmAssignmentProfileState.LocationCategory.SharedHub
	),
	false,
	"giant role never gets hub safe zone"
)

local raidAccepted, raidReason = TinyfolkHubState.ResolveActivityEligibility(
	TinyfolkHubConfig.Activities.RaidBoard,
	RoleConfig.Roles.Tinyfolk,
	RealmAssignmentProfileState.LocationCategory.SharedHub
)
assertTrue(raidAccepted, "raid board activity allowed in hub")
assertEqual(raidReason, "accepted", "raid board activity reason")

local partyDenied, partyReason = TinyfolkHubState.ResolveActivityEligibility(
	TinyfolkHubConfig.Activities.Party,
	RoleConfig.Roles.Tinyfolk,
	RealmAssignmentProfileState.LocationCategory.GiantRealm
)
assertEqual(partyDenied, false, "party activity denied outside hub")
assertEqual(partyReason, "not_in_shared_hub", "party activity denial reason")

local presence = TinyfolkHubState.BuildHubPresenceSnapshot(
	RoleConfig.Roles.Tinyfolk,
	RealmAssignmentProfileState.LocationCategory.SharedHub
)
assertTrue(presence.inHub, "presence marks in hub")
assertTrue(presence.safeZoneProtected, "presence marks safe zone protected")
assertEqual(presence.locationCategory, RealmAssignmentProfileState.LocationCategory.SharedHub, "presence category")

print("tinyfolk_hub_state: all checks passed")
