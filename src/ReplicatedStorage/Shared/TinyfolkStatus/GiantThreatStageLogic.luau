--!strict

local GiantThreatStageLogic: any = {}

export type ThreatStageState = {
	stage: string?,
	stageEnteredAt: number?,
	lastUpdatedAt: number?,
}

local function cloneState(state: ThreatStageState?): ThreatStageState
	local nextState = {} :: any
	if state ~= nil then
		nextState.stage = state.stage
		nextState.stageEnteredAt = state.stageEnteredAt
		nextState.lastUpdatedAt = state.lastUpdatedAt
	end
	return nextState
end

local function getStageConfig(config: any): any
	if type(config) ~= "table" or type(config.GiantThreatStage) ~= "table" then
		return {}
	end
	return config.GiantThreatStage
end

local function stageLevels(config: any): any
	local stages = getStageConfig(config)
	return if type(stages.Levels) == "table" then stages.Levels else {}
end

local function stageName(config: any, key: string, fallback: string): string
	local levels = stageLevels(config)
	local value = levels[key]
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function stageRank(config: any, stage: string): number
	local levels = stageLevels(config)
	if stage == (levels.Critical or "critical") then
		return 3
	end
	if stage == (levels.Pressure or "pressure") then
		return 2
	end
	if stage == (levels.Watch or "watch") then
		return 1
	end
	return 0
end

local function stageFromWarningLevel(config: any, warningLevel: any): string
	local stages = getStageConfig(config)
	local mapping = if type(stages.WarningLevelToStage) == "table" then stages.WarningLevelToStage else {}
	local normalized = if type(warningLevel) == "string" then string.lower(warningLevel) else "none"
	local stage = mapping[normalized]
	if type(stage) == "string" and stage ~= "" then
		return stage
	end
	return stageName(config, "Calm", "calm")
end

local function decaySeconds(config: any): number
	local stages = getStageConfig(config)
	local seconds = tonumber(stages.DecaySeconds) or 10
	if seconds < 0 then
		return 0
	end
	return seconds
end

function GiantThreatStageLogic.NewState(): ThreatStageState
	return {
		stage = nil,
		stageEnteredAt = nil,
		lastUpdatedAt = nil,
	}
end

function GiantThreatStageLogic.ResolveTick(
	state: ThreatStageState?,
	config: any,
	input: { now: number, warningLevel: any }
): (ThreatStageState, any)
	local nextState = cloneState(state)
	local now = input.now
	local desiredStage = stageFromWarningLevel(config, input.warningLevel)
	local currentStage = nextState.stage
	local desiredRank = stageRank(config, desiredStage)
	local currentRank = if type(currentStage) == "string" then stageRank(config, currentStage) else 0
	local enteredAt: number = now
	if type(nextState.stageEnteredAt) == "number" then
		enteredAt = nextState.stageEnteredAt :: number
	end

	if currentStage == nil then
		nextState.stage = desiredStage
		nextState.stageEnteredAt = now
	elseif desiredRank > currentRank then
		nextState.stage = desiredStage
		nextState.stageEnteredAt = now
	elseif desiredRank < currentRank then
		if now - enteredAt >= decaySeconds(config) then
			local nextRank = math.max(currentRank - 1, desiredRank)
			local levels = stageLevels(config)
			if nextRank >= 3 then
				nextState.stage = levels.Critical or "critical"
			elseif nextRank == 2 then
				nextState.stage = levels.Pressure or "pressure"
			elseif nextRank == 1 then
				nextState.stage = levels.Watch or "watch"
			else
				nextState.stage = levels.Calm or "calm"
			end
			nextState.stageEnteredAt = now
		end
	elseif type(nextState.stage) ~= "string" or nextState.stage == "" then
		nextState.stage = desiredStage
		nextState.stageEnteredAt = now
	end

	if type(nextState.stageEnteredAt) ~= "number" then
		nextState.stageEnteredAt = now
	end
	nextState.lastUpdatedAt = now
	return nextState,
		{
			stage = nextState.stage or stageName(config, "Calm", "calm"),
			stageEnteredAt = nextState.stageEnteredAt,
			desiredStage = desiredStage,
			warningLevel = if type(input.warningLevel) == "string" then string.lower(input.warningLevel) else "none",
		}
end

return GiantThreatStageLogic
