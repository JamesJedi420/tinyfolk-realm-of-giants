--!strict

local EscapeConfig: any = {}

EscapeConfig.EscapeRouteNamePrefix = "EscapeRoute_"
EscapeConfig.DefaultEscapeRouteId = "EscapeRoute_A"
EscapeConfig.TinyfolkReturnPointName = "TinyfolkReturnPoint"
EscapeConfig.TinyfolkWorldFolderPath = {"Map", "TinyfolkWorld"}

EscapeConfig.TriggerRadiusStuds = 10
EscapeConfig.RequestCooldownSeconds = 0.15

EscapeConfig.ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed"
EscapeConfig.RouteTypeAttribute = "RouteType"
EscapeConfig.CrossingPhaseAttribute = "CrossingPhase"
EscapeConfig.RequiredCrossingPhase = "MidCrossing"
EscapeConfig.SafeZoneAttribute = "InSafeZone"

EscapeConfig.SupportedThroughGapRouteTypes = {
	TraversalGap = true,
}

return EscapeConfig
