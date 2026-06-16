--!strict

local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
local RaidBoardHubState = require("../src/ReplicatedStorage/Shared/GiantRealm/RaidBoardHubState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local availability = {
	{
		realmId = "giant_realm_9001",
		ownerUserId = 9001,
		privateServerId = "ps-live-9001",
		jobId = "job-9001",
		accessMode = LiveRealmRegistryState.AccessMode.Private,
		playerCount = 2,
		capacity = 8,
		dangerRating = 0.9,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
		isAvailable = true,
		updatedAt = 100,
	},
	{
		realmId = "giant_realm_9002",
		ownerUserId = 9002,
		privateServerId = "giant_realm_ps_9002",
		jobId = "job-9002",
		accessMode = LiveRealmRegistryState.AccessMode.Public,
		playerCount = 1,
		capacity = 8,
		dangerRating = 0.4,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
		isAvailable = true,
		updatedAt = 90,
	},
	{
		realmId = "giant_realm_9003",
		ownerUserId = 9003,
		privateServerId = "ps-live-9003",
		jobId = "job-9003",
		accessMode = LiveRealmRegistryState.AccessMode.InviteOnly,
		playerCount = 1,
		capacity = 8,
		dangerRating = 0.8,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
		isAvailable = true,
		updatedAt = 80,
	},
	{
		realmId = "giant_realm_9005",
		ownerUserId = 9005,
		privateServerId = "ps-live-9005",
		jobId = "job-9005",
		accessMode = LiveRealmRegistryState.AccessMode.RaidEnabled,
		playerCount = 1,
		capacity = 8,
		dangerRating = 0.95,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
		isAvailable = true,
		updatedAt = 85,
	},
	{
		realmId = "giant_realm_9004",
		ownerUserId = 9004,
		privateServerId = "ps-live-9004",
		jobId = "job-9004",
		accessMode = LiveRealmRegistryState.AccessMode.Public,
		playerCount = 0,
		capacity = 8,
		dangerRating = 0.6,
		lifecycle = LiveRealmRegistryState.Lifecycle.Expired,
		isAvailable = false,
		updatedAt = 70,
	},
}

local projected = RaidBoardHubState.ProjectListings({
	availability = availability,
	ownerDisplayNames = {
		[9002] = "Alpha Giant",
		[9005] = "Raid Giant",
	},
	limit = 10,
})
assertTrue(projected.accepted, "projection accepted")
assertEqual(#projected.listings, 2, "public and raid_enabled available listings included")
assertEqual(projected.listings[1].realmId, "giant_realm_9005", "raid_enabled listing sorted first by danger")
assertEqual(projected.listings[1].entryTypeLabel, "Raid Open", "raid_enabled entry type label")
assertEqual(projected.listings[2].realmId, "giant_realm_9002", "public listing realm id")
assertEqual(projected.listings[1].ownerDisplayName, "Raid Giant", "resolved raid owner display name")
assertEqual(projected.listings[1].realmDisplayName, "Raid Giant's Realm", "raid realm display name")
assertEqual(projected.listings[1].rewardTierLabel, "Legendary", "raid reward tier label")
assertTrue(projected.listings[1].isQueueable, "raid_enabled listing queueable")
assertEqual(projected.listings[2].ownerDisplayName, "Alpha Giant", "resolved public owner display name")
assertEqual(projected.listings[2].entryTypeLabel, "Raid", "public entry type label")
assertEqual(projected.listings[2].rewardTierLabel, "Moderate", "public reward tier label")
assertTrue(projected.listings[2].isQueueable, "public listing queueable")

local safeOk, safeReason = RaidBoardHubState.AssertClientSafeListingRow(projected.listings[1])
assertTrue(safeOk, "listing row client safe")
assertEqual(safeReason, nil, "listing row client safe reason")

local unsafeRow = table.clone(projected.listings[1])
unsafeRow.privateServerId = "secret"
local unsafeOk = RaidBoardHubState.AssertClientSafeListingRow(unsafeRow)
assertEqual(unsafeOk, false, "forbidden privateServerId rejected")

assertEqual(RaidBoardHubState.ResolveRewardTierLabel(0.9), "Legendary", "legendary reward tier")
assertEqual(RaidBoardHubState.BuildOwnerDisplayName(42, nil), "Giant 42", "fallback owner display name")

local invalidProjection = RaidBoardHubState.ProjectListings({
	availability = "bad",
})
assertEqual(invalidProjection.accepted, false, "invalid availability rejected")
assertEqual(invalidProjection.reason, "availability_invalid", "invalid availability reason")

print("raid_board_hub_state: all checks passed")
