--!strict

local TinyfolkHaulLogisticsConfig: any = {}

TinyfolkHaulLogisticsConfig.ProcessIntervalSeconds = 0.25

TinyfolkHaulLogisticsConfig.MaxWorkersPerTick = 8

TinyfolkHaulLogisticsConfig.Phases = {
	None = "none",
	Pickup = "pickup",
	Deliver = "deliver",
}

TinyfolkHaulLogisticsConfig.PhaseAttribute = "TinyfolkHaulPhase"
TinyfolkHaulLogisticsConfig.RouteSourceIdAttribute = "TinyfolkHaulRouteSourceId"
TinyfolkHaulLogisticsConfig.RouteDeliveryIdAttribute = "TinyfolkHaulRouteDeliveryId"
TinyfolkHaulLogisticsConfig.MaterialAttribute = "TinyfolkHaulMaterial"
TinyfolkHaulLogisticsConfig.LastReasonAttribute = "TinyfolkHaulLastReason"
TinyfolkHaulLogisticsConfig.UpdatedAtAttribute = "TinyfolkHaulUpdatedAt"
TinyfolkHaulLogisticsConfig.LastMovedAmountAttribute = "TinyfolkHaulLastMovedAmount"

TinyfolkHaulLogisticsConfig.DebugRequestRemoteName = "TinyfolkHaulLogisticsDebugRequest"
TinyfolkHaulLogisticsConfig.DebugResponseRemoteName = "TinyfolkHaulLogisticsDebugResponse"

return TinyfolkHaulLogisticsConfig
