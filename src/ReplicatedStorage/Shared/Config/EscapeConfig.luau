--!strict

-- EscapeConfig: Central config for escape, safe zone, and traversal-gap/capture attributes
-- Used by EscapeService, ThroughGapValidation, and all validator logic for TIN-76, TIN-185, TIN-186
local EscapeConfig: any = {}

-- Route/escape node naming and folder conventions
EscapeConfig.EscapeRouteNamePrefix = "EscapeRoute_" -- Prefix for all escape route parts
EscapeConfig.DefaultEscapeRouteId = "EscapeRoute_A" -- Default route id for fallback
EscapeConfig.TinyfolkReturnPointName = "TinyfolkReturnPoint" -- Name for Tinyfolk return point
EscapeConfig.TinyfolkWorldFolderPath = { "Map", "TinyfolkWorld" } -- Path to Tinyfolk world folder

-- Escape/interaction radii and cooldowns
EscapeConfig.TriggerRadiusStuds = 10 -- Max distance for escape/block/through-gap attempts
EscapeConfig.RequestCooldownSeconds = 0.15 -- Cooldown for escape attempts

-- Traversal gap block timing/cooldown
EscapeConfig.TraversalGapBlockStartupSeconds = 1 -- Startup phase duration (Tinyfolk can still cross)
EscapeConfig.TraversalGapBlockActiveSeconds = 4 -- Active block duration (Tinyfolk blocked)
EscapeConfig.TraversalGapBlockRequestCooldownSeconds = 0.25 -- Cooldown for block requests

-- Attribute names for route/escape/capture validation
EscapeConfig.ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed" -- If true, route allows through-gap reach
EscapeConfig.RouteTypeAttribute = "RouteType" -- Type of route (e.g., TraversalGap)
EscapeConfig.CrossingPhaseAttribute = "CrossingPhase" -- Phase of Tinyfolk crossing
EscapeConfig.RequiredCrossingPhase = "MidCrossing" -- Required phase for valid crossing
EscapeConfig.SafeZoneAttribute = "InSafeZone" -- If true, route/target is in a safe zone (no capture/block allowed)
EscapeConfig.SafeZoneTypeAttribute = "SafeZoneType" -- Safe-zone classification used by server validation
EscapeConfig.SafeZoneProtectionEndsAtAttribute = "SafeZoneProtectionEndsAt" -- Epoch/clock timestamp for temporary protection expiry
EscapeConfig.TraversalGapBlockStateAttribute = "TraversalGapBlockState" -- Block state enum
EscapeConfig.TraversalGapBlockStartupEndsAtAttribute = "TraversalGapBlockStartupEndsAt" -- Startup phase end time
EscapeConfig.TraversalGapBlockActiveEndsAtAttribute = "TraversalGapBlockActiveEndsAt" -- Active phase end time
EscapeConfig.TraversalGapBlockExpiresAtAttribute = "TraversalGapBlockExpiresAt" -- Block expiration time
EscapeConfig.TraversalGapBlockedByUserIdAttribute = "TraversalGapBlockedByUserId" -- UserId of blocking Giant
EscapeConfig.TraversalGapBlockExemptAttribute = "TraversalGapBlockExempt" -- If true, route is exempt from block

EscapeConfig.SafeZoneTypes = {
	SharedHub = "SharedHub",
	RealmEntry = "RealmEntry",
	RealmExit = "RealmExit",
}

EscapeConfig.SafeZoneAbuseWindowSeconds = 2
EscapeConfig.SafeZoneAbuseThreshold = 3
EscapeConfig.SafeZoneAbuseLockoutSeconds = 1

-- Supported route types for through-gap logic
EscapeConfig.SupportedThroughGapRouteTypes = {
	TraversalGap = true,
}

return EscapeConfig
