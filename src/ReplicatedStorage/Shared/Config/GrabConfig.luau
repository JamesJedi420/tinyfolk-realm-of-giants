--!strict

local GrabConfig = {}

GrabConfig.GrabRangeStuds = 18
GrabConfig.PlaceRangeStuds = 14
GrabConfig.DefaultPlaceDistanceStuds = 8
GrabConfig.ClientTargetingRangeStuds = 24
GrabConfig.ClientPlaceDistanceStuds = 8
GrabConfig.RequestCooldownSeconds = 0.15
GrabConfig.CounterplayRequired = 3
GrabConfig.CounterplayProgressPerAction = 1
GrabConfig.CounterplayActionCooldownSeconds = 0.25

GrabConfig.HoldOffset = Vector3.new(0, 6, -6)

GrabConfig.CarriedStateAttribute = "CarriedState"
GrabConfig.CarriedByUserIdAttribute = "CarriedByUserId"
GrabConfig.CarriedTargetUserIdAttribute = "CarriedTargetUserId"
GrabConfig.CarriedGrabbedAtAttribute = "CarriedGrabbedAt"
GrabConfig.CarriedCooldownEndsAtAttribute = "CarriedCooldownEndsAt"
GrabConfig.CarriedCounterplayProgressAttribute = "CarriedCounterplayProgress"
GrabConfig.CarriedCounterplayRequiredAttribute = "CarriedCounterplayRequired"
GrabConfig.CarriedReleaseReasonAttribute = "CarriedReleaseReason"
GrabConfig.CarriedLastActionAttribute = "CarriedLastAction"
GrabConfig.CarriedLastRejectReasonAttribute = "CarriedLastRejectReason"

GrabConfig.PlaceProbeHeightStuds = 8
GrabConfig.PlaceProbeDepthStuds = 20
GrabConfig.PlaceClearanceSize = Vector3.new(4, 6, 4)
GrabConfig.PlaceYOffsetStuds = 3

return GrabConfig
