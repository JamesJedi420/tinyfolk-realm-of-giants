--!strict

local OutcomeSkillXpProducer = {}

local skillProgressionConfig: any = nil
local skillXpAwardPolicy: any = nil

local function getSkillProgressionConfig(): any
	if skillProgressionConfig ~= nil then
		return skillProgressionConfig
	end
	local replicatedStorage = game:GetService("ReplicatedStorage")
	local shared = replicatedStorage:WaitForChild("Shared")
	local config = shared:WaitForChild("Config")
	skillProgressionConfig = require(config:WaitForChild("SkillProgressionConfig"))
	return skillProgressionConfig
end

local function getSkillXpAwardPolicy(): any
	if skillXpAwardPolicy ~= nil then
		return skillXpAwardPolicy
	end
	local replicatedStorage = game:GetService("ReplicatedStorage")
	local shared = replicatedStorage:WaitForChild("Shared")
	local skills = shared:WaitForChild("Skills")
	skillXpAwardPolicy = require(skills:WaitForChild("SkillXpAwardPolicy"))
	return skillXpAwardPolicy
end

local function getSkillProgressionQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._SkillProgressionService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

function OutcomeSkillXpProducer.RecordOutcomeXp(player: any, outcomeKind: string): (boolean, string?)
	if type(player) ~= "table" then
		return false, "player_invalid"
	end
	if type(outcomeKind) ~= "string" or outcomeKind == "" then
		return false, "outcome_kind_invalid"
	end

	local award, resolveReason = getSkillXpAwardPolicy().ResolveXpAward(outcomeKind, getSkillProgressionConfig())
	if award == nil then
		return false, resolveReason or "xp_award_unconfigured"
	end

	local skillProgressionApi = getSkillProgressionQueryApi()
	if type(skillProgressionApi) ~= "table" or type(skillProgressionApi.AwardSkillXp) ~= "function" then
		return false, "skill_progression_api_unavailable"
	end

	local ok, result = pcall(skillProgressionApi.AwardSkillXp, player, award.skillId, award.xpAmount)
	if not ok or type(result) ~= "table" then
		return false, "skill_xp_award_failed"
	end
	if result.accepted == true then
		return true, "accepted"
	end
	return false, tostring(result.reason or "skill_xp_award_rejected")
end

function OutcomeSkillXpProducer.RecordEscapeSuccessXp(player: any): (boolean, string?)
	return OutcomeSkillXpProducer.RecordOutcomeXp(player, getSkillProgressionConfig().OutcomeKinds.EscapeSuccess)
end

function OutcomeSkillXpProducer.RecordContainmentRewardXp(player: any): (boolean, string?)
	return OutcomeSkillXpProducer.RecordOutcomeXp(player, getSkillProgressionConfig().OutcomeKinds.ContainmentReward)
end

function OutcomeSkillXpProducer.RecordObjectiveCompletionXp(player: any): (boolean, string?)
	return OutcomeSkillXpProducer.RecordOutcomeXp(player, getSkillProgressionConfig().OutcomeKinds.ObjectiveCompletion)
end

return OutcomeSkillXpProducer
