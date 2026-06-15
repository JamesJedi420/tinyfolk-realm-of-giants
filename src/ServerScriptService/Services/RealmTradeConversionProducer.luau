--!strict

local RealmTransferState = (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local RealmTradeConversionProducer: any = {}

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then
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

function RealmTradeConversionProducer.RecordTradeCompletion(input: any, deps: any?): any
	local operationId = nonEmptyString(if type(input) == "table" then input.operationId else nil)
	if operationId == nil then
		return { accepted = false, reason = "operation_id_invalid" }
	end

	local targetRealmId = nonEmptyString(if type(input) == "table" then input.targetRealmId else nil)
	if targetRealmId == nil then
		return { accepted = false, reason = "target_realm_invalid" }
	end

	local destinationRealmOwnerUserId = RealmTransferState.ParseRealmOwnerUserId(targetRealmId)
	if
		destinationRealmOwnerUserId == nil
		and type(input) == "table"
		and isPositiveInteger(input.destinationRealmOwnerUserId)
	then
		destinationRealmOwnerUserId = math.floor(input.destinationRealmOwnerUserId)
	end
	if destinationRealmOwnerUserId == nil then
		return { accepted = false, reason = "destination_owner_invalid" }
	end

	local sourceRealmOwnerUserId = if type(input) == "table" and isPositiveInteger(input.sourceRealmOwnerUserId)
		then math.floor(input.sourceRealmOwnerUserId)
		else nil
	if sourceRealmOwnerUserId == nil and type(input) == "table" and isPositiveInteger(input.travelerUserId) then
		sourceRealmOwnerUserId = math.floor(input.travelerUserId)
	end
	if sourceRealmOwnerUserId == nil then
		return { accepted = false, reason = "source_owner_invalid" }
	end

	local convertedAt = if type(input) == "table" and type(input.convertedAt) == "number"
		then input.convertedAt
		else os.time()
	local depsAny = deps
	local conversionApi = if type(depsAny) == "table" then depsAny.conversionApi else nil
	if type(conversionApi) ~= "table" or type(conversionApi.RecordTradeSuccess) ~= "function" then
		return { accepted = false, reason = "conversion_api_unavailable" }
	end

	return conversionApi.RecordTradeSuccess({
		operationId = operationId,
		sourceRealmOwnerUserId = sourceRealmOwnerUserId,
		destinationRealmOwnerUserId = destinationRealmOwnerUserId,
		sourceRealmId = RealmTransferState.FormatRealmId(sourceRealmOwnerUserId),
		destinationRealmId = RealmTransferState.FormatRealmId(destinationRealmOwnerUserId),
		convertedAt = convertedAt,
	})
end

function RealmTradeConversionProducer.RecordFromHandoffEntry(handoffEntry: any, convertedAt: number?, deps: any?): any
	if type(handoffEntry) ~= "table" then
		return { accepted = false, reason = "handoff_entry_invalid" }
	end
	if handoffEntry.assignmentReason ~= "trade" then
		return { accepted = false, reason = "assignment_reason_not_trade" }
	end

	return RealmTradeConversionProducer.RecordTradeCompletion({
		operationId = handoffEntry.operationId or handoffEntry.handoffToken,
		targetRealmId = handoffEntry.targetRealmId,
		destinationRealmOwnerUserId = handoffEntry.realmOwnerUserId,
		travelerUserId = handoffEntry.userId,
		convertedAt = convertedAt,
	}, deps)
end

return RealmTradeConversionProducer
