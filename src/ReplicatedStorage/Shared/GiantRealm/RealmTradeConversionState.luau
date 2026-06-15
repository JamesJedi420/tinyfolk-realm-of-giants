--!strict

local RealmTradeConversionConfig = require("../Config/RealmTradeConversionConfig")

local RealmTradeConversionState: any = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
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

local function cloneConversionEntry(entry: any): any
	return {
		operationId = entry.operationId,
		role = entry.role,
		realmOwnerUserId = entry.realmOwnerUserId,
		counterpartyUserId = entry.counterpartyUserId,
		convertedAt = entry.convertedAt,
		essence = entry.essence,
		wood = entry.wood,
		stone = entry.stone,
	}
end

function RealmTradeConversionState.BuildOperationId(
	baseOperationId: string,
	role: string,
	realmOwnerUserId: number
): string
	return string.format("trade-%s-%s-%d", role, baseOperationId, realmOwnerUserId)
end

function RealmTradeConversionState.CreateEmptySessionLedger(): any
	return {
		essence = 0,
		wood = 0,
		stone = 0,
		recentConversions = {},
	}
end

function RealmTradeConversionState.ResolveAwardAmounts(role: string): any
	local award = if type(RealmTradeConversionConfig.AwardByRole) == "table"
		then RealmTradeConversionConfig.AwardByRole[role]
		else nil
	if type(award) ~= "table" then
		return {
			accepted = false,
			reason = "trade_role_invalid",
			essence = 0,
			wood = 0,
			stone = 0,
		}
	end

	local essence = if isFiniteNumber(award.essence) and award.essence >= 0 then award.essence else 0
	local wood = if isFiniteNumber(award.wood) and award.wood >= 0 then award.wood else 0
	local stone = if isFiniteNumber(award.stone) and award.stone >= 0 then award.stone else 0
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

function RealmTradeConversionState.ValidateSessionLedger(ledger: any): (boolean, string?)
	if type(ledger) ~= "table" then
		return false, "conversion_ledger_invalid"
	end
	if not isFiniteNumber(ledger.essence) or ledger.essence < 0 then
		return false, "conversion_ledger_essence_invalid"
	end
	if not isFiniteNumber(ledger.wood) or ledger.wood < 0 then
		return false, "conversion_ledger_wood_invalid"
	end
	if not isFiniteNumber(ledger.stone) or ledger.stone < 0 then
		return false, "conversion_ledger_stone_invalid"
	end
	if type(ledger.recentConversions) ~= "table" then
		return false, "conversion_ledger_recent_invalid"
	end

	local seenOperationIds: { [string]: boolean } = {}
	for index, entry in ipairs(ledger.recentConversions) do
		if type(entry) ~= "table" then
			return false, string.format("conversion_record_invalid index=%d", index)
		end
		local operationId = nonEmptyString(entry.operationId)
		if operationId == nil then
			return false, string.format("conversion_operation_id_invalid index=%d", index)
		end
		if seenOperationIds[operationId] then
			return false, string.format("conversion_operation_id_duplicate index=%d", index)
		end
		seenOperationIds[operationId] = true

		local role = nonEmptyString(entry.role)
		if role == nil or RealmTradeConversionState.ResolveAwardAmounts(role).accepted ~= true then
			return false, string.format("conversion_role_invalid index=%d", index)
		end
		if not isPositiveInteger(entry.realmOwnerUserId) then
			return false, string.format("conversion_realm_owner_invalid index=%d", index)
		end
		if entry.counterpartyUserId ~= nil and not isPositiveInteger(entry.counterpartyUserId) then
			return false, string.format("conversion_counterparty_invalid index=%d", index)
		end
		if not isFiniteNumber(entry.convertedAt) or entry.convertedAt < 0 then
			return false, string.format("conversion_converted_at_invalid index=%d", index)
		end
		if not isFiniteNumber(entry.essence) or entry.essence < 0 then
			return false, string.format("conversion_essence_invalid index=%d", index)
		end
		if not isFiniteNumber(entry.wood) or entry.wood < 0 then
			return false, string.format("conversion_wood_invalid index=%d", index)
		end
		if not isFiniteNumber(entry.stone) or entry.stone < 0 then
			return false, string.format("conversion_stone_invalid index=%d", index)
		end
	end

	return true, nil
end

function RealmTradeConversionState.HasOperationId(ledger: any, operationId: string): boolean
	if type(ledger) ~= "table" or type(ledger.recentConversions) ~= "table" then
		return false
	end
	for _, entry in ipairs(ledger.recentConversions) do
		if type(entry) == "table" and entry.operationId == operationId then
			return true
		end
	end
	return false
end

function RealmTradeConversionState.ApplyConversion(ledger: any, conversion: any): any
	if type(ledger) ~= "table" then
		return { accepted = false, reason = "ledger_invalid" }
	end
	if type(conversion) ~= "table" then
		return { accepted = false, reason = "conversion_invalid" }
	end

	local operationId = nonEmptyString(conversion.operationId)
	if operationId == nil then
		return { accepted = false, reason = "operation_id_invalid" }
	end
	if RealmTradeConversionState.HasOperationId(ledger, operationId) then
		return {
			accepted = true,
			reason = "duplicate_operation",
			duplicate = true,
			ledger = ledger,
		}
	end

	local role = nonEmptyString(conversion.role)
	if role == nil then
		return { accepted = false, reason = "trade_role_invalid" }
	end
	if not isPositiveInteger(conversion.realmOwnerUserId) then
		return { accepted = false, reason = "realm_owner_invalid" }
	end
	if conversion.counterpartyUserId ~= nil and not isPositiveInteger(conversion.counterpartyUserId) then
		return { accepted = false, reason = "counterparty_user_id_invalid" }
	end
	if not isFiniteNumber(conversion.convertedAt) or conversion.convertedAt < 0 then
		return { accepted = false, reason = "converted_at_invalid" }
	end

	local amounts = RealmTradeConversionState.ResolveAwardAmounts(role)
	if amounts.accepted ~= true then
		return { accepted = false, reason = amounts.reason or "award_amount_invalid" }
	end

	local essence = if isFiniteNumber(conversion.essence) and conversion.essence >= 0
		then conversion.essence
		else amounts.essence
	local wood = if isFiniteNumber(conversion.wood) and conversion.wood >= 0 then conversion.wood else amounts.wood
	local stone = if isFiniteNumber(conversion.stone) and conversion.stone >= 0 then conversion.stone else amounts.stone
	if essence <= 0 and wood <= 0 and stone <= 0 then
		return { accepted = false, reason = "award_amount_zero" }
	end

	local nextLedger = {
		essence = ledger.essence + essence,
		wood = ledger.wood + wood,
		stone = ledger.stone + stone,
		recentConversions = {},
	}

	if type(ledger.recentConversions) == "table" then
		for _, existing in ipairs(ledger.recentConversions) do
			table.insert(nextLedger.recentConversions, cloneConversionEntry(existing))
		end
	end

	local entry = cloneConversionEntry({
		operationId = operationId,
		role = role,
		realmOwnerUserId = math.floor(conversion.realmOwnerUserId),
		counterpartyUserId = if conversion.counterpartyUserId ~= nil
			then math.floor(conversion.counterpartyUserId)
			else nil,
		convertedAt = conversion.convertedAt,
		essence = essence,
		wood = wood,
		stone = stone,
	})
	table.insert(nextLedger.recentConversions, entry)

	while #nextLedger.recentConversions > RealmTradeConversionConfig.MaxRetainedRecentConversions do
		table.remove(nextLedger.recentConversions, 1)
	end

	local valid, validateReason = RealmTradeConversionState.ValidateSessionLedger(nextLedger)
	if not valid then
		return { accepted = false, reason = validateReason or "ledger_validation_failed" }
	end

	return {
		accepted = true,
		reason = "accepted",
		duplicate = false,
		ledger = nextLedger,
		conversion = entry,
	}
end

return RealmTradeConversionState
