--!strict

local StationConfig = require("../Config/StationConfig")
local ShrineConfig = require("../Config/ShrineConfig")
local VillageWorksiteUpgradeConfig = require("../Config/VillageWorksiteUpgradeConfig")

local VillageWorksiteUpgradeState: any = {}

VillageWorksiteUpgradeState.WorksiteKinds = {
	WorkStation = "work_station",
	MiningStation = "mining_station",
	Warehouse = "warehouse",
	Granary = "granary",
	Shrine = "shrine",
	Farm = "farm",
	Pen = "pen",
	GuardTower = "guard_tower",
}

VillageWorksiteUpgradeState.EffectKinds = {
	Production = "production",
	Capacity = "capacity",
	Defense = "defense",
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function startsWithPrefix(value: string, prefix: string): boolean
	return string.sub(value, 1, #prefix) == prefix
end

function VillageWorksiteUpgradeState.ResolveWorksiteKind(worksiteId: string): string?
	if startsWithPrefix(worksiteId, StationConfig.StationNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.WorkStation
	end
	if startsWithPrefix(worksiteId, StationConfig.MiningStationNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.MiningStation
	end
	if startsWithPrefix(worksiteId, StationConfig.WarehouseNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.Warehouse
	end
	if startsWithPrefix(worksiteId, StationConfig.GranaryNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.Granary
	end
	if startsWithPrefix(worksiteId, ShrineConfig.ShrineNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.Shrine
	end
	if startsWithPrefix(worksiteId, StationConfig.FarmNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.Farm
	end
	if startsWithPrefix(worksiteId, StationConfig.PenNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.Pen
	end
	if startsWithPrefix(worksiteId, StationConfig.GuardTowerNamePrefix) then
		return VillageWorksiteUpgradeState.WorksiteKinds.GuardTower
	end
	return nil
end

function VillageWorksiteUpgradeState.ResolveEffectKind(worksiteKind: string): string?
	if
		worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.WorkStation
		or worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.MiningStation
		or worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.Farm
	then
		return VillageWorksiteUpgradeState.EffectKinds.Production
	end
	if
		worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.Warehouse
		or worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.Granary
		or worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.Shrine
		or worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.Pen
	then
		return VillageWorksiteUpgradeState.EffectKinds.Capacity
	end
	if worksiteKind == VillageWorksiteUpgradeState.WorksiteKinds.GuardTower then
		return VillageWorksiteUpgradeState.EffectKinds.Defense
	end
	return nil
end

function VillageWorksiteUpgradeState.ResolveMaxConcurrentCaptures(
	baseMax: number,
	heldCapacityMultiplier: number
): number
	local safeBase = if isFiniteNumber(baseMax) and baseMax > 0 then math.floor(baseMax) else 1
	local multiplier = if isFiniteNumber(heldCapacityMultiplier) and heldCapacityMultiplier > 0
		then heldCapacityMultiplier
		else 1
	return math.max(1, math.floor(safeBase * multiplier + 0.5))
end

function VillageWorksiteUpgradeState.CreateEmptyState(): any
	return {
		byWorksiteId = {},
	}
end

function VillageWorksiteUpgradeState.ValidateUpgradeRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "worksite_upgrade_record_invalid"
	end
	local worksiteId = nonEmptyString(record.worksiteId)
	if worksiteId == nil then
		return false, "worksite_upgrade_worksite_id_invalid"
	end
	local worksiteKind = nonEmptyString(record.worksiteKind)
	if worksiteKind == nil then
		return false, "worksite_upgrade_worksite_kind_invalid"
	end
	if VillageWorksiteUpgradeState.ResolveWorksiteKind(worksiteId) ~= worksiteKind then
		return false, "worksite_upgrade_kind_mismatch"
	end
	if not isFiniteNumber(record.level) or record.level < 0 or record.level > VillageWorksiteUpgradeConfig.MaxLevel then
		return false, "worksite_upgrade_level_invalid"
	end
	if not isFiniteNumber(record.lastUpgradedAt) or record.lastUpgradedAt < 0 then
		return false, "worksite_upgrade_last_upgraded_at_invalid"
	end
	return true, nil
end

function VillageWorksiteUpgradeState.ReconcileState(raw: any): any
	if type(raw) ~= "table" then
		return VillageWorksiteUpgradeState.CreateEmptyState()
	end

	local state = VillageWorksiteUpgradeState.CreateEmptyState()
	if type(raw.byWorksiteId) == "table" then
		for worksiteId, record in pairs(raw.byWorksiteId) do
			if type(record) == "table" then
				local merged = {
					worksiteId = if nonEmptyString(record.worksiteId) then record.worksiteId else worksiteId,
					worksiteKind = record.worksiteKind,
					level = record.level,
					lastUpgradedAt = record.lastUpgradedAt,
				}
				local valid, _ = VillageWorksiteUpgradeState.ValidateUpgradeRecord(merged)
				if valid then
					state.byWorksiteId[merged.worksiteId] = merged
				end
			end
		end
	end
	return state
end

function VillageWorksiteUpgradeState.GetUpgradeLevel(state: any, worksiteId: string): number
	if type(state) ~= "table" or type(state.byWorksiteId) ~= "table" then
		return 0
	end
	local record = state.byWorksiteId[worksiteId]
	if type(record) ~= "table" or not isFiniteNumber(record.level) then
		return 0
	end
	return math.floor(record.level)
end

function VillageWorksiteUpgradeState.ResolveUpgradeCost(worksiteKind: string, targetLevel: number): any
	if not isFiniteNumber(targetLevel) or targetLevel <= 0 or targetLevel > VillageWorksiteUpgradeConfig.MaxLevel then
		return { accepted = false, reason = "target_level_invalid" }
	end

	local costsByLevel = VillageWorksiteUpgradeConfig.UpgradeCostsByKindAndLevel[worksiteKind]
	if type(costsByLevel) ~= "table" then
		return { accepted = false, reason = "worksite_kind_unsupported" }
	end

	local cost = costsByLevel[targetLevel]
	if type(cost) ~= "table" then
		return { accepted = false, reason = "upgrade_cost_missing" }
	end

	return {
		accepted = true,
		reason = "accepted",
		targetLevel = targetLevel,
		wood = if isFiniteNumber(cost.wood) and cost.wood >= 0 then cost.wood else 0,
		stone = if isFiniteNumber(cost.stone) and cost.stone >= 0 then cost.stone else 0,
		essence = if isFiniteNumber(cost.essence) and cost.essence >= 0 then cost.essence else 0,
	}
end

function VillageWorksiteUpgradeState.ResolveProductionModifiers(level: number): any
	local normalizedLevel = if isFiniteNumber(level) and level >= 0
		then math.min(math.floor(level), VillageWorksiteUpgradeConfig.MaxLevel)
		else 0
	local multipliers = VillageWorksiteUpgradeConfig.ProductionMultipliersByLevel[normalizedLevel]
		or VillageWorksiteUpgradeConfig.ProductionMultipliersByLevel[0]

	return {
		level = normalizedLevel,
		perTickMultiplier = multipliers.perTick,
		maxTotalMultiplier = multipliers.maxTotal,
	}
end

function VillageWorksiteUpgradeState.ResolveDefenseModifiers(level: number): any
	local normalizedLevel = if isFiniteNumber(level) and level >= 0
		then math.min(math.floor(level), VillageWorksiteUpgradeConfig.MaxLevel)
		else 0
	local multipliers = VillageWorksiteUpgradeConfig.DefenseMultipliersByLevel[normalizedLevel]
		or VillageWorksiteUpgradeConfig.DefenseMultipliersByLevel[0]

	return {
		level = normalizedLevel,
		treasuryAwardMultiplier = multipliers.treasuryAward,
		barrierDurationMultiplier = multipliers.barrierDuration,
	}
end

function VillageWorksiteUpgradeState.ResolveCapacityModifiers(level: number): any
	local normalizedLevel = if isFiniteNumber(level) and level >= 0
		then math.min(math.floor(level), VillageWorksiteUpgradeConfig.MaxLevel)
		else 0
	local multipliers = VillageWorksiteUpgradeConfig.CapacityMultipliersByLevel[normalizedLevel]
		or VillageWorksiteUpgradeConfig.CapacityMultipliersByLevel[0]

	return {
		level = normalizedLevel,
		inTransitMultiplier = multipliers.inTransit,
		essenceMaxMultiplier = multipliers.essenceMax,
		heldCapacityMultiplier = multipliers.heldCapacity,
	}
end

function VillageWorksiteUpgradeState.ResolveUpgrade(state: any, input: any): any
	if type(state) ~= "table" then
		return { accepted = false, reason = "state_invalid" }
	end
	if type(input) ~= "table" then
		return { accepted = false, reason = "input_invalid" }
	end

	local worksiteId = nonEmptyString(input.worksiteId)
	if worksiteId == nil then
		return { accepted = false, reason = "worksite_id_invalid" }
	end

	local worksiteKind = VillageWorksiteUpgradeState.ResolveWorksiteKind(worksiteId)
	if worksiteKind == nil then
		return { accepted = false, reason = "worksite_kind_unsupported" }
	end

	if not isFiniteNumber(input.at) or input.at < 0 then
		return { accepted = false, reason = "timestamp_invalid" }
	end

	local currentLevel = VillageWorksiteUpgradeState.GetUpgradeLevel(state, worksiteId)
	local targetLevel = currentLevel + 1
	if targetLevel > VillageWorksiteUpgradeConfig.MaxLevel then
		return {
			accepted = false,
			reason = "max_level_reached",
			worksiteId = worksiteId,
			currentLevel = currentLevel,
		}
	end

	local costResult = VillageWorksiteUpgradeState.ResolveUpgradeCost(worksiteKind, targetLevel)
	if costResult.accepted ~= true then
		return {
			accepted = false,
			reason = costResult.reason or "upgrade_cost_invalid",
			worksiteId = worksiteId,
			currentLevel = currentLevel,
		}
	end

	local nextState = VillageWorksiteUpgradeState.ReconcileState(state)
	nextState.byWorksiteId[worksiteId] = {
		worksiteId = worksiteId,
		worksiteKind = worksiteKind,
		level = targetLevel,
		lastUpgradedAt = input.at,
	}

	return {
		accepted = true,
		reason = "accepted",
		worksiteId = worksiteId,
		worksiteKind = worksiteKind,
		previousLevel = currentLevel,
		level = targetLevel,
		cost = {
			wood = costResult.wood,
			stone = costResult.stone,
			essence = costResult.essence,
		},
		state = nextState,
	}
end

function VillageWorksiteUpgradeState.SerializePersistenceState(state: any): any
	if type(state) ~= "table" or type(state.byWorksiteId) ~= "table" then
		return { upgrades = {} }
	end

	local records = {}
	for _, record in pairs(state.byWorksiteId) do
		if type(record) == "table" then
			table.insert(records, {
				worksiteId = record.worksiteId,
				worksiteKind = record.worksiteKind,
				level = record.level,
				lastUpgradedAt = record.lastUpgradedAt,
			})
		end
	end

	table.sort(records, function(a: any, b: any): boolean
		return a.worksiteId < b.worksiteId
	end)

	return { upgrades = records }
end

function VillageWorksiteUpgradeState.ApplyPersistenceState(raw: any): any
	if raw == nil then
		return {
			accepted = true,
			reason = "cleared",
			state = VillageWorksiteUpgradeState.CreateEmptyState(),
		}
	end

	if type(raw) ~= "table" or type(raw.upgrades) ~= "table" then
		return { accepted = false, reason = "persistence_invalid" }
	end

	local byWorksiteId: { [string]: any } = {}
	for index, record in ipairs(raw.upgrades) do
		local valid, reason = VillageWorksiteUpgradeState.ValidateUpgradeRecord(record)
		if not valid then
			return {
				accepted = false,
				reason = string.format("%s index=%d", reason or "worksite_upgrade_record_invalid", index),
			}
		end
		byWorksiteId[record.worksiteId] = {
			worksiteId = record.worksiteId,
			worksiteKind = record.worksiteKind,
			level = record.level,
			lastUpgradedAt = record.lastUpgradedAt,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		state = {
			byWorksiteId = byWorksiteId,
		},
	}
end

return VillageWorksiteUpgradeState
