--!strict

local TinyfolkMovementTraitConfig: any = {}

TinyfolkMovementTraitConfig.TraitAttributeName = "TinyfolkTrait_PostCrossingBurst"

TinyfolkMovementTraitConfig.BurstWalkSpeedBonus = 6
TinyfolkMovementTraitConfig.BurstDurationSeconds = 1.25
TinyfolkMovementTraitConfig.CooldownSeconds = 6
TinyfolkMovementTraitConfig.SharedBurstCooldownSeconds = 6
TinyfolkMovementTraitConfig.TraceCostDurationSeconds = 3
TinyfolkMovementTraitConfig.TraceCostReason = "PostCrossingBurst"

TinyfolkMovementTraitConfig.MaxBurstWalkSpeed = 24

TinyfolkMovementTraitConfig.Attributes = {
	BurstActive = "TinyfolkPostCrossingBurstActive",
	BurstUntil = "TinyfolkPostCrossingBurstUntil",
	BurstCooldownUntil = "TinyfolkPostCrossingBurstCooldownUntil",
	SharedBurstCooldownUntil = "TinyfolkMovementBurstCooldownUntil",
	TraceCostActive = "TinyfolkTraceCostActive",
	TraceCostUntil = "TinyfolkTraceCostUntil",
	TraceCostReason = "TinyfolkTraceCostReason",
}

return TinyfolkMovementTraitConfig
