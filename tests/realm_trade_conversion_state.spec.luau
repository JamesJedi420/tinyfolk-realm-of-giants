--!nocheck

local RealmTradeConversionConfig = require("../src/ReplicatedStorage/Shared/Config/RealmTradeConversionConfig")
local RealmTradeConversionState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTradeConversionState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local operationId = RealmTradeConversionState.BuildOperationId("handoff-op-1", "dest", 9002)
assertEqual(operationId, "trade-dest-handoff-op-1-9002", "operation id format")

local ledger = RealmTradeConversionState.CreateEmptySessionLedger()
local valid, reason = RealmTradeConversionState.ValidateSessionLedger(ledger)
assertTrue(valid, "empty ledger valid")
assertEqual(reason, nil, "empty ledger no reason")

local destAmounts = RealmTradeConversionState.ResolveAwardAmounts(RealmTradeConversionConfig.Roles.Destination)
assertTrue(destAmounts.accepted, "dest amounts accepted")
assertEqual(destAmounts.essence, 8, "dest essence")
assertEqual(destAmounts.wood, 12, "dest wood")
assertEqual(destAmounts.stone, 8, "dest stone")

local firstApply = RealmTradeConversionState.ApplyConversion(ledger, {
	operationId = operationId,
	role = RealmTradeConversionConfig.Roles.Destination,
	realmOwnerUserId = 9002,
	counterpartyUserId = 9001,
	convertedAt = 100,
})
assertTrue(firstApply.accepted, "first conversion accepted")
assertEqual(firstApply.duplicate, false, "first conversion not duplicate")
assertEqual(firstApply.ledger.essence, 8, "ledger essence after first")
assertEqual(firstApply.ledger.wood, 12, "ledger wood after first")
assertEqual(firstApply.ledger.stone, 8, "ledger stone after first")
assertEqual(#firstApply.ledger.recentConversions, 1, "one recent conversion")

local duplicateApply = RealmTradeConversionState.ApplyConversion(firstApply.ledger, {
	operationId = operationId,
	role = RealmTradeConversionConfig.Roles.Destination,
	realmOwnerUserId = 9002,
	counterpartyUserId = 9001,
	convertedAt = 101,
})
assertTrue(duplicateApply.accepted, "duplicate conversion accepted")
assertEqual(duplicateApply.duplicate, true, "duplicate flagged")
assertEqual(duplicateApply.ledger.essence, 8, "ledger unchanged on duplicate")

local sourceOperationId = RealmTradeConversionState.BuildOperationId("handoff-op-1", "source", 9001)
local sourceApply = RealmTradeConversionState.ApplyConversion(firstApply.ledger, {
	operationId = sourceOperationId,
	role = RealmTradeConversionConfig.Roles.Source,
	realmOwnerUserId = 9001,
	counterpartyUserId = 9002,
	convertedAt = 102,
})
assertTrue(sourceApply.accepted, "source conversion accepted")
assertEqual(sourceApply.ledger.essence, 8 + 5, "ledger essence after source")
assertEqual(sourceApply.ledger.wood, 12 + 10, "ledger wood after source")
assertEqual(#sourceApply.ledger.recentConversions, 2, "two recent conversions")

local invalidRole = RealmTradeConversionState.ResolveAwardAmounts("invalid")
assertEqual(invalidRole.accepted, false, "invalid role rejected")
assertEqual(invalidRole.reason, "trade_role_invalid", "invalid role reason")

print("realm_trade_conversion_state.spec.luau: all checks passed")
