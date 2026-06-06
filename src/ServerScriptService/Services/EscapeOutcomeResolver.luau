--!strict

local EscapeOutcomeResolver: any = {}

local DEFAULT_PROFILE_HISTORY_LIMIT = 25
local DEFAULT_BASE_REWARD_POINTS = 100
local DEFAULT_LOOT_VALUE_MULTIPLIER = 10

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and value % 1 == 0
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function cloneValue(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in pairs(value) do
		result[cloneValue(key)] = cloneValue(child)
	end
	return result
end

local function defaultNow(): number
	return os.clock()
end

local function makeEmptyLoot(): any
	return {
		items = {},
		wood = 0,
		stone = 0,
		value = 0,
	}
end

local function normalizeLoot(value: any): any
	if type(value) ~= "table" then
		return makeEmptyLoot()
	end

	local items = {}
	if type(value.items) == "table" then
		for _, item in ipairs(value.items) do
			table.insert(items, cloneValue(item))
		end
	end

	return {
		items = items,
		wood = if isFiniteNumber(value.wood) and value.wood > 0 then value.wood else 0,
		stone = if isFiniteNumber(value.stone) and value.stone > 0 then value.stone else 0,
		value = if isFiniteNumber(value.value) and value.value > 0 then value.value else 0,
	}
end

local function normalizeDifficulty(value: any): number
	if isFiniteNumber(value) and value > 0 then
		return value
	end
	return 1
end

local function makeOperationId(input: any, nowAt: number): string?
	local explicit = nonEmptyString(input.operationId)
	if explicit ~= nil then
		return explicit
	end

	if not isPositiveInteger(input.userId) then
		return nil
	end

	local sourceKind = nonEmptyString(input.sourceKind) or "escape"
	if sourceKind == "transport" then
		local endpointId = nonEmptyString(input.endpointId) or nonEmptyString(input.sourceId)
		if endpointId == nil then
			return nil
		end
		return string.format("escape_transport:%s:%d:%.3f", endpointId, input.userId, nowAt)
	end

	local routeId = nonEmptyString(input.routeId) or nonEmptyString(input.sourceId)
	if routeId == nil then
		return nil
	end
	return string.format("escape:%d:%s:%.3f", input.userId, routeId, nowAt)
end

local function makeMemoryIdempotencyStore(): any
	local recordsByOperationId: { [string]: string } = {}
	return {
		TryBegin = function(operationId: any): any
			local id = nonEmptyString(operationId)
			if id == nil then
				return { accepted = false, reason = "operation_id_invalid" }
			end
			local status = recordsByOperationId[id]
			if status == "completed" then
				return { accepted = true, reason = "accepted", status = "completed" }
			end
			if status == "processing" then
				return { accepted = false, reason = "already_processing", status = "processing" }
			end
			recordsByOperationId[id] = "processing"
			return { accepted = true, reason = "accepted", status = "begun" }
		end,
		MarkCompleted = function(operationId: any): any
			local id = nonEmptyString(operationId)
			if id == nil then
				return { accepted = false, reason = "operation_id_invalid" }
			end
			recordsByOperationId[id] = "completed"
			return { accepted = true, reason = "accepted", status = "completed" }
		end,
		ReleaseProcessing = function(operationId: any): any
			local id = nonEmptyString(operationId)
			if id ~= nil and recordsByOperationId[id] == "processing" then
				recordsByOperationId[id] = nil
			end
			return { accepted = true, reason = "accepted", status = "released" }
		end,
	}
end

local function appendBounded(list: any, entry: any, limit: number): { any }
	local output = {}
	if type(list) == "table" then
		for _, existing in ipairs(list) do
			if type(existing) == "table" and existing.operationId ~= entry.operationId then
				table.insert(output, cloneValue(existing))
			end
		end
	end
	table.insert(output, cloneValue(entry))
	while #output > limit do
		table.remove(output, 1)
	end
	return output
end

function EscapeOutcomeResolver.Create(deps: any?): any
	local depsAny = if type(deps) == "table" then deps else {}
	local nowFn = if type(depsAny.now) == "function" then depsAny.now else defaultNow
	local idempotencyStore = if type(depsAny.idempotencyStore) == "table"
		then depsAny.idempotencyStore
		else makeMemoryIdempotencyStore()

	local resolver: any = {}

	local function getGlobalApi(name: string): any?
		local globalEnv: any = getfenv()
		if type(globalEnv) == "table" and type(rawget(globalEnv, name)) == "table" then
			return rawget(globalEnv, name)
		end
		if type(_G) == "table" and type(rawget(_G, name)) == "table" then
			return rawget(_G, name)
		end
		return nil
	end

	local function consumeLoot(userId: number, operationId: string): (boolean, string, any)
		local carriedLootApi = if type(depsAny.carriedLootApi) == "table"
			then depsAny.carriedLootApi
			else getGlobalApi("_TinyfolkCarriedLoot_QueryAPI")
		if type(carriedLootApi) ~= "table" or type(carriedLootApi.ConsumeForEscape) ~= "function" then
			return true, "loot_api_unavailable", makeEmptyLoot()
		end

		local ok, result = pcall(carriedLootApi.ConsumeForEscape, userId, operationId)
		if not ok or type(result) ~= "table" then
			return false, "loot_consume_failed", makeEmptyLoot()
		end
		if result.accepted ~= true then
			return false, tostring(result.reason or "loot_consume_rejected"), normalizeLoot(result.loot)
		end
		return true, tostring(result.reason or "accepted"), normalizeLoot(result.loot)
	end

	local function requestScore(userId: number, at: number, metadata: any): any
		local scoreApi = if type(depsAny.scoreApi) == "table"
			then depsAny.scoreApi
			else getGlobalApi("_ScoreService_QueryAPI")
		if type(scoreApi) ~= "table" or type(scoreApi.RequestScoreEvent) ~= "function" then
			return { accepted = false, reason = "score_api_unavailable" }
		end
		local ok, result = pcall(scoreApi.RequestScoreEvent, userId, "escape_success", at, metadata)
		if not ok or type(result) ~= "table" then
			return { accepted = false, reason = "score_request_failed" }
		end
		return result
	end

	local function updateProfile(player: any, entry: any): (boolean, string?)
		local gateway = if type(depsAny.profileGateway) == "table"
			then depsAny.profileGateway
			else getGlobalApi("_ProfilePersistenceGateway_QueryAPI")
		if gateway == nil then
			local ok, loaded = pcall(function()
				if script ~= nil and script.Parent ~= nil then
					return require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
				end
				return require("./ProfilePersistenceGateway")
			end)
			if ok then
				gateway = loaded
			end
		end

		if type(gateway) ~= "table" or type(gateway.UpdateLoadedPlayerProfileData) ~= "function" then
			return false, "profile_gateway_unavailable"
		end

		local ok, result = pcall(gateway.UpdateLoadedPlayerProfileData, player, function(currentData: any): any
			if type(currentData) ~= "table" then
				return nil, "profile_data_invalid"
			end
			currentData.escapeHistory = appendBounded(currentData.escapeHistory, entry, DEFAULT_PROFILE_HISTORY_LIMIT)
			return currentData
		end)
		if not ok or type(result) ~= "table" or result.ok ~= true then
			return false,
				if type(result) == "table" and type(result.reason) == "string"
					then result.reason
					else "profile_update_failed"
		end
		return true, nil
	end

	local function recordDefense(entry: any): (boolean, string?)
		local defenseApi = if type(depsAny.defenseHistoryApi) == "table"
			then depsAny.defenseHistoryApi
			else getGlobalApi("_GiantBuildModeService_QueryAPI")
		if type(defenseApi) ~= "table" or type(defenseApi.RecordEscapeDefenseOutcome) ~= "function" then
			return false, "defense_history_api_unavailable"
		end
		local ok, result = pcall(defenseApi.RecordEscapeDefenseOutcome, entry)
		if not ok or type(result) ~= "table" or result.accepted ~= true then
			return false,
				if type(result) == "table" and type(result.reason) == "string"
					then result.reason
					else "defense_history_update_failed"
		end
		return true, nil
	end

	local function returnToHub(player: any): boolean
		if type(depsAny.returnToHub) ~= "function" then
			return false
		end
		local ok, result = pcall(depsAny.returnToHub, player)
		return ok and result == true
	end

	function resolver.Resolve(input: any): any
		if type(input) ~= "table" then
			return { accepted = false, reason = "input_invalid" }
		end
		if not isPositiveInteger(input.userId) then
			return { accepted = false, reason = "user_id_invalid" }
		end

		local nowAt = if isFiniteNumber(input.now) and input.now >= 0 then input.now else nowFn()
		local operationId = makeOperationId(input, nowAt)
		if operationId == nil then
			return { accepted = false, reason = "operation_id_invalid" }
		end

		local beginOk, beginResult = pcall(idempotencyStore.TryBegin, operationId)
		if not beginOk or type(beginResult) ~= "table" then
			return { accepted = false, reason = "idempotency_try_begin_failed", operationId = operationId }
		end
		if beginResult.accepted == true and beginResult.status == "completed" then
			return {
				accepted = true,
				reason = "duplicate_completed",
				operationId = operationId,
				duplicate = true,
			}
		end
		if beginResult.accepted ~= true then
			return {
				accepted = false,
				reason = tostring(beginResult.reason or "already_processing"),
				operationId = operationId,
				duplicate = beginResult.status == "processing",
			}
		end

		local userId = input.userId :: number
		local difficulty = normalizeDifficulty(input.difficulty)
		local lootAccepted, lootReason, loot = consumeLoot(userId, operationId)
		local rewardPoints = DEFAULT_BASE_REWARD_POINTS
			+ math.floor((difficulty - 1) * 25 + 0.5)
			+ math.floor((loot.value or 0) * DEFAULT_LOOT_VALUE_MULTIPLIER + 0.5)
		local sourceKind = nonEmptyString(input.sourceKind) or "escape"
		local sourceId = nonEmptyString(input.sourceId)
			or nonEmptyString(input.routeId)
			or nonEmptyString(input.endpointId)
			or sourceKind

		local reward = {
			points = rewardPoints,
			basePoints = DEFAULT_BASE_REWARD_POINTS,
			difficulty = difficulty,
			lootValue = loot.value,
		}
		local metadata = {
			operationId = operationId,
			sourceKind = sourceKind,
			sourceId = sourceId,
			routeId = input.routeId,
			endpointId = input.endpointId,
			difficulty = difficulty,
			loot = loot,
			reward = reward,
		}
		local scoreResult = requestScore(userId, nowAt, metadata)

		local profileEntry = {
			operationId = operationId,
			escapedAt = nowAt,
			sourceKind = sourceKind,
			sourceId = sourceId,
			routeId = input.routeId,
			realmId = input.realmId,
			realmOwnerUserId = input.realmOwnerUserId,
			difficulty = difficulty,
			reward = reward,
			loot = loot,
		}
		local profileUpdated, profileReason = updateProfile(input.player, profileEntry)
		local defenseUpdated, defenseReason = recordDefense({
			operationId = operationId,
			escapedUserId = userId,
			escapedAt = nowAt,
			sourceKind = sourceKind,
			sourceId = sourceId,
			routeId = input.routeId,
			difficulty = difficulty,
			lootValue = loot.value,
			rewardPoints = rewardPoints,
		})
		local returnedToHub = returnToHub(input.player)

		local completedOk, completedResult = pcall(idempotencyStore.MarkCompleted, operationId)
		if not completedOk or type(completedResult) ~= "table" or completedResult.accepted ~= true then
			return {
				accepted = false,
				reason = "idempotency_mark_completed_failed",
				operationId = operationId,
				reward = reward,
				lootTransferred = lootAccepted,
				cleanupDebt = true,
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			operationId = operationId,
			duplicate = false,
			reward = reward,
			scoreAccepted = type(scoreResult) == "table" and scoreResult.accepted == true,
			scoreReason = if type(scoreResult) == "table" then scoreResult.reason else "score_result_invalid",
			profileUpdated = profileUpdated,
			profileReason = profileReason,
			defenseUpdated = defenseUpdated,
			defenseReason = defenseReason,
			lootTransferred = lootAccepted,
			lootReason = lootReason,
			loot = loot,
			returnedToHub = returnedToHub,
		}
	end

	return resolver
end

return EscapeOutcomeResolver
