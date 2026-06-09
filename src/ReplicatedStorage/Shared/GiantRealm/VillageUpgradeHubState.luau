--!strict

local UpgradeBoardConfig = require("../Config/UpgradeBoardConfig")
local VillageUpgradeHubConfig = require("../Config/VillageUpgradeHubConfig")
local VillageWorksiteUpgradeConfig = require("../Config/VillageWorksiteUpgradeConfig")
local VillageWorksiteUpgradeState = require("./VillageWorksiteUpgradeState")

local VillageUpgradeHubState: any = {}

VillageUpgradeHubState.OwnershipKinds = {
	LegacySessionBoard = "legacy_session_board",
	RealmWorksite = "realm_worksite",
}

VillageUpgradeHubState.EntryStatuses = {
	Locked = "locked",
	Available = "available",
	Purchased = "purchased",
	Maxed = "maxed",
	Upgradeable = "upgradeable",
}

local function formatCost(cost: any): string
	if type(cost) ~= "table" then
		return ""
	end
	return string.format("W%d S%d E%d", cost.wood or 0, cost.stone or 0, cost.essence or 0)
end

local function summarizeBoardEffect(effect: any): string
	if type(effect) ~= "table" then
		return "No effect data"
	end

	local parts: { string } = {}
	if type(effect.maxHealthBonus) == "number" and effect.maxHealthBonus > 0 then
		table.insert(parts, string.format("+%d health", effect.maxHealthBonus))
	end
	if type(effect.powerBudgetBonus) == "number" and effect.powerBudgetBonus > 0 then
		table.insert(parts, string.format("+%d power budget", effect.powerBudgetBonus))
	end
	if type(effect.walkSpeedBonus) == "number" and effect.walkSpeedBonus > 0 then
		table.insert(parts, string.format("+%d walk speed", effect.walkSpeedBonus))
	end
	if type(effect.movementControlBonus) == "number" and effect.movementControlBonus > 0 then
		table.insert(parts, string.format("+%.2f movement control", effect.movementControlBonus))
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
		return "Giant housing capacity"
	end
	return "Worksite effect"
end

local function resolveBoardEntryStatus(upgradeId: string, selected: boolean, nextUpgradeId: string?): string
	if selected then
		return VillageUpgradeHubState.EntryStatuses.Purchased
	end
	if nextUpgradeId == upgradeId then
		return VillageUpgradeHubState.EntryStatuses.Available
	end
	return VillageUpgradeHubState.EntryStatuses.Locked
end

function VillageUpgradeHubState.BuildBoardTrackSnapshot(input: any): any
	local boardId = if type(input) == "table" and type(input.boardId) == "string"
		then input.boardId
		else "GiantUpgradeBoard_A"
	local selectedByUpgradeId = if type(input) == "table" and type(input.selectedByUpgradeId) == "table"
		then input.selectedByUpgradeId
		else {}
	local progression = if type(input) == "table" and type(input.progression) == "table" then input.progression else {}
	local resolvedEffects = if type(input) == "table" and type(input.resolvedEffects) == "table"
		then input.resolvedEffects
		else {}

	local entries: { any } = {}
	for _, option in UpgradeBoardConfig.UpgradeOptions do
		local upgradeId = option.id
		local selected = selectedByUpgradeId[upgradeId] == true
		local effect = UpgradeBoardConfig.EffectByUpgradeId[upgradeId]
		table.insert(entries, {
			upgradeId = upgradeId,
			label = option.label or upgradeId,
			ownership = VillageUpgradeHubState.OwnershipKinds.LegacySessionBoard,
			migrationTarget = VillageUpgradeHubConfig.LegacyMigrationTargetByUpgradeId[upgradeId],
			status = resolveBoardEntryStatus(upgradeId, selected, progression.nextUpgradeId),
			costEssence = if type(option.costEssence) == "number" then option.costEssence else nil,
			effectSummary = summarizeBoardEffect(effect),
			isActive = selected,
		})
	end

	return {
		boardId = boardId,
		trackTitle = VillageUpgradeHubConfig.BoardTrackTitle,
		trackSubtitle = VillageUpgradeHubConfig.BoardTrackSubtitle,
		progression = {
			completedSteps = progression.completedSteps or 0,
			totalSteps = progression.totalSteps or #entries,
			status = progression.status or "Unavailable",
			nextUpgradeId = progression.nextUpgradeId,
		},
		entries = entries,
		activeEffectSummary = summarizeBoardEffect({
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
	local normalizedLevel = if type(level) == "number" and level >= 0
		then math.min(math.floor(level), VillageWorksiteUpgradeConfig.MaxLevel)
		else 0
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

	return {
		worksiteId = worksiteId,
		displayLabel = displayLabel,
		ownership = VillageUpgradeHubState.OwnershipKinds.RealmWorksite,
		worksiteKind = worksiteKind,
		effectKind = effectKind,
		effectLabel = resolveEffectLabel(effectKind),
		level = normalizedLevel,
		maxLevel = maxLevel,
		status = status,
		nextCost = nextCost,
	}
end

function VillageUpgradeHubState.BuildWorksiteSummaries(levelByWorksiteId: { [string]: number }?): { any }
	local summaries: { any } = {}
	local levels = levelByWorksiteId or {}

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

	return {
		accepted = true,
		reason = "accepted",
		boardId = input.boardId,
		boardTrack = VillageUpgradeHubState.BuildBoardTrackSnapshot(input),
		worksiteSummaries = VillageUpgradeHubState.BuildWorksiteSummaries(input.levelByWorksiteId),
	}
end

function VillageUpgradeHubState.FormatBoardEntryLine(entry: any): string
	local status = entry.status or "unknown"
	local migrationHint = ""
	if type(entry.migrationTarget) == "string" then
		migrationHint = string.format(" → %s", entry.migrationTarget)
	end

	if status == VillageUpgradeHubState.EntryStatuses.Purchased then
		return string.format("• %s [legacy active]%s — %s", entry.label, migrationHint, entry.effectSummary)
	end

	if status == VillageUpgradeHubState.EntryStatuses.Available then
		return string.format(
			"• %s [legacy available, E%d]%s — %s",
			entry.label,
			entry.costEssence or 0,
			migrationHint,
			entry.effectSummary
		)
	end

	return string.format("• %s [legacy locked]%s — %s", entry.label, migrationHint, entry.effectSummary)
end

function VillageUpgradeHubState.FormatWorksiteEntryLine(entry: any): string
	local levelText = string.format("L%d/%d", entry.level or 0, entry.maxLevel or 0)
	if entry.status == VillageUpgradeHubState.EntryStatuses.Maxed then
		return string.format("• %s %s — %s (maxed)", entry.displayLabel, levelText, entry.effectLabel)
	end

	local costText = formatCost(entry.nextCost)
	return string.format(
		"• %s %s — %s (next %s at anchor)",
		entry.displayLabel,
		levelText,
		entry.effectLabel,
		costText
	)
end

return VillageUpgradeHubState
