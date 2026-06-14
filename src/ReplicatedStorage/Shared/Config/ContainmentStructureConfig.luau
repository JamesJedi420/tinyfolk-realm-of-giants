--!strict

local ContainmentStructureConfig: any = {}

ContainmentStructureConfig.StructureNamePrefix = "ContainmentStructure_"
ContainmentStructureConfig.ZoneNamePrefix = "ContainmentStructureZone_"
ContainmentStructureConfig.DefaultStructureId = "ContainmentStructure_A"
ContainmentStructureConfig.DefaultZoneId = "ContainmentStructureZone_A"

ContainmentStructureConfig.StructuresFolderPath = { "Map", "ContainmentStructures" }
ContainmentStructureConfig.ZonesFolderPath = { "Map", "ContainmentStructureZones" }

ContainmentStructureConfig.BuildModeCategory = "containment"
ContainmentStructureConfig.BuildModePlacements = {
	GiantStructure_Containment_Cage_A = {
		structureType = "cage",
		capacity = 2,
		structureSize = { X = 10, Y = 5, Z = 8 },
		zoneSize = { X = 24, Y = 6, Z = 16 },
		escapeInteractionEnabled = true,
	},
	GiantStructure_Containment_Jar_A = {
		structureType = "jar",
		capacity = 1,
		structureSize = { X = 6, Y = 8, Z = 6 },
		zoneSize = { X = 14, Y = 6, Z = 14 },
		escapeInteractionEnabled = true,
	},
}

ContainmentStructureConfig.DefaultCapacity = 1
ContainmentStructureConfig.AssignInteractionRangeStuds = 14
ContainmentStructureConfig.RescueInteractionRangeStuds = 14
ContainmentStructureConfig.ContainmentEscapeProgressRequired = 5
ContainmentStructureConfig.ContainmentEscapeActionCooldownSeconds = 0.35
ContainmentStructureConfig.ContainmentRescueCooldownSeconds = 0.5

ContainmentStructureConfig.StructureTypeAttribute = "ContainmentStructureType"
ContainmentStructureConfig.ZoneIdAttribute = "ContainmentStructureZoneId"
ContainmentStructureConfig.CapacityAttribute = "ContainmentStructureCapacity"
ContainmentStructureConfig.EnabledAttribute = "ContainmentStructureEnabled"
ContainmentStructureConfig.EscapeInteractionAttribute = "ContainmentEscapeInteractionEnabled"

ContainmentStructureConfig.Attributes = {
	State = "ContainmentStructureState",
	StructureType = "ContainmentStructureType",
	ZoneId = "ContainmentStructureZoneId",
	Capacity = "ContainmentStructureCapacity",
	OccupantCount = "ContainmentStructureOccupantCount",
	OccupantUserIds = "ContainmentStructureOccupantUserIds",
	EscapeInteractionEnabled = "ContainmentEscapeInteractionEnabled",
}

ContainmentStructureConfig.PlayerAttributes = {
	EscapeProgress = "ContainmentEscapeProgress",
	EscapeProgressRequired = "ContainmentEscapeProgressRequired",
	EscapeLastReason = "ContainmentEscapeLastReason",
	StructureId = "ContainmentStructureId",
}

ContainmentStructureConfig.StructureTypes = {
	cage = {
		displayName = "Cage",
		defaultCapacity = 2,
		escapeInteractionEnabled = true,
	},
	jar = {
		displayName = "Jar",
		defaultCapacity = 1,
		escapeInteractionEnabled = true,
	},
	tower = { displayName = "Tower", escapeInteractionEnabled = true },
	terrarium = { displayName = "Terrarium", escapeInteractionEnabled = true },
	drawer = { displayName = "Drawer", escapeInteractionEnabled = true },
	birdcage = { displayName = "Birdcage", escapeInteractionEnabled = true },
	glass_box = { displayName = "Glass Box", escapeInteractionEnabled = true },
}

ContainmentStructureConfig.Status = {
	Ready = "Ready",
	Occupied = "Occupied",
	Full = "Full",
	Disabled = "Disabled",
}

return ContainmentStructureConfig
