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
})
assertEqual(publicAdmission.accepted, true, "public mode accepts admission")
assertEqual(publicAdmission.reason, RealmPermissionConfig.Reasons.Accepted, "public mode accepted reason")

local raidAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.RaidEnabled,
	entryType = "direct_invite",
})
assertEqual(raidAdmission.accepted, true, "raid_enabled mode accepts admission")
assertEqual(raidAdmission.reason, RealmPermissionConfig.Reasons.Accepted, "raid_enabled accepted reason")

local lockedAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.Locked,
	entryType = "direct_invite",
})
assertEqual(lockedAdmission.accepted, false, "locked mode rejects admission")
assertEqual(lockedAdmission.reason, RealmPermissionConfig.Reasons.Locked, "locked rejection reason")

local inviteAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.InviteOnly,
	entryType = "direct_invite",
})
assertEqual(inviteAdmission.accepted, false, "invite_only mode rejects admission")
assertEqual(inviteAdmission.reason, RealmPermissionConfig.Reasons.InviteOnly, "invite_only rejection reason")

local friendsAdmission = RealmPermissionState.EvaluateAdmission({
	accessMode = RealmPermissionConfig.Modes.FriendsOnly,
	entryType = "direct_invite",
})
assertEqual(friendsAdmission.accepted, false, "friends_only mode rejects admission")
assertEqual(friendsAdmission.reason, RealmPermissionConfig.Reasons.FriendsOnly, "friends_only rejection reason")

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

print("realm_permission_state: all checks passed")
