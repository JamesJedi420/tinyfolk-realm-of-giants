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

RealmPermissionConfig.EntryTypes = {
	Standard = "standard",
	DirectInvite = "direct_invite",
	RescueContract = "rescue_contract",
}

RealmPermissionConfig.Reasons = {
	Accepted = "accepted",
	Locked = "realm_access_locked",
	InviteOnly = "realm_access_invite_only",
	FriendsOnly = "realm_access_friends_only",
	NotInvited = "realm_access_not_invited",
	NotFriend = "realm_access_not_friend",
	UnsupportedMode = "realm_access_mode_unsupported",
	ModeInvalid = "realm_access_mode_invalid",
	OwnerMismatch = "realm_access_owner_mismatch",
	OwnerUnavailable = "realm_access_owner_unavailable",
}

RealmPermissionConfig.OwnerActions = {
	SetAccessMode = "set_access_mode",
	AddInvite = "add_invite",
	RemoveInvite = "remove_invite",
}

RealmPermissionConfig.Remotes = {
	OwnerRequest = "RealmPermissionOwnerRequest",
	OwnerResponse = "RealmPermissionOwnerResponse",
}

RealmPermissionConfig.RequestCooldownSeconds = 0.5

return RealmPermissionConfig
