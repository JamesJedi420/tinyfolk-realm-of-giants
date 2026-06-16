--!strict

local RealmPermissionConfig: any = {}

RealmPermissionConfig.Modes = {
	Public = "public",
	RaidEnabled = "raid_enabled",
	Locked = "locked",
	InviteOnly = "invite_only",
	FriendsOnly = "friends_only",
}

RealmPermissionConfig.DefaultMode = RealmPermissionConfig.Modes.Public

RealmPermissionConfig.Reasons = {
	Accepted = "accepted",
	Locked = "realm_access_locked",
	InviteOnly = "realm_access_invite_only",
	FriendsOnly = "realm_access_friends_only",
	UnsupportedMode = "realm_access_mode_unsupported",
	ModeInvalid = "realm_access_mode_invalid",
}

return RealmPermissionConfig
