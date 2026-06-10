--!strict

local GiantRealmResourceState: any = {}

GiantRealmResourceState.ResourceKinds = {
	Essence = "Essence",
	Wood = "Wood",
	Stone = "Stone",
}

GiantRealmResourceState.SourceKinds = {
	ContainmentCustodyEnd = "containment_custody_end",
	DefenseEscapeOutcome = "defense_escape_outcome",
	ShrineTributeTick = "shrine_tribute_tick",
	RescueContractDefenseFailure = "rescue_contract_defense_failure",
	DefendedRaidRoutePressure = "defended_raid_route_pressure",
}

GiantRealmResourceState.SpendKinds = {
	StructurePlacement = "structure_placement",
	WorksiteUpgrade = "worksite_upgrade",
}

local AWARD_HISTORY_LIMIT = 50
local SPEND_HISTORY_LIMIT = 50

local CONTAINMENT_AWARD_END_REASONS = {
	released = true,
	timeout = true,
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

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function clampRatio(value: any): number
	if not isFiniteNumber(value) then
		return 0
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function cloneAwardEntry(entry: any): any
	return {
		operationId = entry.operationId,
		sourceKind = entry.sourceKind,
		awardedAt = entry.awardedAt,
		essence = entry.essence,
		wood = entry.wood,
		stone = entry.stone,
		counterpartyUserId = entry.counterpartyUserId,
	}
end

local function cloneSpendEntry(entry: any): any
	return {
		operationId = entry.operationId,
		spendKind = entry.spendKind,
		spentAt = entry.spentAt,
		essence = entry.essence,
		wood = entry.wood,
		stone = entry.stone,
	}
end

function GiantRealmResourceState.CreateEmptyLedger(): any
	return {
		essence = 0,
		wood = 0,
		stone = 0,
		recentAwards = {},
		recentSpends = {},
	}
end

function GiantRealmResourceState.ValidateLedger(ledger: any): (boolean, string?)
	if type(ledger) ~= "table" then
		return false, "resource_ledger_invalid"
	end
	if not isFiniteNumber(ledger.essence) or ledger.essence < 0 then
		return false, "resource_ledger_essence_invalid"
	end
	if not isFiniteNumber(ledger.wood) or ledger.wood < 0 then
		return false, "resource_ledger_wood_invalid"
	end
	if not isFiniteNumber(ledger.stone) or ledger.stone < 0 then
		return false, "resource_ledger_stone_invalid"
	end
	if type(ledger.recentAwards) ~= "table" then
		return false, "resource_ledger_recent_awards_invalid"
	end
	if type(ledger.recentSpends) ~= "table" then
		return false, "resource_ledger_recent_spends_invalid"
	end

	local seenOperationIds: { [string]: boolean } = {}
	for index, award in ipairs(ledger.recentAwards) do
		if type(award) ~= "table" then
			return false, string.format("resource_award_record_invalid index=%d", index)
		end
		local operationId = nonEmptyString(award.operationId)
		if operationId == nil then
			return false, string.format("resource_award_operation_id_invalid index=%d", index)
		end
		if seenOperationIds[operationId] then
			return false, string.format("resource_award_operation_id_duplicate index=%d", index)
		end
		seenOperationIds[operationId] = true

		local sourceKind = nonEmptyString(award.sourceKind)
		if sourceKind == nil then
			return false, string.format("resource_award_source_kind_invalid index=%d", index)
		end
		if not isFiniteNumber(award.awardedAt) or award.awardedAt < 0 then
			return false, string.format("resource_award_awarded_at_invalid index=%d", index)
		end
		if not isFiniteNumber(award.essence) or award.essence < 0 then
			return false, string.format("resource_award_essence_invalid index=%d", index)
		end
		if not isFiniteNumber(award.wood) or award.wood < 0 then
			return false, string.format("resource_award_wood_invalid index=%d", index)
		end
		if not isFiniteNumber(award.stone) or award.stone < 0 then
			return false, string.format("resource_award_stone_invalid index=%d", index)
		end
		if award.counterpartyUserId ~= nil and not isPositiveInteger(award.counterpartyUserId) then
			return false, string.format("resource_award_counterparty_user_id_invalid index=%d", index)
		end
	end

	for index, spend in ipairs(ledger.recentSpends) do
		if type(spend) ~= "table" then
			return false, string.format("resource_spend_record_invalid index=%d", index)
		end
		local operationId = nonEmptyString(spend.operationId)
		if operationId == nil then
			return false, string.format("resource_spend_operation_id_invalid index=%d", index)
		end
		if seenOperationIds[operationId] then
			return false, string.format("resource_spend_operation_id_duplicate index=%d", index)
		end
		seenOperationIds[operationId] = true

		local spendKind = nonEmptyString(spend.spendKind)
		if spendKind == nil then
			return false, string.format("resource_spend_kind_invalid index=%d", index)
		end
		if not isFiniteNumber(spend.spentAt) or spend.spentAt < 0 then
			return false, string.format("resource_spend_spent_at_invalid index=%d", index)
		end
		if not isFiniteNumber(spend.essence) or spend.essence < 0 then
			return false, string.format("resource_spend_essence_invalid index=%d", index)
		end
		if not isFiniteNumber(spend.wood) or spend.wood < 0 then
			return false, string.format("resource_spend_wood_invalid index=%d", index)
		end
		if not isFiniteNumber(spend.stone) or spend.stone < 0 then
			return false, string.format("resource_spend_stone_invalid index=%d", index)
		end
	end

	return true, nil
end

function GiantRealmResourceState.ReconcileLedger(raw: any): any
	if type(raw) ~= "table" then
		return GiantRealmResourceState.CreateEmptyLedger()
	end

	local ledger = GiantRealmResourceState.CreateEmptyLedger()
	if isFiniteNumber(raw.essence) and raw.essence >= 0 then
		ledger.essence = raw.essence
	end
	if isFiniteNumber(raw.wood) and raw.wood >= 0 then
		ledger.wood = raw.wood
	end
	if isFiniteNumber(raw.stone) and raw.stone >= 0 then
		ledger.stone = raw.stone
	end

	if type(raw.recentAwards) == "table" then
		for _, award in ipairs(raw.recentAwards) do
			if type(award) == "table" and nonEmptyString(award.operationId) ~= nil then
				table.insert(ledger.recentAwards, cloneAwardEntry(award))
			end
		end
	end
	if type(raw.recentSpends) == "table" then
		for _, spend in ipairs(raw.recentSpends) do
			if type(spend) == "table" and nonEmptyString(spend.operationId) ~= nil then
				table.insert(ledger.recentSpends, cloneSpendEntry(spend))
			end
		end
	end

	local valid, _ = GiantRealmResourceState.ValidateLedger(ledger)
	if valid then
		return ledger
	end
	return GiantRealmResourceState.CreateEmptyLedger()
end

function GiantRealmResourceState.HasLedgerOperationId(ledger: any, operationId: string): boolean
	if type(ledger) ~= "table" then
		return false
	end
	if type(ledger.recentAwards) == "table" then
		for _, award in ipairs(ledger.recentAwards) do
			if type(award) == "table" and award.operationId == operationId then
				return true
			end
		end
	end
	if type(ledger.recentSpends) == "table" then
		for _, spend in ipairs(ledger.recentSpends) do
			if type(spend) == "table" and spend.operationId == operationId then
				return true
			end
		end
	end
	return false
end

function GiantRealmResourceState.HasAwardOperationId(ledger: any, operationId: string): boolean
	return GiantRealmResourceState.HasLedgerOperationId(ledger, operationId)
end

function GiantRealmResourceState.CanAffordSpend(ledger: any, essence: number, wood: number, stone: number): boolean
	if type(ledger) ~= "table" then
		return false
	end
	if not isFiniteNumber(ledger.essence) or ledger.essence < essence then
		return false
	end
	if not isFiniteNumber(ledger.wood) or ledger.wood < wood then
		return false
	end
	if not isFiniteNumber(ledger.stone) or ledger.stone < stone then
		return false
	end
	return true
end

function GiantRealmResourceState.ComputeAwardAmounts(sourceKind: string, metadata: any, pairMultiplier: number): any
	local multiplier = if isFiniteNumber(pairMultiplier) and pairMultiplier > 0 then pairMultiplier else 0
	if multiplier <= 0 then
		return {
			accepted = false,
			reason = "pair_reward_cap_reached",
			essence = 0,
			wood = 0,
			stone = 0,
		}
	end

	if sourceKind == GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd then
		local endReason = if type(metadata) == "table" then nonEmptyString(metadata.endReason) else nil
		if endReason == nil or CONTAINMENT_AWARD_END_REASONS[endReason] ~= true then
			return {
				accepted = false,
				reason = "containment_end_reason_not_rewarded",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		local ratio = clampRatio(if type(metadata) == "table" then metadata.contributionRatio else nil)
		if ratio <= 0 then
			return {
				accepted = false,
				reason = "containment_contribution_ratio_invalid",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		local levelRewardMultiplier = 1
		if type(metadata) == "table" and isFiniteNumber(metadata.levelRewardMultiplier) then
			if metadata.levelRewardMultiplier > 0 then
				levelRewardMultiplier = metadata.levelRewardMultiplier
			end
		end

		local essence = math.floor(20 * ratio * multiplier * levelRewardMultiplier + 0.5)
		local wood = math.floor(8 * ratio * multiplier * levelRewardMultiplier + 0.5)
		local stone = math.floor(4 * ratio * multiplier * levelRewardMultiplier + 0.5)
		if essence <= 0 and wood <= 0 and stone <= 0 then
			return {
				accepted = false,
				reason = "award_amount_zero",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			essence = essence,
			wood = wood,
			stone = stone,
		}
	end

	if sourceKind == GiantRealmResourceState.SourceKinds.ShrineTributeTick then
		local generatedAmount = if type(metadata) == "table"
				and isFiniteNumber(metadata.generatedAmount)
				and metadata.generatedAmount > 0
			then metadata.generatedAmount
			else 0
		if generatedAmount <= 0 then
			return {
				accepted = false,
				reason = "shrine_generated_amount_invalid",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		local essence = math.max(1, math.floor(generatedAmount * 0.5 + 0.5))
		return {
			accepted = true,
			reason = "accepted",
			essence = essence,
			wood = 0,
			stone = 0,
		}
	end

	if sourceKind == GiantRealmResourceState.SourceKinds.RescueContractDefenseFailure then
		local essence = math.floor(4 * multiplier + 0.5)
		local wood = math.floor(2 * multiplier + 0.5)
		local stone = math.floor(2 * multiplier + 0.5)
		if essence <= 0 and wood <= 0 and stone <= 0 then
			return {
				accepted = false,
				reason = "award_amount_zero",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			essence = essence,
			wood = wood,
			stone = stone,
		}
	end

	if sourceKind == GiantRealmResourceState.SourceKinds.DefendedRaidRoutePressure then
		local stationId = if type(metadata) == "table" then nonEmptyString(metadata.stationId) else nil
		local routeId = if type(metadata) == "table" then nonEmptyString(metadata.routeId) else nil
		if stationId == nil or routeId == nil then
			return {
				accepted = false,
				reason = "defended_raid_metadata_invalid",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		local defenseMultiplier = if type(metadata) == "table"
				and isFiniteNumber(metadata.defenseMultiplier)
				and metadata.defenseMultiplier > 0
			then metadata.defenseMultiplier
			else 1
		local effectiveMultiplier = multiplier * defenseMultiplier

		local essence = math.floor(3 * effectiveMultiplier + 0.5)
		local wood = math.floor(2 * effectiveMultiplier + 0.5)
		local stone = math.floor(1 * effectiveMultiplier + 0.5)
		if essence <= 0 and wood <= 0 and stone <= 0 then
			return {
				accepted = false,
				reason = "award_amount_zero",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			essence = essence,
			wood = wood,
			stone = stone,
		}
	end

	if sourceKind == GiantRealmResourceState.SourceKinds.DefenseEscapeOutcome then
		local lootValue = if type(metadata) == "table"
				and isFiniteNumber(metadata.lootValue)
				and metadata.lootValue >= 0
			then metadata.lootValue
			else 0
		local difficulty = if type(metadata) == "table"
				and isFiniteNumber(metadata.difficulty)
				and metadata.difficulty > 0
			then metadata.difficulty
			else 1

		local essence = math.floor((6 + difficulty * 2) * multiplier + 0.5)
		local wood = math.floor((4 + lootValue * 0.25) * multiplier + 0.5)
		local stone = math.floor((2 + difficulty) * multiplier + 0.5)
		if essence <= 0 and wood <= 0 and stone <= 0 then
			return {
				accepted = false,
				reason = "award_amount_zero",
				essence = 0,
				wood = 0,
				stone = 0,
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			essence = essence,
			wood = wood,
			stone = stone,
		}
	end

	return {
		accepted = false,
		reason = "source_kind_invalid",
		essence = 0,
		wood = 0,
		stone = 0,
	}
end

function GiantRealmResourceState.ApplyAward(ledger: any, award: any): any
	if type(ledger) ~= "table" then
		return { accepted = false, reason = "ledger_invalid" }
	end
	if type(award) ~= "table" then
		return { accepted = false, reason = "award_invalid" }
	end

	local operationId = nonEmptyString(award.operationId)
	if operationId == nil then
		return { accepted = false, reason = "operation_id_invalid" }
	end
	if GiantRealmResourceState.HasLedgerOperationId(ledger, operationId) then
		return {
			accepted = true,
			reason = "duplicate_operation",
			duplicate = true,
			ledger = ledger,
		}
	end

	local sourceKind = nonEmptyString(award.sourceKind)
	if sourceKind == nil then
		return { accepted = false, reason = "source_kind_invalid" }
	end
	if not isFiniteNumber(award.awardedAt) or award.awardedAt < 0 then
		return { accepted = false, reason = "awarded_at_invalid" }
	end
	if not isFiniteNumber(award.essence) or award.essence < 0 then
		return { accepted = false, reason = "award_essence_invalid" }
	end
	if not isFiniteNumber(award.wood) or award.wood < 0 then
		return { accepted = false, reason = "award_wood_invalid" }
	end
	if not isFiniteNumber(award.stone) or award.stone < 0 then
		return { accepted = false, reason = "award_stone_invalid" }
	end
	if award.counterpartyUserId ~= nil and not isPositiveInteger(award.counterpartyUserId) then
		return { accepted = false, reason = "counterparty_user_id_invalid" }
	end
	if award.essence <= 0 and award.wood <= 0 and award.stone <= 0 then
		return { accepted = false, reason = "award_amount_zero" }
	end

	local nextLedger = {
		essence = ledger.essence + award.essence,
		wood = ledger.wood + award.wood,
		stone = ledger.stone + award.stone,
		recentAwards = {},
		recentSpends = {},
	}

	for _, existing in ipairs(ledger.recentAwards) do
		table.insert(nextLedger.recentAwards, cloneAwardEntry(existing))
	end
	if type(ledger.recentSpends) == "table" then
		for _, existing in ipairs(ledger.recentSpends) do
			table.insert(nextLedger.recentSpends, cloneSpendEntry(existing))
		end
	end
	table.insert(nextLedger.recentAwards, cloneAwardEntry(award))
	while #nextLedger.recentAwards > AWARD_HISTORY_LIMIT do
		table.remove(nextLedger.recentAwards, 1)
	end

	local valid, _ = GiantRealmResourceState.ValidateLedger(nextLedger)
	if not valid then
		return { accepted = false, reason = "ledger_validation_failed" }
	end

	return {
		accepted = true,
		reason = "accepted",
		duplicate = false,
		ledger = nextLedger,
		award = cloneAwardEntry(award),
	}
end

function GiantRealmResourceState.ApplySpend(ledger: any, spend: any): any
	if type(ledger) ~= "table" then
		return { accepted = false, reason = "ledger_invalid" }
	end
	if type(spend) ~= "table" then
		return { accepted = false, reason = "spend_invalid" }
	end

	local operationId = nonEmptyString(spend.operationId)
	if operationId == nil then
		return { accepted = false, reason = "operation_id_invalid" }
	end
	if GiantRealmResourceState.HasLedgerOperationId(ledger, operationId) then
		return {
			accepted = true,
			reason = "duplicate_operation",
			duplicate = true,
			ledger = ledger,
		}
	end

	local spendKind = nonEmptyString(spend.spendKind)
	if spendKind == nil then
		return { accepted = false, reason = "spend_kind_invalid" }
	end
	if not isFiniteNumber(spend.spentAt) or spend.spentAt < 0 then
		return { accepted = false, reason = "spent_at_invalid" }
	end

	local essence = if isFiniteNumber(spend.essence) and spend.essence >= 0 then spend.essence else 0
	local wood = if isFiniteNumber(spend.wood) and spend.wood >= 0 then spend.wood else 0
	local stone = if isFiniteNumber(spend.stone) and spend.stone >= 0 then spend.stone else 0
	if essence <= 0 and wood <= 0 and stone <= 0 then
		return { accepted = false, reason = "spend_amount_zero" }
	end
	if not GiantRealmResourceState.CanAffordSpend(ledger, essence, wood, stone) then
		return { accepted = false, reason = "insufficient_resources" }
	end

	local nextLedger = {
		essence = ledger.essence - essence,
		wood = ledger.wood - wood,
		stone = ledger.stone - stone,
		recentAwards = {},
		recentSpends = {},
	}

	for _, existing in ipairs(ledger.recentAwards) do
		table.insert(nextLedger.recentAwards, cloneAwardEntry(existing))
	end
	if type(ledger.recentSpends) == "table" then
		for _, existing in ipairs(ledger.recentSpends) do
			table.insert(nextLedger.recentSpends, cloneSpendEntry(existing))
		end
	end
	table.insert(
		nextLedger.recentSpends,
		cloneSpendEntry({
			operationId = operationId,
			spendKind = spendKind,
			spentAt = spend.spentAt,
			essence = essence,
			wood = wood,
			stone = stone,
		})
	)
	while #nextLedger.recentSpends > SPEND_HISTORY_LIMIT do
		table.remove(nextLedger.recentSpends, 1)
	end

	local valid, _ = GiantRealmResourceState.ValidateLedger(nextLedger)
	if not valid then
		return { accepted = false, reason = "ledger_validation_failed" }
	end

	return {
		accepted = true,
		reason = "accepted",
		duplicate = false,
		ledger = nextLedger,
		spend = cloneSpendEntry({
			operationId = operationId,
			spendKind = spendKind,
			spentAt = spend.spentAt,
			essence = essence,
			wood = wood,
			stone = stone,
		}),
	}
end

return GiantRealmResourceState
