--!strict

local SkillProgressionConfig = require("../Config/SkillProgressionConfig")
local SkillCatalogSchema = require("../Config/SkillCatalogSchema")

local SkillXpAwardPolicy = {}

export type XpAward = {
	skillId: string,
	xpAmount: number,
}

local function isFinitePositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return value > 0
end

function SkillXpAwardPolicy.ResolveXpAward(outcomeKind: string, config: any?): (XpAward?, string?)
	if type(outcomeKind) ~= "string" or outcomeKind == "" then
		return nil, "outcome_kind_invalid"
	end

	local sourceConfig = if type(config) == "table" then config else SkillProgressionConfig
	local awardsByOutcomeKind = sourceConfig.XpAwardsByOutcomeKind
	if type(awardsByOutcomeKind) ~= "table" then
		return nil, "xp_award_config_invalid"
	end

	local awardRecord = awardsByOutcomeKind[outcomeKind]
	if type(awardRecord) ~= "table" then
		return nil, "xp_award_unconfigured"
	end

	local skillId = awardRecord.skillId
	local xpAmount = awardRecord.xpAmount
	if type(skillId) ~= "string" or skillId == "" then
		return nil, "xp_award_skill_id_invalid"
	end
	if not isFinitePositiveInteger(xpAmount) then
		return nil, "xp_award_amount_invalid"
	end

	local skillRecord = SkillCatalogSchema.GetSkillRecord(skillId)
	if skillRecord == nil then
		return nil, "xp_award_skill_missing"
	end

	return {
		skillId = skillId,
		xpAmount = xpAmount,
	}, nil
end

return SkillXpAwardPolicy
