--!strict

local ShrineConfig = require("../Config/ShrineConfig")
local StationConfig = require("../Config/StationConfig")
local UpgradeBoardConfig = require("../Config/UpgradeBoardConfig")
local VillageUpgradeHubConfig = require("../Config/VillageUpgradeHubConfig")
local VillageWorksiteUpgradeConfig = require("../Config/VillageWorksiteUpgradeConfig")
local GiantWorksiteEffectResolution = require("./GiantWorksiteEffectResolution")
local VillageWorksiteUpgradeState = require("./VillageWorksiteUpgradeState")

local VillageUpgradeHubState: any = {}

VillageUpgradeHubState.OwnershipKinds = {
	LegacySessionBoard = "legacy_session_board",
	RealmWorksite = "realm_worksite",
}

VillageUpgradeHubState.EntryStatuses = {
	Deprecated = "deprecated",
	Maxed = "maxed",
	Upgradeable = "upgradeable",
}

local function formatCost(cost: any): string
	if type(cost) ~= "table" then
		return ""
	end
	return string.format("W%d S%d E%d", cost.wood or 0, cost.stone or 0, cost.essence or 0)
end

local function summarizeBonuses(bonuses: any): string
	if type(bonuses) ~= "table" then
		return "No active bonuses"
	end

	local parts: { string } = {}
	if type(bonuses.maxHealthBonus) == "number" and bonuses.maxHealthBonus > 0 then
		table.insert(parts, string.format("+%d health", bonuses.maxHealthBonus))
	end
	if type(bonuses.powerBudgetBonus) == "number" and bonuses.powerBudgetBonus > 0 then
		table.insert(parts, string.format("+%d power budget", bonuses.powerBudgetBonus))
	end
	if type(bonuses.walkSpeedBonus) == "number" and bonuses.walkSpeedBonus > 0 then
		table.insert(parts, string.format("+%d walk speed", bonuses.walkSpeedBonus))
	end
	if type(bonuses.movementControlBonus) == "number" and bonuses.movementControlBonus > 0 then
		table.insert(parts, string.format("+%.2f movement control", bonuses.movementControlBonus))
	end

	if #parts == 0 then
		return "No active bonuses"
	end
	return table.concat(parts, ", ")
end

local function resolveEffectLabel(effectKind: string?): string
	if effectKind == VillageWorksiteUpgradeState.EffectKinds.Production then
		return "Production throughput"
	end
	if effectKind == VillageWorksiteUpgradeState.EffectKinds.Capacity then
		return "Capacity / throughput limits"
	end
	if effectKind == VillageWorksiteUpgradeState.EffectKinds.Defense then
		return "Defense / raid mitigation"
	end
	if effectKind == VillageWorksiteUpgradeState.EffectKinds.GiantHousingCapacity then
		return "Giant housing capacity (slots only)"
	end
	return "Worksite effect"
end

local function normalizeLevel(level: any): number
	if type(level) ~= "number" or level < 0 then
		return 0
	end
	return math.min(math.floor(level), VillageWorksiteUpgradeConfig.MaxLevel)
end

function VillageUpgradeHubState.BuildBoardTrackSnapshot(input: any): any
	local boardId = if type(input) == "table" and type(input.boardId) == "string"
		then input.boardId
		else "GiantUpgradeBoard_A"
	local shrineLevel = if type(input) == "table" then normalizeLevel(input.shrineLevel) else 0
	local dwellingLevel = if type(input) == "table" then normalizeLevel(input.dwellingLevel) else 0
	local resolvedEffects = if type(input) == "table" and type(input.resolvedEffects) == "table"
		then input.resolvedEffects
		else GiantWorksiteEffectResolution.ResolveEffects({
			shrineLevel = shrineLevel,
			dwellingLevel = dwellingLevel,
		})

	local shrineBonuses = GiantWorksiteEffectResolution.ResolveShrineBonuses(shrineLevel)
	local dwellingBonuses = GiantWorksiteEffectResolution.ResolveDwellingBonuses(dwellingLevel)

	local entries: { any } = {}
	for _, option in UpgradeBoardConfig.UpgradeOptions do
		local upgradeId = option.id
		local migrationTarget = VillageUpgradeHubConfig.LegacyMigrationTargetByUpgradeId[upgradeId]
		local sourceLabel = if upgradeId == "PowerCore" then "Shrine" else "Giant Dwelling"
		local sourceLevel = if upgradeId == "PowerCore" then shrineLevel else dwellingLevel
		local contribution = if upgradeId == "PowerCore" then shrineBonuses else dwellingBonuses

		table.insert(entries, {
			upgradeId = upgradeId,
			label = option.label or upgradeId,
			ownership = VillageUpgradeHubState.OwnershipKinds.LegacySessionBoard,
			migrationTarget = migrationTarget,
			status = VillageUpgradeHubState.EntryStatuses.Deprecated,
			sourceLabel = sourceLabel,
			sourceLevel = sourceLevel,
			effectSummary = summarizeBonuses(contribution),
		})
	end

	return {
		boardId = boardId,
		trackTitle = VillageUpgradeHubConfig.BoardTrackTitle,
		trackSubtitle = VillageUpgradeHubConfig.BoardTrackSubtitle,
		progression = {
			status = "Deprecated",
			shrineLevel = shrineLevel,
			dwellingLevel = dwellingLevel,
		},
		entries = entries,
		activeEffectSummary = summarizeBonuses({
			maxHealthBonus = resolvedEffects.maxHealthBonus,
			powerBudgetBonus = resolvedEffects.powerBudgetBonus,
			walkSpeedBonus = resolvedEffects.walkSpeedBonus,
			movementControlBonus = resolvedEffects.movementControlBonus,
		}),
	}
end

function VillageUpgradeHubState.BuildWorksiteSummaryEntry(worksiteId: string, displayLabel: string, level: number): any
	local worksiteKind = VillageWorksiteUpgradeState.ResolveWorksiteKind(worksiteId)
	local effectKind = if worksiteKind ~= nil then VillageWorksiteUpgradeState.ResolveEffectKind(worksiteKind) else nil
	local normalizedLevel = normalizeLevel(level)
	local maxLevel = VillageWorksiteUpgradeConfig.MaxLevel

	local nextCost = nil
	local status = VillageUpgradeHubState.EntryStatuses.Maxed
	if worksiteKind ~= nil and normalizedLevel < maxLevel then
		local costResult = VillageWorksiteUpgradeState.ResolveUpgradeCost(worksiteKind, normalizedLevel + 1)
		if costResult.accepted == true then
			nextCost = {
				wood = costResult.wood,
				stone = costResult.stone,
				essence = costResult.essence,
			}
			status = VillageUpgradeHubState.EntryStatuses.Upgradeable
		end
	end

	local giantEffectNote = nil
	if worksiteId == ShrineConfig.DefaultShrineId then
		giantEffectNote = "Giant vitality / power budget"
	elseif worksiteId == StationConfig.DefaultGiantDwellingId then
		giantEffectNote = "Giant locomotion (not housing slots)"
	end

	return {
		worksiteId = worksiteId,
		displayLabel = displayLabel,
		ownership = VillageUpgradeHubState.OwnershipKinds.RealmWorksite,
		worksiteKind = worksiteKind,
		effectKind = effectKind,
		effectLabel = resolveEffectLabel(effectKind),
		giantEffectNote = giantEffectNote,
		level = normalizedLevel,
		maxLevel = maxLevel,
		status = status,
		nextCost = nextCost,
	}
end

function VillageUpgradeHubState.BuildWorksiteSummaries(levelByWorksiteId: { [string]: number }?): { any }
	local summaries: { any } = {}
	local levels = if type(levelByWorksiteId) == "table" then levelByWorksiteId else {}

	for _, catalogEntry in VillageUpgradeHubConfig.HubWorksiteCatalog do
		local worksiteId = catalogEntry.worksiteId
		local displayLabel = catalogEntry.displayLabel or worksiteId
		table.insert(
			summaries,
			VillageUpgradeHubState.BuildWorksiteSummaryEntry(worksiteId, displayLabel, levels[worksiteId] or 0)
		)
	end

	return summaries
end

function VillageUpgradeHubState.BuildHubSnapshot(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "hub_input_invalid",
		}
	end

	local levelByWorksiteId = if type(input.levelByWorksiteId) == "table" then input.levelByWorksiteId else {}
	local shrineLevel = if type(input.shrineLevel) == "number"
		then input.shrineLevel
		else levelByWorksiteId[ShrineConfig.DefaultShrineId] or 0
	local dwellingLevel = if type(input.dwellingLevel) == "number"
		then input.dwellingLevel
		else levelByWorksiteId[StationConfig.DefaultGiantDwellingId] or 0

	return {
		accepted = true,
		reason = "accepted",
		boardId = input.boardId,
		boardTrack = VillageUpgradeHubState.BuildBoardTrackSnapshot({
			boardId = input.boardId,
			shrineLevel = shrineLevel,
			dwellingLevel = dwellingLevel,
			resolvedEffects = input.resolvedEffects,
		}),
		worksiteSummaries = VillageUpgradeHubState.BuildWorksiteSummaries(levelByWorksiteId),
	}
end

function VillageUpgradeHubState.FormatBoardEntryLine(entry: any): string
	local migrationHint = ""
	if type(entry.migrationTarget) == "string" then
		migrationHint = string.format(" → %s", entry.migrationTarget)
	end

	return string.format(
		"• %s [deprecated]%s — %s L%d: %s",
		entry.label,
		migrationHint,
		entry.sourceLabel or "Worksite",
		entry.sourceLevel or 0,
		entry.effectSummary or "No active bonuses"
	)
end

function VillageUpgradeHubState.FormatWorksiteEntryLine(entry: any): string
	local levelText = string.format("L%d/%d", entry.level or 0, entry.maxLevel or 0)
	local effectText = entry.effectLabel or "Worksite effect"
	if type(entry.giantEffectNote) == "string" and entry.giantEffectNote ~= "" then
		effectText = string.format("%s; %s", effectText, entry.giantEffectNote)
	end

	if entry.status == VillageUpgradeHubState.EntryStatuses.Maxed then
		return string.format("• %s %s — %s (maxed)", entry.displayLabel, levelText, effectText)
	end

	local costText = formatCost(entry.nextCost)
	return string.format("• %s %s — %s (next %s at anchor)", entry.displayLabel, levelText, effectText, costText)
end

return VillageUpgradeHubState
