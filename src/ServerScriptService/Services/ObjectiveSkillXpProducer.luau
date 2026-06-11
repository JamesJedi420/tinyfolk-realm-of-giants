--!strict

local ObjectiveSkillXpProducer = {}

local outcomeSkillXpProducer: any = nil
local skillProgressionConfig: any = nil

local function getOutcomeSkillXpProducer(): any
	if outcomeSkillXpProducer ~= nil then
		return outcomeSkillXpProducer
	end
	if script ~= nil and script.Parent ~= nil and type(script.Parent.WaitForChild) == "function" then
		local moduleValue = script.Parent:WaitForChild("OutcomeSkillXpProducer")
		if moduleValue ~= nil then
			local ok, loaded = pcall(require, moduleValue)
			if ok and type(loaded) == "table" then
				outcomeSkillXpProducer = loaded
			end
		end
	end
	if outcomeSkillXpProducer == nil then
		outcomeSkillXpProducer = require("./OutcomeSkillXpProducer")
	end
	return outcomeSkillXpProducer
end

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

function ObjectiveSkillXpProducer.RecordObjectiveQteSuccessXp(player: any): (boolean, string?)
	return getOutcomeSkillXpProducer().RecordOutcomeXp(
		player,
		getSkillProgressionConfig().OutcomeKinds.ObjectiveQteSuccess
	)
end

return ObjectiveSkillXpProducer
