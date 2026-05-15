--!strict

local EscapeConfig: any = {}

EscapeConfig.EscapeRouteNamePrefix = "EscapeRoute_"
EscapeConfig.DefaultEscapeRouteId = "EscapeRoute_A"
EscapeConfig.TinyfolkReturnPointName = "TinyfolkReturnPoint"
EscapeConfig.TinyfolkWorldFolderPath = { "Map", "TinyfolkWorld" }

EscapeConfig.TriggerRadiusStuds = 10
EscapeConfig.RequestCooldownSeconds = 0.15

EscapeConfig.TraversalGapBlockStartupSeconds = 1
EscapeConfig.TraversalGapBlockActiveSeconds = 4
EscapeConfig.TraversalGapBlockRequestCooldownSeconds = 0.25

EscapeConfig.ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed"
EscapeConfig.RouteTypeAttribute = "RouteType"
EscapeConfig.CrossingPhaseAttribute = "CrossingPhase"
EscapeConfig.RequiredCrossingPhase = "MidCrossing"
EscapeConfig.SafeZoneAttribute = "InSafeZone"
EscapeConfig.TraversalGapBlockStateAttribute = "TraversalGapBlockState"
EscapeConfig.TraversalGapBlockStartupEndsAtAttribute = "TraversalGapBlockStartupEndsAt"
EscapeConfig.TraversalGapBlockActiveEndsAtAttribute = "TraversalGapBlockActiveEndsAt"
EscapeConfig.TraversalGapBlockExpiresAtAttribute = "TraversalGapBlockExpiresAt"
EscapeConfig.TraversalGapBlockedByUserIdAttribute = "TraversalGapBlockedByUserId"
EscapeConfig.TraversalGapBlockExemptAttribute = "TraversalGapBlockExempt"

EscapeConfig.SupportedThroughGapRouteTypes = {
	TraversalGap = true,
}

return EscapeConfig
