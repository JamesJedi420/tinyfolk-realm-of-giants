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
}

local AWARD_HISTORY_LIMIT = 50

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

function GiantRealmResourceState.CreateEmptyLedger(): any
	return {
		essence = 0,
		wood = 0,
		stone = 0,
		recentAwards = {},
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

	local valid, _ = GiantRealmResourceState.ValidateLedger(ledger)
	if valid then
		return ledger
	end
	return GiantRealmResourceState.CreateEmptyLedger()
end

function GiantRealmResourceState.HasAwardOperationId(ledger: any, operationId: string): boolean
	if type(ledger) ~= "table" or type(ledger.recentAwards) ~= "table" then
		return false
	end
	for _, award in ipairs(ledger.recentAwards) do
		if type(award) == "table" and award.operationId == operationId then
			return true
		end
	end
	return false
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

		local essence = math.floor(20 * ratio * multiplier + 0.5)
		local wood = math.floor(8 * ratio * multiplier + 0.5)
		local stone = math.floor(4 * ratio * multiplier + 0.5)
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
	if GiantRealmResourceState.HasAwardOperationId(ledger, operationId) then
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
	}

	for _, existing in ipairs(ledger.recentAwards) do
		table.insert(nextLedger.recentAwards, cloneAwardEntry(existing))
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

return GiantRealmResourceState
