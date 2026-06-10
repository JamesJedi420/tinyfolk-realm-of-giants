--!strict

local TrophyConfig: any = {}

TrophyConfig.MaxRetainedTrophies = 50
TrophyConfig.CaseDisplayMaxEntries = 5
TrophyConfig.TrophyCaseSurfaceAttribute = "TrophyCaseSurface"
TrophyConfig.AnonymousTargetDisplayToken = "Private Visitor"

TrophyConfig.Kinds = {
	CaptureSuccess = "capture_success",
	ContainmentHeld = "containment_held",
	ContainmentStarvation = "containment_starvation",
	ContainmentEscapeFailure = "containment_escape_failure",
	RaidDefenseWin = "raid_defense_win",
	NegotiatedRelease = "negotiated_release",
}

TrophyConfig.DisplayTitlesByKind = {
	capture_success = "Capture Secured",
	containment_held = "Containment Completed",
	containment_starvation = "Starvation Release",
	containment_escape_failure = "Escape Denied",
	raid_defense_win = "Intruder Snared",
	negotiated_release = "Negotiated Release",
}

TrophyConfig.StateAttributes = {
	Count = "GiantTrophyCount",
	LatestSummary = "GiantTrophyLatestSummary",
	LatestKind = "GiantTrophyLatestKind",
	CaseHeader = "GiantTrophyCaseHeader",
	CaseSummary = "GiantTrophyCaseSummary",
	CaseUpdatedAt = "GiantTrophyCaseUpdatedAt",
}

TrophyConfig.MapSurfaceAttributes = {
	Header = "TrophyCaseHeader",
	Summary = "TrophyCaseSummary",
	Count = "TrophyCaseCount",
	UpdatedAt = "TrophyCaseUpdatedAt",
}

TrophyConfig.DisplayPolicyAttributes = {
	OptOutOfNameDisplay = "TinyfolkTrophyNameOptOut",
}

TrophyConfig.DisplayPolicyRemotes = {
	UpdateRequest = "TrophyDisplayPolicyUpdateRequest",
	UpdateResponse = "TrophyDisplayPolicyUpdateResponse",
}

return TrophyConfig
