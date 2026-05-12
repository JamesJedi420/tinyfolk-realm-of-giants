--!strict

local GiantBuildModeConfig: any = {}

-- Remote name for giant structure placement requests.
-- This remote remains isolated from ConstructionBuildRequest and DistrictPlacementRequest.
GiantBuildModeConfig.StructurePlacementRemoteName = "GiantStructurePlacementRequest"
GiantBuildModeConfig.StructureCatalogModuleName = "GiantStructureCatalog"

GiantBuildModeConfig.RequestCooldownSeconds = 0.2

-- Validation limits for deterministic payload boundary checks.
GiantBuildModeConfig.MaxWorldCoordinateStuds = 8192
GiantBuildModeConfig.MaxHalfExtentStuds = 512

return GiantBuildModeConfig
