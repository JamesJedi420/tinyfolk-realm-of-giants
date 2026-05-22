--!strict

local UpgradeProgressionLogic = {}

export type ProgressionStatus = "InProgress" | "Completed" | "Unavailable"

export type ProgressionState = {
	completedSteps: number,
	totalSteps: number,
	nextUpgradeId: string?,
	status: ProgressionStatus,
}

export type Kernel = {
	orderedUpgradeIds: { string },
	validUpgradeIdSet: { [string]: boolean },
	upgradeCostById: { [string]: number },
	warnings: { string },
}

local function cloneState(state: { [string]: boolean }): { [string]: boolean }
	local copied: { [string]: boolean } = {}
	for upgradeId, enabled in state do
		if enabled then
			copied[upgradeId] = true
		end
	end
	return copied
end

function UpgradeProgressionLogic.BuildKernel(upgradeOptions: { any }, effectByUpgradeId: { [string]: any }?): Kernel
	local orderedUpgradeIds: { string } = {}
	local validUpgradeIdSet: { [string]: boolean } = {}
	local upgradeCostById: { [string]: number } = {}
	local warnings: { string } = {}
	local effects = effectByUpgradeId or {}

	for _, option in upgradeOptions do
		local upgradeId = option.id
		if type(upgradeId) ~= "string" or upgradeId == "" then
			table.insert(warnings, "Invalid UpgradeOptions entry: missing or empty id")
			continue
		end

		if validUpgradeIdSet[upgradeId] then
			table.insert(warnings, string.format("Duplicate upgrade id in UpgradeOptions ignored: %s", upgradeId))
			continue
		end

		validUpgradeIdSet[upgradeId] = true
		table.insert(orderedUpgradeIds, upgradeId)

		if type(option.costEssence) == "number" and option.costEssence >= 0 then
			upgradeCostById[upgradeId] = option.costEssence
		else
			upgradeCostById[upgradeId] = 0
			table.insert(
				warnings,
				string.format("Invalid or missing costEssence for upgradeId=%s; defaulting to 0", upgradeId)
			)
		end

		if type(effects[upgradeId]) ~= "table" then
			table.insert(
				warnings,
				string.format("Missing EffectByUpgradeId entry for upgradeId=%s; defaults will apply", upgradeId)
			)
		end
	end

	if #orderedUpgradeIds == 0 then
		table.insert(warnings, "No valid upgrades found in UpgradeOptions; progression status will remain Unavailable")
	end

	return {
		orderedUpgradeIds = orderedUpgradeIds,
		validUpgradeIdSet = validUpgradeIdSet,
		upgradeCostById = upgradeCostById,
		warnings = warnings,
	}
end

function UpgradeProgressionLogic.ResolveProgressionState(kernel: Kernel, state: { [string]: boolean }): ProgressionState
	local completedSteps = 0
	local nextUpgradeId: string? = nil
	local totalSteps = #kernel.orderedUpgradeIds

	for _, upgradeId in kernel.orderedUpgradeIds do
		if state[upgradeId] == true then
			completedSteps += 1
		elseif nextUpgradeId == nil then
			nextUpgradeId = upgradeId
		end
	end

	local status: ProgressionStatus = "InProgress"
	if totalSteps == 0 then
		status = "Unavailable"
	elseif completedSteps >= totalSteps then
		status = "Completed"
	end

	return {
		completedSteps = completedSteps,
		totalSteps = totalSteps,
		nextUpgradeId = nextUpgradeId,
		status = status,
	}
end

function UpgradeProgressionLogic.RebuildUpgradeCsv(kernel: Kernel, state: { [string]: boolean }): string
	local selected: { string } = {}
	for _, upgradeId in kernel.orderedUpgradeIds do
		if state[upgradeId] == true then
			table.insert(selected, upgradeId)
		end
	end

	return table.concat(selected, ",")
end

function UpgradeProgressionLogic.ValidateSelection(
	kernel: Kernel,
	state: { [string]: boolean },
	upgradeId: string,
	hasSufficientEssence: boolean
): (boolean, string?, ProgressionState, number)
	local progression = UpgradeProgressionLogic.ResolveProgressionState(kernel, state)

	if not kernel.validUpgradeIdSet[upgradeId] then
		return false, "invalid_upgrade_id", progression, 0
	end

	if state[upgradeId] == true then
		return false, "already_selected", progression, 0
	end

	if progression.status == "Unavailable" then
		return false, "progression_unavailable", progression, 0
	end

	if progression.status == "Completed" then
		return false, "progression_completed", progression, 0
	end

	local expectedUpgradeId = progression.nextUpgradeId
	if expectedUpgradeId == nil then
		return false, "next_upgrade_missing", progression, 0
	end

	if expectedUpgradeId ~= upgradeId then
		return false,
			string.format("out_of_order expected=%s requested=%s", expectedUpgradeId, upgradeId),
			progression,
			0
	end

	local cost = kernel.upgradeCostById[upgradeId] or 0
	if cost > 0 and not hasSufficientEssence then
		return false, "insufficient_essence", progression, cost
	end

	return true, nil, progression, cost
end

function UpgradeProgressionLogic.ApplySelection(state: { [string]: boolean }, upgradeId: string): { [string]: boolean }
	local nextState = cloneState(state)
	nextState[upgradeId] = true
	return nextState
end

return UpgradeProgressionLogic
