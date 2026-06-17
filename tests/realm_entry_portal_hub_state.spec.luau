--!strict

local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
local RealmEntryPortalConfig = require("../src/ReplicatedStorage/Shared/Config/RealmEntryPortalConfig")
local RealmEntryPortalHubState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmEntryPortalHubState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local availability = {
	{
		realmId = "giant_realm_9001",
		ownerUserId = 9001,
		privateServerId = "ps-live-9001",
		accessMode = LiveRealmRegistryState.AccessMode.Private,
		playerCount = 2,
		capacity = 8,
		isAvailable = true,
		updatedAt = 100,
	},
	{
		realmId = "giant_realm_9002",
		ownerUserId = 9002,
		privateServerId = "giant_realm_ps_9002",
		accessMode = LiveRealmRegistryState.AccessMode.Public,
		playerCount = 1,
		capacity = 8,
		isAvailable = true,
		updatedAt = 90,
	},
	{
		realmId = "giant_realm_9003",
		ownerUserId = 9003,
		privateServerId = "ps-live-9003",
		accessMode = LiveRealmRegistryState.AccessMode.RaidEnabled,
		playerCount = 1,
		capacity = 8,
		isAvailable = true,
		updatedAt = 80,
	},
}

local portalList = RealmEntryPortalHubState.ProjectListings({
	availability = availability,
	ownerDisplayNames = { [9002] = "Portal Giant" },
	entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
	limit = 10,
})
assertTrue(portalList.accepted == true, "portal list accepted")
assertEqual(#portalList.listings, 2, "portal lists public and raid_enabled realms")
assertEqual(portalList.listings[1].realmId, "giant_realm_9002", "portal sorted public realm first")
assertEqual(portalList.listings[1].entryRole, RealmEntryPortalConfig.EntryRoles.Guest, "portal default guest role")
assertTrue(portalList.listings[1].isEnterable == true, "public realm enterable")

local raidList = RealmEntryPortalHubState.ProjectListings({
	availability = availability,
	entryMethod = RealmEntryPortalConfig.EntryMethods.Raid,
	limit = 10,
})
assertEqual(#raidList.listings, 2, "raid method lists public and raid_enabled")

local entryPlan = RealmEntryPortalHubState.ResolveEntryRequest({
	entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
	targetRealmId = "giant_realm_9002",
	availability = availability,
})
assertTrue(entryPlan.accepted == true, "portal entry plan accepted")
assertEqual(entryPlan.entryRole, RealmEntryPortalConfig.EntryRoles.Guest, "portal entry guest role")
assertEqual(entryPlan.admissionEntryType, "standard", "portal standard admission")
assertEqual(entryPlan.assignmentBeginOperation, "begin_party_admission", "portal party admission assignment")
assertEqual(entryPlan.locationTransitReason, "party_admission", "portal party admission transit")

local raidPlan = RealmEntryPortalHubState.ResolveEntryRequest({
	entryMethod = RealmEntryPortalConfig.EntryMethods.Raid,
	targetRealmId = "giant_realm_9003",
	availability = availability,
})
assertTrue(raidPlan.accepted == true, "raid entry plan accepted")
assertEqual(raidPlan.entryRole, RealmEntryPortalConfig.EntryRoles.Raider, "raid entry raider role")
assertEqual(raidPlan.locationConfirmOperation, "confirm_realm_invader", "raid confirms invader")

local invitePlan = RealmEntryPortalHubState.ResolveEntryRequest({
	entryMethod = RealmEntryPortalConfig.EntryMethods.Invitation,
	targetRealmId = "giant_realm_9002",
	availability = availability,
})
assertEqual(invitePlan.admissionEntryType, "direct_invite", "invitation direct invite admission")

local rejected = RealmEntryPortalHubState.ResolveEntryRequest({
	entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
	targetRealmId = "giant_realm_9001",
	availability = availability,
})
assertEqual(rejected.accepted, false, "private realm rejected")
assertEqual(rejected.reason, "target_realm_not_discoverable", "private realm rejection reason")

local safeOk = select(1, RealmEntryPortalHubState.AssertClientSafeListingRow(portalList.listings[1]))
assertTrue(safeOk == true, "listing row client safe")

print("realm_entry_portal_hub_state: all checks passed")
