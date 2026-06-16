--!nocheck

local RealmPermissionConfig = require("../src/ReplicatedStorage/Shared/Config/RealmPermissionConfig")
local RealmPermissionState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmPermissionState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local publicAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.Public,
	entryType = "direct_invite",
	requesterUserIds = { 1001 },
})
assertEqual(publicAdmission.accepted, true, "public mode accepts admission")
assertEqual(publicAdmission.reason, RealmPermissionConfig.Reasons.Accepted, "public mode accepted reason")

local raidAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.RaidEnabled,
	entryType = "standard",
	requesterUserIds = { 1001 },
})
assertEqual(raidAdmission.accepted, true, "raid_enabled mode accepts admission")
assertEqual(raidAdmission.reason, RealmPermissionConfig.Reasons.Accepted, "raid_enabled accepted reason")

local lockedAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.Locked,
	entryType = "direct_invite",
	requesterUserIds = { 1001 },
})
assertEqual(lockedAdmission.accepted, false, "locked mode rejects admission")
assertEqual(lockedAdmission.reason, RealmPermissionConfig.Reasons.Locked, "locked rejection reason")

local inviteDenied = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.InviteOnly,
	entryType = "direct_invite",
	requesterUserIds = { 1001 },
	inviteAllowlistUserIds = { 2002 },
})
assertEqual(inviteDenied.accepted, false, "invite_only rejects non-allowlisted user")
assertEqual(inviteDenied.reason, RealmPermissionConfig.Reasons.NotInvited, "invite_only not invited reason")

local inviteAccepted = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.InviteOnly,
	entryType = "direct_invite",
	requesterUserIds = { 1001, 1002 },
	inviteAllowlistUserIds = { 1001, 1002 },
})
assertEqual(inviteAccepted.accepted, true, "invite_only accepts allowlisted party")
assertEqual(inviteAccepted.reason, RealmPermissionConfig.Reasons.Accepted, "invite_only accepted reason")

local inviteStandardRejected = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.InviteOnly,
	entryType = "standard",
	requesterUserIds = { 1001 },
	inviteAllowlistUserIds = { 1001 },
})
assertEqual(inviteStandardRejected.accepted, false, "invite_only rejects standard entry")
assertEqual(
	inviteStandardRejected.reason,
	RealmPermissionConfig.Reasons.InviteOnly,
	"invite_only standard rejection reason"
)

local friendsDenied = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.FriendsOnly,
	entryType = "direct_invite",
	requesterUserIds = { 1001 },
	realmOwnerUserId = 9001,
	isFriendsWithOwner = function(_ownerUserId: number, _requesterUserId: number): boolean
		return false
	end,
})
assertEqual(friendsDenied.accepted, false, "friends_only rejects non-friend")
assertEqual(friendsDenied.reason, RealmPermissionConfig.Reasons.NotFriend, "friends_only not friend reason")

local friendsAccepted = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.FriendsOnly,
	entryType = "direct_invite",
	requesterUserIds = { 1001 },
	realmOwnerUserId = 9001,
	isFriendsWithOwner = function(_ownerUserId: number, _requesterUserId: number): boolean
		return true
	end,
})
assertEqual(friendsAccepted.accepted, true, "friends_only accepts friend")
assertEqual(friendsAccepted.reason, RealmPermissionConfig.Reasons.Accepted, "friends_only accepted reason")

local resolverProbeInvite = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.InviteOnly,
	resolverProbe = true,
})
assertEqual(resolverProbeInvite.accepted, true, "resolver probe accepts invite_only target resolution")
assertEqual(resolverProbeInvite.reason, RealmPermissionConfig.Reasons.Accepted, "resolver probe invite_only reason")

local invalidAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = "mystery_mode",
	entryType = "direct_invite",
})
assertEqual(invalidAdmission.accepted, false, "invalid mode rejects admission")
assertEqual(invalidAdmission.reason, RealmPermissionConfig.Reasons.ModeInvalid, "invalid mode rejection reason")

local defaultAdmission = RealmPermissionState.EvaluateAdmission({
	entryType = "direct_invite",
})
assertEqual(defaultAdmission.accepted, true, "missing mode defaults to public")
assertEqual(defaultAdmission.reason, RealmPermissionConfig.Reasons.Accepted, "default mode accepted reason")

assertEqual(
	RealmPermissionState.NormalizeRegistryAccessMode("private"),
	RealmPermissionConfig.Modes.Locked,
	"registry private maps to locked"
)
assertEqual(
	RealmPermissionState.NormalizeRegistryAccessMode("public"),
	RealmPermissionConfig.Modes.Public,
	"registry public maps to public"
)
assertEqual(
	RealmPermissionState.NormalizeRegistryAccessMode("invite_only"),
	RealmPermissionConfig.Modes.InviteOnly,
	"registry invite_only maps to invite_only"
)
assertEqual(
	RealmPermissionState.ToRegistryAccessMode(RealmPermissionConfig.Modes.Locked),
	"private",
	"locked maps to private registry mode"
)
assertEqual(
	RealmPermissionState.ToRegistryAccessMode(RealmPermissionConfig.Modes.RaidEnabled),
	"raid_enabled",
	"raid_enabled maps to registry mode"
)
assertEqual(RealmPermissionState.IsDiscoverableRegistryAccessMode("raid_enabled"), true, "raid_enabled is discoverable")
assertEqual(RealmPermissionState.ParseRealmOwnerUserId("giant_realm_9001"), 9001, "parse realm owner user id")

print("realm_permission_state: all checks passed")
