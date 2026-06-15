--!strict

local GiantLevelConfig = require("../Config/GiantLevelConfig")

local GiantLevelState = {}

export type XpEventRecord = {
	operationId: string,
	eventKind: string,
	xpAwarded: number,
	awardedAt: number,
}

export type ResolvedUnlockRecord = {
	unlockId: string,
	level: number,
	displayName: string?,
}

export type ModifierSnapshot = {
	xpAwardMultiplier: number,
	containmentRewardMultiplier: number,
	resolvedUnlockIds: { string },
}

export type State = {
	xp: number,
	level: number,
	operationIds: { [string]: boolean },
	recentEvents: { XpEventRecord },
	resolvedUnlockIds: { [string]: boolean },
}

local VALID_EVENT_KINDS = {
	[GiantLevelConfig.EventKinds.CaptureSuccess] = true,
	[GiantLevelConfig.EventKinds.ContainmentHeld] = true,
	[GiantLevelConfig.EventKinds.WorksiteUpgrade] = true,
	[GiantLevelConfig.EventKinds.TradeSuccess] = true,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function cloneEventRecord(record: XpEventRecord): XpEventRecord
	return {
		operationId = record.operationId,
		eventKind = record.eventKind,
		xpAwarded = record.xpAwarded,
		awardedAt = record.awardedAt,
	}
end

local function cloneResolvedUnlockSet(resolvedUnlockIds: { [string]: boolean }): { [string]: boolean }
	local cloned: { [string]: boolean } = {}
	for unlockId in pairs(resolvedUnlockIds) do
		cloned[unlockId] = true
	end
	return cloned
end

local function sortedResolvedUnlockIds(resolvedUnlockIds: { [string]: boolean }): { string }
	local ids = {}
	for unlockId in pairs(resolvedUnlockIds) do
		table.insert(ids, unlockId)
	end
	table.sort(ids)
	return ids
end

local function getCatalogEntriesForLevel(level: number): { any }
	local catalog = GiantLevelConfig.LevelUnlockCatalog
	if type(catalog) ~= "table" then
		return {}
	end
	local entries = catalog[level]
	if type(entries) ~= "table" then
		return {}
	end
	return entries
end

local function applyPositiveMultiplier(current: number, nextValue: any): number
	if isFiniteNumber(nextValue) and nextValue > 1 then
		return current * nextValue
	end
	return current
end

function GiantLevelState.GetMaxLevel(): number
	return #GiantLevelConfig.LevelThresholds
end

function GiantLevelState.ResolveLevelFromXp(xp: number): number
	local thresholds = GiantLevelConfig.LevelThresholds
	local resolvedLevel = 1
	for index = #thresholds, 2, -1 do
		if xp >= thresholds[index] then
			resolvedLevel = index
			break
		end
	end
	return resolvedLevel
end

function GiantLevelState.ResolveXpToNextLevel(xp: number, level: number): number
	local thresholds = GiantLevelConfig.LevelThresholds
	local maxLevel = #thresholds
	if level >= maxLevel then
		return 0
	end
	local nextThreshold = thresholds[level + 1]
	if type(nextThreshold) ~= "number" then
		return 0
	end
	return math.max(0, nextThreshold - xp)
end

function GiantLevelState.ResolveXpAward(eventKind: string): number?
	local award = GiantLevelConfig.XpAwardsByEventKind[eventKind]
	if type(award) == "number" and award > 0 then
		return math.floor(award)
	end
	return nil
end

function GiantLevelState.ResolveModifierSnapshot(state: State): ModifierSnapshot
	local xpAwardMultiplier = 1
	local containmentRewardMultiplier = 1

	for _, unlockId in ipairs(sortedResolvedUnlockIds(state.resolvedUnlockIds)) do
		local catalog = GiantLevelConfig.LevelUnlockCatalog
		if type(catalog) ~= "table" then
			continue
		end

		for level = 2, GiantLevelState.GetMaxLevel() do
			local entries = getCatalogEntriesForLevel(level)
			for _, entry in ipairs(entries) do
				if type(entry) == "table" and entry.unlockId == unlockId and type(entry.modifiers) == "table" then
					xpAwardMultiplier = applyPositiveMultiplier(xpAwardMultiplier, entry.modifiers.xpAwardMultiplier)
					containmentRewardMultiplier = applyPositiveMultiplier(
						containmentRewardMultiplier,
						entry.modifiers.containmentRewardMultiplier
					)
				end
			end
		end
	end

	return {
		xpAwardMultiplier = xpAwardMultiplier,
		containmentRewardMultiplier = containmentRewardMultiplier,
		resolvedUnlockIds = sortedResolvedUnlockIds(state.resolvedUnlockIds),
	}
end

function GiantLevelState.ResolveLevelUnlocks(state: State, fromLevel: number, toLevel: number): any
	if type(state) ~= "table" then
		state = GiantLevelState.CreateEmptyState()
	end
	if not isFiniteNumber(fromLevel) or not isFiniteNumber(toLevel) then
		return {
			accepted = false,
			reason = "level_range_invalid",
			state = state,
			newlyResolved = {},
		}
	end

	local startLevel = math.max(2, math.floor(fromLevel))
	local endLevel = math.min(math.floor(toLevel), GiantLevelState.GetMaxLevel())
	if endLevel < startLevel then
		return {
			accepted = true,
			reason = "no_unlock_range",
			state = state,
			newlyResolved = {},
		}
	end

	local nextState: State = {
		xp = state.xp,
		level = state.level,
		operationIds = state.operationIds,
		recentEvents = state.recentEvents,
		resolvedUnlockIds = cloneResolvedUnlockSet(state.resolvedUnlockIds),
	}
	local newlyResolved: { ResolvedUnlockRecord } = {}

	for level = startLevel, endLevel do
		local entries = getCatalogEntriesForLevel(level)
		for _, entry in ipairs(entries) do
			if type(entry) ~= "table" then
				continue
			end
			local unlockId = nonEmptyString(entry.unlockId)
			if unlockId == nil then
				continue
			end
			if nextState.resolvedUnlockIds[unlockId] == true then
				continue
			end

			nextState.resolvedUnlockIds[unlockId] = true
			table.insert(newlyResolved, {
				unlockId = unlockId,
				level = level,
				displayName = if type(entry.displayName) == "string" then entry.displayName else nil,
			})
		end
	end

	return {
		accepted = true,
		reason = if #newlyResolved > 0 then "accepted" else "no_new_unlocks",
		state = nextState,
		newlyResolved = newlyResolved,
	}
end

function GiantLevelState.ReconcileEntitledUnlocks(state: State): any
	if type(state) ~= "table" then
		state = GiantLevelState.CreateEmptyState()
	end
	return GiantLevelState.ResolveLevelUnlocks(state, 2, state.level)
end

function GiantLevelState.CreateEmptyState(): State
	return {
		xp = 0,
		level = 1,
		operationIds = {},
		recentEvents = {},
		resolvedUnlockIds = {},
	}
end

function GiantLevelState.ValidateEventRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "giant_level_event_invalid"
	end
	if nonEmptyString(record.operationId) == nil then
		return false, "giant_level_operation_id_invalid"
	end
	if VALID_EVENT_KINDS[record.eventKind] ~= true then
		return false, "giant_level_event_kind_invalid"
	end
	if not isFiniteNumber(record.xpAwarded) or record.xpAwarded <= 0 then
		return false, "giant_level_xp_awarded_invalid"
	end
	if not isFiniteNumber(record.awardedAt) or record.awardedAt < 0 then
		return false, "giant_level_awarded_at_invalid"
	end
	return true, nil
end

function GiantLevelState.ApplyXpEvent(state: State, input: any): any
	if type(state) ~= "table" then
		state = GiantLevelState.CreateEmptyState()
	end

	local operationId = nonEmptyString(input.operationId)
	if operationId == nil then
		return {
			accepted = false,
			reason = "operation_id_invalid",
			state = state,
			record = nil,
			leveledUp = false,
			previousLevel = state.level,
			newLevel = state.level,
		}
	end

	if state.operationIds[operationId] == true then
		return {
			accepted = false,
			reason = "duplicate",
			state = state,
			record = nil,
			leveledUp = false,
			previousLevel = state.level,
			newLevel = state.level,
		}
	end

	local eventKind = nonEmptyString(input.eventKind)
	if eventKind == nil or VALID_EVENT_KINDS[eventKind] ~= true then
		return {
			accepted = false,
			reason = "event_kind_invalid",
			state = state,
			record = nil,
			leveledUp = false,
			previousLevel = state.level,
			newLevel = state.level,
		}
	end

	local baseXpAward = GiantLevelState.ResolveXpAward(eventKind)
	if baseXpAward == nil then
		return {
			accepted = false,
			reason = "xp_award_invalid",
			state = state,
			record = nil,
			leveledUp = false,
			previousLevel = state.level,
			newLevel = state.level,
		}
	end

	if not isFiniteNumber(input.awardedAt) or input.awardedAt < 0 then
		return {
			accepted = false,
			reason = "awarded_at_invalid",
			state = state,
			record = nil,
			leveledUp = false,
			previousLevel = state.level,
			newLevel = state.level,
		}
	end

	local modifierSnapshot = GiantLevelState.ResolveModifierSnapshot(state)
	local xpAward = math.max(1, math.floor(baseXpAward * modifierSnapshot.xpAwardMultiplier + 0.5))

	local previousLevel = state.level
	local nextXp = state.xp + xpAward
	local nextLevel = GiantLevelState.ResolveLevelFromXp(nextXp)

	local record: XpEventRecord = {
		operationId = operationId,
		eventKind = eventKind,
		xpAwarded = xpAward,
		awardedAt = input.awardedAt,
	}

	local nextState: State = {
		xp = nextXp,
		level = nextLevel,
		operationIds = {},
		recentEvents = {},
		resolvedUnlockIds = cloneResolvedUnlockSet(state.resolvedUnlockIds),
	}
	for existingOperationId in pairs(state.operationIds) do
		nextState.operationIds[existingOperationId] = true
	end
	nextState.operationIds[operationId] = true

	for _, existing in ipairs(state.recentEvents) do
		table.insert(nextState.recentEvents, cloneEventRecord(existing))
	end
	table.insert(nextState.recentEvents, record)

	while #nextState.recentEvents > GiantLevelConfig.MaxRetainedRecentEvents do
		table.remove(nextState.recentEvents, 1)
	end

	return {
		accepted = true,
		reason = "accepted",
		state = nextState,
		record = record,
		leveledUp = nextLevel > previousLevel,
		previousLevel = previousLevel,
		newLevel = nextLevel,
	}
end

function GiantLevelState.SerializePersistenceState(state: State): any
	if type(state) ~= "table" then
		return { xp = 0, level = 1, recentEvents = {}, resolvedUnlockIds = {} }
	end

	local events = {}
	for _, record in ipairs(state.recentEvents) do
		table.insert(events, cloneEventRecord(record))
	end

	table.sort(events, function(a: XpEventRecord, b: XpEventRecord): boolean
		if a.awardedAt ~= b.awardedAt then
			return a.awardedAt < b.awardedAt
		end
		return a.operationId < b.operationId
	end)

	return {
		xp = state.xp,
		level = state.level,
		recentEvents = events,
		resolvedUnlockIds = sortedResolvedUnlockIds(state.resolvedUnlockIds),
	}
end

function GiantLevelState.ApplyPersistenceState(raw: any): any
	if raw == nil then
		return {
			accepted = true,
			reason = "cleared",
			state = GiantLevelState.CreateEmptyState(),
			needsEntitlementReconcile = false,
		}
	end

	if type(raw) ~= "table" then
		return { accepted = false, reason = "persistence_invalid" }
	end
	if not isFiniteNumber(raw.xp) or raw.xp < 0 then
		return { accepted = false, reason = "giant_level_xp_invalid" }
	end
	if not isFiniteNumber(raw.level) or raw.level < 1 then
		return { accepted = false, reason = "giant_level_level_invalid" }
	end

	local resolvedLevel = GiantLevelState.ResolveLevelFromXp(raw.xp)
	if math.floor(raw.level) ~= resolvedLevel then
		return { accepted = false, reason = "giant_level_level_xp_mismatch" }
	end

	local recentEvents: { XpEventRecord } = {}
	local operationIds: { [string]: boolean } = {}
	if raw.recentEvents ~= nil then
		if type(raw.recentEvents) ~= "table" then
			return { accepted = false, reason = "giant_level_recent_events_invalid" }
		end
		for index, record in ipairs(raw.recentEvents) do
			local valid, reason = GiantLevelState.ValidateEventRecord(record)
			if not valid then
				return {
					accepted = false,
					reason = string.format("%s index=%d", reason or "giant_level_event_invalid", index),
				}
			end
			if operationIds[record.operationId] == true then
				return {
					accepted = false,
					reason = string.format("giant_level_operation_id_duplicate index=%d", index),
				}
			end
			table.insert(recentEvents, cloneEventRecord(record))
			operationIds[record.operationId] = true
		end
	end

	local resolvedUnlockIds: { [string]: boolean } = {}
	local needsEntitlementReconcile = false
	if raw.resolvedUnlockIds ~= nil then
		if type(raw.resolvedUnlockIds) ~= "table" then
			return { accepted = false, reason = "giant_level_resolved_unlock_ids_invalid" }
		end
		local seenUnlockIds: { [string]: boolean } = {}
		for index, unlockId in ipairs(raw.resolvedUnlockIds) do
			local normalizedUnlockId = nonEmptyString(unlockId)
			if normalizedUnlockId == nil then
				return {
					accepted = false,
					reason = string.format("giant_level_resolved_unlock_id_invalid index=%d", index),
				}
			end
			if seenUnlockIds[normalizedUnlockId] == true then
				return {
					accepted = false,
					reason = string.format("giant_level_resolved_unlock_id_duplicate index=%d", index),
				}
			end
			seenUnlockIds[normalizedUnlockId] = true
			resolvedUnlockIds[normalizedUnlockId] = true
		end
	else
		needsEntitlementReconcile = resolvedLevel >= 2
	end

	return {
		accepted = true,
		reason = "accepted",
		needsEntitlementReconcile = needsEntitlementReconcile,
		state = {
			xp = math.floor(raw.xp),
			level = resolvedLevel,
			operationIds = operationIds,
			recentEvents = recentEvents,
			resolvedUnlockIds = resolvedUnlockIds,
		},
	}
end

function GiantLevelState.ResolveEventKindFromContainmentEnd(endReason: string): string?
	if endReason == "released" or endReason == "timeout" then
		return GiantLevelConfig.EventKinds.ContainmentHeld
	end
	return nil
end

return GiantLevelState
