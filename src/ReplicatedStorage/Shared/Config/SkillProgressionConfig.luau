--!strict

local SkillProgressionConfig: any = {}

SkillProgressionConfig.OutcomeKinds = {
	ObjectiveQteSuccess = "objective_qte_success",
	ObjectiveCompletion = "objective_completion",
	EscapeSuccess = "escape_success",
	ContainmentReward = "containment_reward",
}

SkillProgressionConfig.XpAwardsByOutcomeKind = {
	objective_qte_success = {
		skillId = "objective_craft",
		xpAmount = 25,
	},
	objective_completion = {
		skillId = "objective_craft",
		xpAmount = 50,
	},
	escape_success = {
		skillId = "realm_adaptation",
		xpAmount = 100,
	},
	containment_reward = {
		skillId = "custody_stewardship",
		xpAmount = 50,
	},
}

return SkillProgressionConfig
