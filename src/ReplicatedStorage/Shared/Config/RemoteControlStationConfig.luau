--!strict

local RemoteControlStationConfig: any = {}

RemoteControlStationConfig.StationNamePrefix = "GiantControlStation_"
RemoteControlStationConfig.ZoneNamePrefix = "GiantControlZone_"
RemoteControlStationConfig.DefaultStationId = "GiantControlStation_A"
RemoteControlStationConfig.DefaultZoneId = "GiantControlZone_A"

RemoteControlStationConfig.InteractionRangeStuds = 18
RemoteControlStationConfig.SabotageRangeStuds = 16
RemoteControlStationConfig.RequestCooldownSeconds = 0.2
RemoteControlStationConfig.SabotageTaskDurationSeconds = 1.5

RemoteControlStationConfig.MaxEnergy = 3
RemoteControlStationConfig.InitialEnergy = 3
RemoteControlStationConfig.PressureEnergyCost = 1
RemoteControlStationConfig.EnergyRecoverySeconds = 8
RemoteControlStationConfig.EnergyRecoveryAmount = 1
RemoteControlStationConfig.SabotageEnergyDrain = 1
RemoteControlStationConfig.SabotageLockoutSeconds = 6

RemoteControlStationConfig.BarrierWarningSeconds = 1
RemoteControlStationConfig.BarrierActiveSeconds = 4

RemoteControlStationConfig.Mode = {
	Enter = "enter",
	Exit = "exit",
	Pressure = "pressure",
	Sabotage = "sabotage",
}

RemoteControlStationConfig.BarrierState = {
	Idle = "Idle",
	Warning = "Warning",
	Active = "Active",
	Expired = "Expired",
}

RemoteControlStationConfig.StationActiveOperatorUserIdAttribute = "RemoteControlActiveOperatorUserId"
RemoteControlStationConfig.StationEnergyAttribute = "RemoteControlEnergy"
RemoteControlStationConfig.StationLockoutEndsAtAttribute = "RemoteControlLockoutEndsAt"
RemoteControlStationConfig.StationZoneIdAttribute = "RemoteControlZoneId"
RemoteControlStationConfig.RouteBarrierStateAttribute = "RemoteBarrierState"
RemoteControlStationConfig.RouteBarrierWarningEndsAtAttribute = "RemoteBarrierWarningEndsAt"
RemoteControlStationConfig.RouteBarrierActiveEndsAtAttribute = "RemoteBarrierActiveEndsAt"
RemoteControlStationConfig.RouteBarrierExpiresAtAttribute = "RemoteBarrierExpiresAt"
RemoteControlStationConfig.RouteBarrierByUserIdAttribute = "RemoteBarrierByUserId"
RemoteControlStationConfig.RouteBarrierStationIdAttribute = "RemoteBarrierStationId"

return RemoteControlStationConfig
