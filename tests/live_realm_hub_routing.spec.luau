--!strict

local LiveRealmHubRouting = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")
local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")

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
		accessMode = LiveRealmRegistryState.AccessMode.Public,
		playerCount = 1,
		capacity = 8,
		dangerRating = 0.4,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
		isAvailable = true,
		updatedAt = 100,
	},
	{
		realmId = "giant_realm_9003",
		ownerUserId = 9003,
		privateServerId = "ps-live-9003",
		accessMode = LiveRealmRegistryState.AccessMode.Private,
		playerCount = 0,
		capacity = 8,
		dangerRating = 0.8,
		lifecycle = LiveRealmRegistryState.Lifecycle.Expired,
		isAvailable = false,
		updatedAt = 100,
	},
}

local direct = LiveRealmHubRouting.ResolveAdmissionTarget({
	targetRealmId = "giant_realm_9001",
}, availability)
assertTrue(direct.accepted, "direct hub target accepted")
assertEqual(direct.targetRealmId, "giant_realm_9001", "direct hub target realm id")
assertEqual(direct.privateServerId, "ps-live-9001", "direct hub private server id")
assertEqual(direct.resolverPath, "hub_direct", "direct hub resolver path")

local offline = LiveRealmHubRouting.ResolveAdmissionTarget({
	targetRealmId = "giant_realm_9003",
}, availability)
assertEqual(offline.accepted, false, "offline hub target rejected")
assertEqual(offline.reason, "target_realm_unavailable", "offline hub target reason")
assertEqual(offline.resolverPath, "hub_direct_offline", "offline hub resolver path")

local raidBoard = LiveRealmHubRouting.ResolveAdmissionTarget({}, availability)
assertTrue(raidBoard.accepted, "raid board target accepted")
assertEqual(raidBoard.targetRealmId, "giant_realm_9001", "raid board picks highest danger available")
assertEqual(raidBoard.resolverPath, "hub_raid_board", "raid board resolver path")

assertEqual(
	LiveRealmHubRouting.ResolveTeleportAccessCode(availability[1]),
	"ps-live-9001",
	"private live access code resolved"
)
assertEqual(
	LiveRealmHubRouting.ResolveTeleportAccessCode(availability[2]),
	nil,
	"public stable fallback does not resolve teleport access code"
)
assertEqual(
	LiveRealmHubRouting.ResolveTeleportAccessCode(availability[3]),
	nil,
	"offline realm does not resolve teleport access code"
)

print("live_realm_hub_routing: all checks passed")
