--!nocheck

local TinyfolkHaulLogisticsConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkHaulLogisticsConfig")
local TinyfolkJobSchedulingConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkJobSchedulingConfig")
local StationConfig = require("../src/ReplicatedStorage/Shared/Config/StationConfig")
local TinyfolkHaulLogisticsState = require("../src/ReplicatedStorage/Shared/GiantRealm/TinyfolkHaulLogisticsState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local woodRoute, woodRouteReason = TinyfolkHaulLogisticsState.ResolveHaulRoute("Wood", "WorkStation_A")
assertTrue(woodRoute ~= nil, "wood route resolves")
assertEqual(woodRoute.sourceStationId, "WorkStation_A", "wood source station")
assertEqual(woodRoute.deliveryId, StationConfig.DefaultWarehouseId, "wood delivery warehouse")
assertEqual(woodRouteReason, nil, "wood route has no error")

local foodRoute, foodRouteReason = TinyfolkHaulLogisticsState.ResolveHaulRoute("Food", nil)
assertTrue(foodRoute ~= nil, "food route resolves from config source")
assertEqual(foodRoute.sourceStationId, "Farm_A", "food source from config")
assertEqual(foodRoute.deliveryId, StationConfig.DefaultGranaryId, "food delivery granary")
assertEqual(foodRouteReason, nil, "food route has no error")

local missingRoute, missingReason = TinyfolkHaulLogisticsState.ResolveHaulRoute("", nil)
assertTrue(missingRoute == nil, "empty material rejects route")
assertEqual(missingReason, "material_missing", "empty material reason")

assertEqual(
	TinyfolkHaulLogisticsState.ResolveHaulPhase({ produced = 4, inTransit = 0 }),
	TinyfolkHaulLogisticsConfig.Phases.Pickup,
	"produced pool selects pickup"
)
assertEqual(
	TinyfolkHaulLogisticsState.ResolveHaulPhase({ produced = 2, inTransit = 3 }),
	TinyfolkHaulLogisticsConfig.Phases.Deliver,
	"in transit selects deliver"
)
assertEqual(
	TinyfolkHaulLogisticsState.ResolveHaulPhase({ produced = 0, inTransit = 0 }),
	TinyfolkHaulLogisticsConfig.Phases.None,
	"empty pools select none"
)

assertTrue(
	TinyfolkHaulLogisticsState.IsHaulComplete({ produced = 0, inTransit = 0 }),
	"haul complete when pools empty"
)
assertTrue(
	not TinyfolkHaulLogisticsState.IsHaulComplete({ produced = 1, inTransit = 0 }),
	"haul incomplete with produced"
)
assertTrue(
	not TinyfolkHaulLogisticsState.IsHaulComplete({ produced = 0, inTransit = 2 }),
	"haul incomplete with in transit"
)

local eligibleWorker = {
	userId = 1,
	role = "Tinyfolk",
	scheduledJobKind = TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul,
	scheduledMaterial = "Wood",
	captureActive = false,
}
local eligible, eligibleReason = TinyfolkHaulLogisticsState.IsWorkerEligible(eligibleWorker)
assertTrue(eligible, "scheduled haul worker eligible")
assertEqual(eligibleReason, nil, "eligible worker has no reason")

local capturedWorker = table.clone(eligibleWorker)
capturedWorker.captureActive = true
local capturedEligible = TinyfolkHaulLogisticsState.IsWorkerEligible(capturedWorker)
assertTrue(not capturedEligible, "captured worker ineligible")

local giantWorker = table.clone(eligibleWorker)
giantWorker.role = "Giant"
assertTrue(not TinyfolkHaulLogisticsState.IsWorkerEligible(giantWorker), "giant ineligible")

local manualWorker = table.clone(eligibleWorker)
manualWorker.haulInteractionActive = true
local deferManual, deferManualReason = TinyfolkHaulLogisticsState.ShouldDeferToManualHaul(manualWorker, {
	lastHaulRequestAt = nil,
	now = 10,
	cooldownSeconds = 0.25,
})
assertTrue(deferManual, "defer when manual haul active")
assertEqual(deferManualReason, "manual_haul_active", "manual haul defer reason")

local cooldownWorker = table.clone(eligibleWorker)
local deferCooldown, deferCooldownReason = TinyfolkHaulLogisticsState.ShouldDeferToManualHaul(cooldownWorker, {
	lastHaulRequestAt = 9.9,
	now = 10,
	cooldownSeconds = 0.25,
})
assertTrue(deferCooldown, "defer during haul cooldown")
assertEqual(deferCooldownReason, "haul_cooldown", "cooldown defer reason")

assertTrue(
	TinyfolkHaulLogisticsState.IsWithinRange({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 }, 16),
	"within range at 10 studs"
)
assertTrue(
	not TinyfolkHaulLogisticsState.IsWithinRange({ x = 0, y = 0, z = 0 }, { x = 20, y = 0, z = 0 }, 16),
	"out of range at 20 studs"
)

assertEqual(
	TinyfolkHaulLogisticsState.ResolvePickupAmount(2, 1.5),
	3,
	"pickup amount applies haul yield multiplier"
)
assertEqual(
	TinyfolkHaulLogisticsState.ResolveDeliveryAmount("Wood", 5, StationConfig.HaulTransferPerStepByMaterial),
	2,
	"delivery amount capped by per-step config"
)

local workers = {
	{ userId = 3, role = "Tinyfolk" },
	{ userId = 1, role = "Tinyfolk" },
	{ userId = 2, role = "Tinyfolk" },
}
local sorted = TinyfolkHaulLogisticsState.SortWorkersByUserId(workers)
assertEqual(sorted[1].userId, 1, "sorted worker 1")
assertEqual(sorted[2].userId, 2, "sorted worker 2")
assertEqual(sorted[3].userId, 3, "sorted worker 3")

print("tinyfolk_haul_logistics_state: all checks passed")
