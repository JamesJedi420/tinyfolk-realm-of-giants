--!strict

local GrabConfig = {}

GrabConfig.GrabRangeStuds = 18
GrabConfig.PlaceRangeStuds = 14
GrabConfig.DefaultPlaceDistanceStuds = 8
GrabConfig.ClientTargetingRangeStuds = 24
GrabConfig.ClientPlaceDistanceStuds = 8
GrabConfig.RequestCooldownSeconds = 0.15

GrabConfig.HoldOffset = Vector3.new(0, 6, -6)

GrabConfig.PlaceProbeHeightStuds = 8
GrabConfig.PlaceProbeDepthStuds = 20
GrabConfig.PlaceClearanceSize = Vector3.new(4, 6, 4)
GrabConfig.PlaceYOffsetStuds = 3

return GrabConfig
