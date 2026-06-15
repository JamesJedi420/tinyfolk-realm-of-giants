--!nocheck

local RealmTradeConversionConfig = require("../src/ReplicatedStorage/Shared/Config/RealmTradeConversionConfig")
local RealmTradeConversionCrossRealmSyncState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/RealmTradeConversionCrossRealmSyncState")
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

local realmId = "giant_realm_9001"
local now = 100

local buffer = RealmTradeConversionCrossRealmSyncState.NewPendingConversionBuffer(realmId, now)
local valid, reason = RealmTradeConversionCrossRealmSyncState.ValidatePendingConversionBuffer(buffer)
assertTrue(valid, "empty pending buffer valid")
assertEqual(reason, nil, "empty pending buffer no reason")

local destRecord = {
	operationId = "trade-dest-handoff-op-1-9002",
	role = RealmTradeConversionConfig.Roles.Destination,
	realmOwnerUserId = 9002,
	counterpartyUserId = 9001,
	convertedAt = 101,
	essence = 8,
	wood = 12,
	stone = 8,
}
local withDest, appendReason =
	RealmTradeConversionCrossRealmSyncState.AppendPendingConversion(buffer, destRecord, 101, realmId)
assertTrue(withDest ~= nil, "append dest accepted")
assertEqual(appendReason, nil, "append dest no reason")
assertEqual(#withDest.conversions, 1, "one pending conversion")

local sourceRecord = {
	operationId = "trade-source-handoff-op-1-9001",
	role = RealmTradeConversionConfig.Roles.Source,
	realmOwnerUserId = 9001,
	counterpartyUserId = 9002,
	convertedAt = 102,
	essence = 5,
	wood = 10,
	stone = 5,
}
local withBoth, secondReason =
	RealmTradeConversionCrossRealmSyncState.AppendPendingConversion(withDest, sourceRecord, 102, realmId)
assertTrue(withBoth ~= nil, "append source accepted")
assertEqual(secondReason, nil, "append source no reason")
assertEqual(#withBoth.conversions, 2, "two pending conversions")

local encoded, encodeReason = RealmTradeConversionCrossRealmSyncState.EncodePendingConversionBuffer(withBoth :: any)
assertTrue(encoded ~= nil, "encode pending buffer")
assertEqual(encodeReason, nil, "encode no reason")

local decoded, decodeReason = RealmTradeConversionCrossRealmSyncState.DecodePendingConversionBuffer(encoded)
assertTrue(decoded ~= nil, "decode pending buffer")
assertEqual(decodeReason, nil, "decode no reason")
assertEqual(decoded.realmId, realmId, "decoded realm id")
assertEqual(#decoded.conversions, 2, "decoded conversion count")

local ledger = RealmTradeConversionState.CreateEmptySessionLedger()
local merged = RealmTradeConversionCrossRealmSyncState.MergeSessionLedgerWithPending(ledger, decoded)
assertTrue(merged.accepted, "merge session ledger accepted")
assertEqual(merged.ledger.essence, 13, "merged essence total")
assertEqual(merged.ledger.wood, 22, "merged wood total")
assertEqual(merged.ledger.stone, 13, "merged stone total")
assertEqual(#merged.ledger.recentConversions, 2, "merged recent conversion count")

local acknowledged = RealmTradeConversionCrossRealmSyncState.CollectAcknowledgedOperationIds(merged.ledger)
assertTrue(acknowledged[destRecord.operationId] == true, "dest operation acknowledged")
assertTrue(acknowledged[sourceRecord.operationId] == true, "source operation acknowledged")

local pruned = RealmTradeConversionCrossRealmSyncState.PruneAcknowledgedOperationIds(decoded, acknowledged, 110)
assertEqual(pruned, nil, "pruned buffer empty")

print("realm_trade_conversion_cross_realm_sync_state.spec.luau: all checks passed")
