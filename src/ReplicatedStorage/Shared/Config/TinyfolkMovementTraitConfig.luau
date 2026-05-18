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

TinyfolkMovementTraitConfig.SprintMaxStamina = 100
TinyfolkMovementTraitConfig.SprintDrainPerSecond = 25
TinyfolkMovementTraitConfig.SprintRegenPerSecond = 20
TinyfolkMovementTraitConfig.SprintExhaustedRecoveryThreshold = 25
TinyfolkMovementTraitConfig.SprintWalkSpeedMultiplier = 1.25
TinyfolkMovementTraitConfig.SprintMaxWalkSpeed = 24

TinyfolkMovementTraitConfig.Attributes = {
	BurstActive = "TinyfolkPostCrossingBurstActive",
	BurstUntil = "TinyfolkPostCrossingBurstUntil",
	BurstCooldownUntil = "TinyfolkPostCrossingBurstCooldownUntil",
	SharedBurstCooldownUntil = "TinyfolkMovementBurstCooldownUntil",
	TraceCostActive = "TinyfolkTraceCostActive",
	TraceCostUntil = "TinyfolkTraceCostUntil",
	TraceCostReason = "TinyfolkTraceCostReason",
	SprintRequested = "TinyfolkSprintRequested",
	SprintActive = "TinyfolkSprintActive",
	SprintExhausted = "TinyfolkSprintExhausted",
	SprintBreathless = "TinyfolkSprintBreathless",
	SprintStamina = "TinyfolkSprintStamina",
	SprintMaxStamina = "TinyfolkSprintMaxStamina",
	SprintStaminaRatio = "TinyfolkSprintStaminaRatio",
	SprintSpeedMultiplier = "TinyfolkSprintSpeedMultiplier",
	SprintRecoveryThreshold = "TinyfolkSprintRecoveryThreshold",
	SprintReason = "TinyfolkSprintReason",
}

return TinyfolkMovementTraitConfig
