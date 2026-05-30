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
EscapeConfig.DashTriggerRadiusStuds = 15 -- Max distance for dash attempts
EscapeConfig.DashCooldownSeconds = 0.2 -- Cooldown for dash attempts

-- Traversal gap block timing/cooldown
EscapeConfig.TraversalGapBlockStartupSeconds = 1 -- Startup phase duration (Tinyfolk can still cross)
EscapeConfig.TraversalGapBlockActiveSeconds = 4 -- Active block duration (Tinyfolk blocked)
EscapeConfig.TraversalGapBlockRequestCooldownSeconds = 0.25 -- Cooldown for block requests

-- Attribute names for route/escape/capture validation
EscapeConfig.ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed" -- If true, route allows through-gap reach
EscapeConfig.RouteTypeAttribute = "RouteType" -- Type of route (e.g., TraversalGap)
EscapeConfig.TinyfolkOnlyRouteAttribute = "TinyfolkOnlyRoute" -- If true, only Tinyfolk may traverse/access the route
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
EscapeConfig.FinalExitManagedAttribute = "FinalExitManaged" -- If true, route participates in the final-exit clock
EscapeConfig.FinalExitPhaseAttribute = "FinalExitPhase" -- Final-exit phase enum projected by EscapeService
EscapeConfig.FinalExitPoweredEndsAtAttribute = "FinalExitPoweredEndsAt" -- Powered phase end timestamp
EscapeConfig.FinalExitOpeningEndsAtAttribute = "FinalExitOpeningEndsAt" -- Opening phase end timestamp
EscapeConfig.FinalExitBlockedEndsAtAttribute = "FinalExitBlockedEndsAt" -- Blocked phase end timestamp
EscapeConfig.FinalExitResolvedAtAttribute = "FinalExitResolvedAt" -- Resolved phase timestamp
EscapeConfig.FinalExitBlockedByUserIdAttribute = "FinalExitBlockedByUserId" -- UserId that triggered final-exit block
EscapeConfig.FallbackEscapeCandidateAttribute = "FallbackEscapeCandidate" -- If true, route is a solo fallback escape candidate
EscapeConfig.FallbackEscapePhaseAttribute = "FallbackEscapePhase" -- Last-Tinyfolk fallback escape phase
EscapeConfig.FallbackEscapeCueBandAttribute = "FallbackEscapeCueBand" -- Coarse cue band for local search
EscapeConfig.FallbackEscapeClosedEndsAtAttribute = "FallbackEscapeClosedEndsAt" -- Giant closure expiry timestamp
EscapeConfig.FallbackEscapeClosedByUserIdAttribute = "FallbackEscapeClosedByUserId" -- UserId that closed fallback route
EscapeConfig.PlayerCreatedRouteAttribute = "PlayerCreatedRoute" -- If true, route metadata is owned by player-created tooling
EscapeConfig.RouteCreatedByUserIdAttribute = "RouteCreatedByUserId" -- UserId of the player who created the route
EscapeConfig.RouteCreationTimestampAttribute = "RouteCreationTimestamp" -- Epoch/clock timestamp when route metadata was authored
EscapeConfig.PlayerCreatedRouteExpiresAtAttribute = "PlayerCreatedRouteExpiresAt" -- Optional expiration timestamp for player-created route metadata
EscapeConfig.RouteEnabledAttribute = "RouteEnabled" -- Attribute that controls route enabled/disabled projection

-- Final exit raid-escalation timings
EscapeConfig.FinalExitPoweredDurationSeconds = 2 -- Delay between objective threshold and opening start
EscapeConfig.FinalExitOpeningDurationSeconds = 3 -- Opening wind-up before route becomes escape-ready
EscapeConfig.FinalExitBlockedDurationSeconds = 4 -- How long a Giant interruption keeps the exit blocked
EscapeConfig.FinalExitReopenDurationSeconds = 2 -- Reopening wind-up after a block expires
EscapeConfig.FallbackEscapeOpenDelaySeconds = 2 -- Delay between last-Tinyfolk activation and fallback opening
EscapeConfig.FallbackEscapeCloseDurationSeconds = 4 -- How long a Giant closure keeps fallback sealed

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
