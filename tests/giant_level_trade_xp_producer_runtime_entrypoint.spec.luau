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

local GiantLevelConfig = require("../src/ReplicatedStorage/Shared/Config/GiantLevelConfig")
local GiantLevelTradeXpProducer = require("../src/ServerScriptService/Services/GiantLevelTradeXpProducer")

local grantedCalls = {}

local fakeGiantLevelApi = {
	RecordTradeSuccess = function(input: any)
		table.insert(grantedCalls, input)
		return { accepted = true, reason = "accepted" }
	end,
}

local result = GiantLevelTradeXpProducer.RecordTradeCompletion({
	operationId = "trade-op-1",
	targetRealmId = "giant_realm_9002",
	destinationRealmOwnerUserId = 9002,
	travelerUserId = 9001,
	awardedAt = 42,
}, {
	giantLevelApi = fakeGiantLevelApi,
})
assertTrue(result.accepted, "trade completion accepted")
assertEqual(#grantedCalls, 1, "trade completion calls giant level api once")
assertEqual(grantedCalls[1].operationId, "trade-op-1", "trade operation id forwarded")
assertEqual(grantedCalls[1].sourceRealmOwnerUserId, 9001, "source owner derived from traveler")
assertEqual(grantedCalls[1].destinationRealmOwnerUserId, 9002, "destination owner forwarded")

local skipped = GiantLevelTradeXpProducer.RecordFromHandoffEntry({
	assignmentReason = "capture",
	operationId = "capture-op",
	targetRealmId = "giant_realm_9002",
	userId = 9001,
}, 50, { giantLevelApi = fakeGiantLevelApi })
assertEqual(skipped.reason, "assignment_reason_not_trade", "non-trade handoff skipped")

grantedCalls = {}
local tradeHandoff = GiantLevelTradeXpProducer.RecordFromHandoffEntry({
	assignmentReason = "trade",
	operationId = "trade-op-2",
	handoffToken = "trade-op-2",
	targetRealmId = "giant_realm_9002",
	realmOwnerUserId = 9002,
	userId = 9001,
}, 55, { giantLevelApi = fakeGiantLevelApi })
assertTrue(tradeHandoff.accepted, "trade handoff accepted")
assertEqual(grantedCalls[1].operationId, "trade-op-2", "handoff operation id used")
assertEqual(GiantLevelConfig.XpAwardsByEventKind.trade_success, 30, "trade xp award configured")

print("giant_level_trade_xp_producer_runtime_entrypoint.spec.luau: all checks passed")
