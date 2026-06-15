--!nocheck

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local RealmTradeConversionConfig = require("../src/ReplicatedStorage/Shared/Config/RealmTradeConversionConfig")
local RealmTradeConversionProducer = require("../src/ServerScriptService/Services/RealmTradeConversionProducer")
local RealmTradeConversionService = require("../src/ServerScriptService/Services/RealmTradeConversionService")

RealmTradeConversionService.ResetForTests()

local conversionCalls = {}
local fakeConversionApi = {
	RecordTradeSuccess = function(input: any)
		table.insert(conversionCalls, input)
		return { accepted = true, reason = "accepted" }
	end,
}

local result = RealmTradeConversionProducer.RecordTradeCompletion({
	operationId = "trade-op-1",
	targetRealmId = "giant_realm_9002",
	destinationRealmOwnerUserId = 9002,
	travelerUserId = 9001,
	convertedAt = 42,
}, {
	conversionApi = fakeConversionApi,
})
assertTrue(result.accepted, "trade completion accepted")
assertEqual(#conversionCalls, 1, "trade completion calls conversion api once")
assertEqual(conversionCalls[1].operationId, "trade-op-1", "trade operation id forwarded")
assertEqual(conversionCalls[1].sourceRealmOwnerUserId, 9001, "source owner derived from traveler")
assertEqual(conversionCalls[1].destinationRealmOwnerUserId, 9002, "destination owner forwarded")

local skipped = RealmTradeConversionProducer.RecordFromHandoffEntry({
	assignmentReason = "capture",
	operationId = "capture-op",
	targetRealmId = "giant_realm_9002",
	userId = 9001,
}, 50, { conversionApi = fakeConversionApi })
assertEqual(skipped.reason, "assignment_reason_not_trade", "non-trade handoff skipped")

conversionCalls = {}
local tradeHandoff = RealmTradeConversionProducer.RecordFromHandoffEntry({
	assignmentReason = "trade",
	operationId = "trade-op-2",
	handoffToken = "trade-op-2",
	targetRealmId = "giant_realm_9002",
	realmOwnerUserId = 9002,
	userId = 9001,
}, 55, { conversionApi = fakeConversionApi })
assertTrue(tradeHandoff.accepted, "trade handoff accepted")
assertEqual(conversionCalls[1].operationId, "trade-op-2", "handoff operation id used")
assertEqual(RealmTradeConversionConfig.AwardByRole.dest.essence, 8, "dest essence configured")

RealmTradeConversionService.ResetForTests()
local globalEnv: any = getfenv()
globalEnv._GiantBuildModeService_QueryAPI = {
	GetRealmOwnerUserId = function(): number?
		return 9002
	end,
}

local serviceResult = RealmTradeConversionService.RecordTradeSuccess({
	operationId = "trade-op-3",
	sourceRealmOwnerUserId = 9001,
	destinationRealmOwnerUserId = 9002,
	convertedAt = 60,
})
assertTrue(serviceResult.accepted, "service records destination conversion")
assertTrue(type(serviceResult.destinationResult) == "table", "destination result present")
assertTrue(serviceResult.destinationResult.accepted, "destination conversion accepted")
assertEqual(serviceResult.destinationResult.duplicate, false, "destination not duplicate")

local snapshot = RealmTradeConversionService.GetSessionLedgerSnapshot(9002)
assertTrue(snapshot.accepted, "session snapshot accepted")
assertEqual(snapshot.ledger.essence, 8, "session essence total")
assertEqual(snapshot.ledger.wood, 12, "session wood total")
assertEqual(snapshot.ledger.recentConversionCount, 1, "session conversion count")

local duplicateService = RealmTradeConversionService.RecordTradeSuccess({
	operationId = "trade-op-3",
	sourceRealmOwnerUserId = 9001,
	destinationRealmOwnerUserId = 9002,
	convertedAt = 61,
})
assertTrue(duplicateService.accepted, "duplicate service call accepted")
assertTrue(duplicateService.destinationResult.duplicate, "duplicate destination conversion")

local lastSnapshot = RealmTradeConversionService.GetLastConversionSnapshot()
assertTrue(type(lastSnapshot) == "table", "last conversion snapshot stored")
assertEqual(lastSnapshot.operationId, "trade-dest-trade-op-3-9002", "last snapshot operation id")

print("realm_trade_conversion_producer_runtime_entrypoint.spec.luau: all checks passed")
