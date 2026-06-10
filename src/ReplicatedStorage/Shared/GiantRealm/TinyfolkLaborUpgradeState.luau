--!strict

local TinyfolkLaborUpgradeConfig = require("../Config/TinyfolkLaborUpgradeConfig")

local TinyfolkLaborUpgradeState = {}

export type PlayerState = {
	laborTokens: number,
	haulYieldLevel: number,
	taskPaceLevel: number,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizeLevel(level: number): number
	if not isFiniteNumber(level) or level < 0 then
		return 0
	end
	return math.min(math.floor(level), TinyfolkLaborUpgradeConfig.MaxLevel)
end

function TinyfolkLaborUpgradeState.CreateEmptyPlayerState(): PlayerState
	return {
		laborTokens = 0,
		haulYieldLevel = 0,
		taskPaceLevel = 0,
	}
end

function TinyfolkLaborUpgradeState.ResolveTrackForBenchId(benchId: string?): string?
	if type(benchId) ~= "string" or benchId == "" then
		return nil
	end
	local track = TinyfolkLaborUpgradeConfig.TrackByBenchId[benchId]
	if type(track) == "string" and track ~= "" then
		return track
	end
	return nil
end

function TinyfolkLaborUpgradeState.GetLevelForTrack(state: PlayerState, track: string): number
	if track == TinyfolkLaborUpgradeConfig.Tracks.HaulYield then
		return normalizeLevel(state.haulYieldLevel)
	end
	if track == TinyfolkLaborUpgradeConfig.Tracks.TaskPace then
		return normalizeLevel(state.taskPaceLevel)
	end
	return 0
end

function TinyfolkLaborUpgradeState.ResolveHaulYieldMultiplier(level: number): number
	local normalizedLevel = normalizeLevel(level)
	return TinyfolkLaborUpgradeConfig.HaulYieldMultiplierByLevel[normalizedLevel]
		or TinyfolkLaborUpgradeConfig.HaulYieldMultiplierByLevel[0]
end

function TinyfolkLaborUpgradeState.ResolveTaskPaceMultiplier(level: number): number
	local normalizedLevel = normalizeLevel(level)
	return TinyfolkLaborUpgradeConfig.TaskPaceMultiplierByLevel[normalizedLevel]
		or TinyfolkLaborUpgradeConfig.TaskPaceMultiplierByLevel[0]
end

function TinyfolkLaborUpgradeState.GrantWorkActionReward(state: PlayerState): PlayerState
	local nextState = table.clone(state)
	nextState.laborTokens += TinyfolkLaborUpgradeConfig.TokensPerWorkAction
	return nextState
end

function TinyfolkLaborUpgradeState.ResolveUpgrade(state: PlayerState, track: string): any
	if track ~= TinyfolkLaborUpgradeConfig.Tracks.HaulYield and track ~= TinyfolkLaborUpgradeConfig.Tracks.TaskPace then
		return {
			accepted = false,
			reason = "track_invalid",
			state = state,
		}
	end

	local currentLevel = TinyfolkLaborUpgradeState.GetLevelForTrack(state, track)
	if currentLevel >= TinyfolkLaborUpgradeConfig.MaxLevel then
		return {
			accepted = false,
			reason = "max_level_reached",
			state = state,
			track = track,
			level = currentLevel,
		}
	end

	local nextLevel = currentLevel + 1
	local costTable = TinyfolkLaborUpgradeConfig.UpgradeCostsByTrackAndLevel[track]
	local cost = if type(costTable) == "table" then costTable[nextLevel] else nil
	if type(cost) ~= "table" then
		return {
			accepted = false,
			reason = "cost_missing",
			state = state,
			track = track,
		}
	end

	local laborTokenCost = if type(cost.laborTokens) == "number" then math.floor(cost.laborTokens) else 0
	local foodCost = if type(cost.food) == "number" then math.floor(cost.food) else 0

	if track == TinyfolkLaborUpgradeConfig.Tracks.HaulYield then
		if laborTokenCost <= 0 then
			return {
				accepted = false,
				reason = "cost_missing",
				state = state,
				track = track,
			}
		end
		if state.laborTokens < laborTokenCost then
			return {
				accepted = false,
				reason = "insufficient_labor_tokens",
				state = state,
				track = track,
				level = currentLevel,
				cost = cost,
			}
		end

		local nextState = table.clone(state)
		nextState.laborTokens -= laborTokenCost
		nextState.haulYieldLevel = nextLevel
		return {
			accepted = true,
			reason = nil,
			state = nextState,
			track = track,
			level = nextLevel,
			cost = cost,
			spendKind = "labor_tokens",
		}
	end

	if foodCost <= 0 then
		return {
			accepted = false,
			reason = "cost_missing",
			state = state,
			track = track,
		}
	end

	return {
		accepted = true,
		reason = nil,
		state = state,
		track = track,
		level = nextLevel,
		cost = cost,
		spendKind = "stored_food",
		pendingFoodCost = foodCost,
	}
end

function TinyfolkLaborUpgradeState.ApplyFoodSpendSuccess(state: PlayerState, track: string, nextLevel: number): PlayerState
	local nextState = table.clone(state)
	if track == TinyfolkLaborUpgradeConfig.Tracks.TaskPace then
		nextState.taskPaceLevel = normalizeLevel(nextLevel)
	end
	return nextState
end

function TinyfolkLaborUpgradeState.BuildDebugSnapshot(state: PlayerState): any
	return {
		laborTokens = state.laborTokens,
		haulYieldLevel = normalizeLevel(state.haulYieldLevel),
		taskPaceLevel = normalizeLevel(state.taskPaceLevel),
		haulYieldMultiplier = TinyfolkLaborUpgradeState.ResolveHaulYieldMultiplier(state.haulYieldLevel),
		taskPaceMultiplier = TinyfolkLaborUpgradeState.ResolveTaskPaceMultiplier(state.taskPaceLevel),
	}
end

return TinyfolkLaborUpgradeState
