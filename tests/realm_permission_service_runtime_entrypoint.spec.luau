--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local RealmPermissionConfig = require("../src/ReplicatedStorage/Shared/Config/RealmPermissionConfig")
local globalEnv: any = getfenv()

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}
	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end
	function node:WaitForChild(childName: string): any
		return self._Children[childName]
	end
	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		child.Parent = parent
	end
end

local configFolder = makeNode("Config")
addChild(configFolder, "RealmPermissionConfig", "../../ReplicatedStorage/Shared/Config/RealmPermissionConfig")

local giantRealmFolder = makeNode("GiantRealm")
addChild(giantRealmFolder, "RealmPermissionState", "../../ReplicatedStorage/Shared/GiantRealm/RealmPermissionState")
addChild(giantRealmFolder, "LiveRealmHubRouting", "../../ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	return nil
end

game = fakeGame

local registryRefreshCalls = {}
local availability = {
	{
		realmId = "giant_realm_9001",
		ownerUserId = 9001,
		privateServerId = "ps-9001",
		accessMode = "public",
		playerCount = 1,
		capacity = 8,
		dangerRating = 0.5,
		lifecycle = "active",
		isAvailable = true,
		updatedAt = 100,
	},
	{
		realmId = "giant_realm_9002",
		ownerUserId = 9002,
		privateServerId = "ps-9002",
		accessMode = "private",
		playerCount = 2,
		capacity = 8,
		dangerRating = 0.7,
		lifecycle = "active",
		isAvailable = true,
		updatedAt = 101,
	},
}

local serviceFactory = require("../src/ServerScriptService/Services/RealmPermissionService.server")
local service = serviceFactory(fakeGame, {
	listLiveRealmAvailability = function(_limit: number?, _at: number?): { any }
		return availability
	end,
	liveRegistryApi = {
		RefreshActiveRealm = function(input: any): any
			table.insert(registryRefreshCalls, input)
			return { accepted = true, reason = "accepted" }
		end,
	},
	isFriendsWithOwner = function(ownerUserId: number, requesterUserId: number): boolean
		return ownerUserId == 9003 and requesterUserId == 4401
	end,
})

local permissionApi = globalEnv._RealmPermissionService_QueryAPI
assertEqual(type(permissionApi), "table", "permission query api published")
assertEqual(type(permissionApi.GetRealmAccessMode), "function", "get mode function published")
assertEqual(type(permissionApi.EvaluateAdmissionForRealm), "function", "evaluate function published")
assertEqual(type(permissionApi.SetOwnerRealmAccessMode), "function", "owner setter published")

assertEqual(
	permissionApi.GetRealmAccessMode("giant_realm_9001"),
	RealmPermissionConfig.Modes.Public,
	"hub public realm mode"
)
assertEqual(
	permissionApi.GetRealmAccessMode("giant_realm_9002"),
	RealmPermissionConfig.Modes.Locked,
	"hub private realm maps to locked"
)
assertEqual(
	permissionApi.GetRealmAccessMode("giant_realm_missing"),
	RealmPermissionConfig.Modes.Public,
	"missing realm defaults to public"
)
assertEqual(permissionApi.GetRegistryAccessMode("giant_realm_9002"), "private", "registry mode maps locked to private")

local publicAdmission = permissionApi.EvaluateAdmissionForRealm("giant_realm_9001", {
	entryType = "direct_invite",
	requesterUserIds = { 4401 },
})
assertEqual(publicAdmission.accepted, true, "public realm admission accepted")
assertEqual(publicAdmission.reason, RealmPermissionConfig.Reasons.Accepted, "public realm admission reason")

local lockedAdmission = permissionApi.EvaluateAdmissionForRealm("giant_realm_9002", {
	entryType = "direct_invite",
	requesterUserIds = { 4401 },
})
assertEqual(lockedAdmission.accepted, false, "private/locked realm admission rejected")
assertEqual(lockedAdmission.reason, RealmPermissionConfig.Reasons.Locked, "private/locked realm rejection reason")

local sessionSet = permissionApi.SetSessionRealmAccessMode("giant_realm_9002", "raid_enabled")
assertEqual(sessionSet.accepted, true, "session mode override accepted")
assertEqual(
	permissionApi.GetRealmAccessMode("giant_realm_9002"),
	RealmPermissionConfig.Modes.RaidEnabled,
	"session override replaces hub mode"
)
local raidAdmission = permissionApi.EvaluateAdmissionForRealm("giant_realm_9002", {
	entryType = "direct_invite",
	requesterUserIds = { 4401 },
})
assertEqual(raidAdmission.accepted, true, "session raid_enabled admission accepted")

local ownerSet = permissionApi.SetOwnerRealmAccessMode(9002, "invite_only")
assertEqual(ownerSet.accepted, true, "owner access mode set accepted")
assertEqual(#registryRefreshCalls, 1, "owner setter publishes registry refresh")
assertEqual(registryRefreshCalls[1].ownerUserId, 9002, "registry refresh owner user id")
assertEqual(registryRefreshCalls[1].accessMode, "invite_only", "registry refresh access mode")

permissionApi.AddInviteAllowlistUser("giant_realm_9002", 4401)
local inviteDenied = permissionApi.EvaluateAdmissionForRealm("giant_realm_9002", {
	entryType = "direct_invite",
	requesterUserIds = { 4402 },
})
assertEqual(inviteDenied.accepted, false, "invite_only rejects non-allowlisted user")
assertEqual(inviteDenied.reason, RealmPermissionConfig.Reasons.NotInvited, "invite_only not invited reason")

local inviteAccepted = permissionApi.EvaluateAdmissionForRealm("giant_realm_9002", {
	entryType = "direct_invite",
	requesterUserIds = { 4401 },
})
assertEqual(inviteAccepted.accepted, true, "invite_only accepts allowlisted user")

permissionApi.SetSessionRealmAccessMode("giant_realm_9003", "friends_only")
local friendsAccepted = permissionApi.EvaluateAdmissionForRealm("giant_realm_9003", {
	entryType = "direct_invite",
	requesterUserIds = { 4401 },
})
assertEqual(friendsAccepted.accepted, true, "friends_only accepts friend via checker")

local friendsDenied = permissionApi.EvaluateAdmissionForRealm("giant_realm_9003", {
	entryType = "direct_invite",
	requesterUserIds = { 4402 },
})
assertEqual(friendsDenied.accepted, false, "friends_only rejects non-friend")
assertEqual(friendsDenied.reason, RealmPermissionConfig.Reasons.NotFriend, "friends_only not friend reason")

service.ResetForTests()
permissionApi.ConfigureForTests({
	listLiveRealmAvailability = function(_limit: number?, _at: number?): { any }
		return availability
	end,
	liveRegistryApi = {
		RefreshActiveRealm = function(input: any): any
			table.insert(registryRefreshCalls, input)
			return { accepted = true, reason = "accepted" }
		end,
	},
})
assertEqual(
	permissionApi.GetRealmAccessMode("giant_realm_9002"),
	RealmPermissionConfig.Modes.Locked,
	"reset clears session override and restores hub mode"
)

print("realm_permission_service_runtime_entrypoint: all checks passed")
