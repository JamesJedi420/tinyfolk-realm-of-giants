--!strict

local TrophyConfig: any = {}

TrophyConfig.MaxRetainedTrophies = 50

TrophyConfig.Kinds = {
	CaptureSuccess = "capture_success",
	ContainmentHeld = "containment_held",
	ContainmentStarvation = "containment_starvation",
	ContainmentEscapeFailure = "containment_escape_failure",
}

TrophyConfig.DisplayTitlesByKind = {
	capture_success = "Capture Secured",
	containment_held = "Containment Completed",
	containment_starvation = "Starvation Release",
	containment_escape_failure = "Escape Denied",
}

TrophyConfig.StateAttributes = {
	Count = "GiantTrophyCount",
	LatestSummary = "GiantTrophyLatestSummary",
	LatestKind = "GiantTrophyLatestKind",
}

return TrophyConfig
