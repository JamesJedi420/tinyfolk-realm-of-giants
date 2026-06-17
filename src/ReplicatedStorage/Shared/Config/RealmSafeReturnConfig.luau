--!strict

local RealmSafeReturnConfig: any = {}

RealmSafeReturnConfig.SourceIds = {
	Escape = "realm_safe_return_escape",
	Timeout = "realm_safe_return_timeout",
	Logout = "realm_safe_return_logout",
	ServerShutdown = "realm_safe_return_server_shutdown",
	GiantDisconnect = "realm_safe_return_giant_disconnect",
	ModerationFallback = "realm_safe_return_moderation",
	JoinResolution = "realm_safe_return_join_resolution",
}

return RealmSafeReturnConfig
