--!strict

local ModerationReportConfig: any = {}

ModerationReportConfig.RequestCooldownSeconds = 0.5
ModerationReportConfig.AffordanceRefreshSeconds = 1
ModerationReportConfig.MaxRecentEvents = 25
ModerationReportConfig.MaxExportRecords = 50

ModerationReportConfig.TargetRealmIdAttribute = "GiantRealmId"
ModerationReportConfig.TargetRealmOwnerUserIdAttribute = "GiantRealmOwnerUserId"

ModerationReportConfig.EventLogCategory = "moderation_report"

ModerationReportConfig.SurfaceKinds = {
	Capture = "capture",
	CustodyTransfer = "custody_transfer",
	Ransom = "ransom",
	RepeatedBlocking = "repeated_blocking",
	RescueBlocking = "rescue_blocking",
}

ModerationReportConfig.Remotes = {
	RequestExport = "ModerationReportRequestExport",
}

ModerationReportConfig.StateAttributes = {
	AffordanceAvailable = "ModerationReportAffordanceAvailable",
	AffordanceSurfaces = "ModerationReportAffordanceSurfaces",
	LastExportAt = "ModerationReportLastExportAt",
	LastExportReportId = "ModerationReportLastExportReportId",
}

ModerationReportConfig.ReportEventCategories = {
	"capture",
	"custody_transfer",
	"ransom_board",
	"repeated_targeting_abuse",
	"rescue_contract",
	"moderation_report",
}

ModerationReportConfig.BlockedMetadataKeys = {
	"token",
	"profileToken",
	"accessToken",
	"refreshToken",
	"sessionToken",
	"secureToken",
	"password",
	"email",
	"phone",
	"displayName",
	"username",
	"privateProfileData",
}

ModerationReportConfig.RescueBlockedReason = "escape_action_blocked"

return ModerationReportConfig
