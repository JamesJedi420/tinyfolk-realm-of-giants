--!strict

local DistrictPlacementConfig: any = {}

-- Remote name for district placement requests.
-- This remote is distinct from ConstructionBuildRequest.
-- Do not route district placement through ConstructionBuildRequest or ConstructionService.
DistrictPlacementConfig.PlacementRemoteName = "DistrictPlacementRequest"

DistrictPlacementConfig.RequestCooldownSeconds = 0.2

return DistrictPlacementConfig
