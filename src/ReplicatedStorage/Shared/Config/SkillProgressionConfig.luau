--!strict

local SkillProgressionConfig: any = {}

SkillProgressionConfig.OutcomeKinds = {
	ObjectiveQteSuccess = "objective_qte_success",
}

SkillProgressionConfig.XpAwardsByOutcomeKind = {
	objective_qte_success = {
		skillId = "objective_craft",
		xpAmount = 25,
	},
}

return SkillProgressionConfig
