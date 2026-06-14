--!strict

local DefensivePropConfig: any = {}

DefensivePropConfig.PropNamePrefix = "DefensiveProp_"
DefensivePropConfig.ZoneNamePrefix = "DefensivePropZone_"
DefensivePropConfig.DefaultPropId = "DefensiveProp_A"
DefensivePropConfig.DefaultZoneId = "DefensivePropZone_A"

DefensivePropConfig.PropsFolderPath = { "Map", "DefensiveProps" }
DefensivePropConfig.ZonesFolderPath = { "Map", "DefensivePropZones" }
DefensivePropConfig.GiantRoutesFolderPath = { "Map", "GiantRoutes" }

DefensivePropConfig.DropInteractionRangeStuds = 12
DefensivePropConfig.BreakInteractionRangeStuds = 14
DefensivePropConfig.DropRequestCooldownSeconds = 0.25
DefensivePropConfig.BreakRequestCooldownSeconds = 0.25
DefensivePropConfig.DropRechargeSeconds = 8
DefensivePropConfig.MaxActivePropsPerTinyfolk = 1

DefensivePropConfig.BarrierStartupSeconds = 1
DefensivePropConfig.BarrierActiveSeconds = 5
DefensivePropConfig.ObstacleDurationSeconds = 12
DefensivePropConfig.BreakDurationSeconds = 2
DefensivePropConfig.ResetDurationSeconds = 6

DefensivePropConfig.BarrierContactRadiusStuds = 8
DefensivePropConfig.BarrierContactStaggerSeconds = 0.75
DefensivePropConfig.BarrierContactCooldownSeconds = 1.5
DefensivePropConfig.GiantBarrierContactScanIntervalSeconds = 0.25

DefensivePropConfig.RescueDropAllyRadiusStuds = 24

DefensivePropConfig.PropTypeAttribute = "DefensivePropType"
DefensivePropConfig.ZoneIdAttribute = "DefensivePropZoneId"
DefensivePropConfig.EnabledAttribute = "DefensivePropEnabled"

DefensivePropConfig.Attributes = {
	State = "DefensivePropState",
	PropType = "DefensivePropType",
	ZoneId = "DefensivePropZoneId",
	DroppedByUserId = "DefensivePropDroppedByUserId",
	DroppedAt = "DefensivePropDroppedAt",
	BarrierStartupEndsAt = "DefensivePropBarrierStartupEndsAt",
	BarrierActiveEndsAt = "DefensivePropBarrierActiveEndsAt",
	ObstacleExpiresAt = "DefensivePropObstacleExpiresAt",
	BreakStartedAt = "DefensivePropBreakStartedAt",
	BreakEndsAt = "DefensivePropBreakEndsAt",
	BrokenByUserId = "DefensivePropBrokenByUserId",
	BrokenAt = "DefensivePropBrokenAt",
	ResetEndsAt = "DefensivePropResetEndsAt",
	GiantBarrierStaggerActive = "GiantBarrierStaggerActive",
	GiantBarrierStaggerUntil = "GiantBarrierStaggerUntil",
	GiantBarrierStaggerPropId = "GiantBarrierStaggerPropId",
}

DefensivePropConfig.PropTypes = {
	shelf = {
		displayName = "Shelf",
		barrierActiveSeconds = 6,
	},
	plank = {
		displayName = "Plank",
		barrierStartupSeconds = 0.75,
	},
	curtain = { displayName = "Curtain" },
	tray = { displayName = "Tray" },
	ladder = { displayName = "Ladder" },
	rope_gate = {
		displayName = "Rope Gate",
		barrierContactStaggerSeconds = 1,
	},
	loose_board = { displayName = "Loose Board" },
	crate = { displayName = "Crate" },
}

DefensivePropConfig.Status = {
	Ready = "Ready",
	Dropped = "Dropped",
	Blocked = "Blocked",
	Broken = "Broken",
	Resetting = "Resetting",
	Disabled = "Disabled",
}

return DefensivePropConfig
