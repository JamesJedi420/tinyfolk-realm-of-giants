local RansomBoardState = require("../src/ReplicatedStorage/Shared/GiantRealm/RansomBoardState")
local RansomBoardConfig = require("../src/ReplicatedStorage/Shared/Config/RansomBoardConfig")
local CaptivityDurationState = require("../src/ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState")

local function assertEqual(actual: any, expected: any, message: string)
	if actual ~= expected then
		error(string.format("%s (expected=%s actual=%s)", message, tostring(expected), tostring(actual)))
	end
	print("PASS [" .. message .. "]")
end

local function assertTrue(value: any, message: string)
	if value ~= true then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function assertFalse(value: any, message: string)
	if value ~= false then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function makeRecord(overrides: any?): any
	local record = {
		custodianUserId = 100,
		targetUserId = 200,
		startedAt = 10,
		expiresAt = 18,
		captivityAnchorAt = 10,
		containmentPhase = CaptivityDurationState.Phases.captured,
		containedAt = nil,
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			record[key] = value
		end
	end
	return record
end

local state = RansomBoardState.NewState()

local terms = RansomBoardState.BuildTerms({
	record = makeRecord(),
	now = 12,
	settlementKind = RansomBoardConfig.SettlementKinds.PaymentFood,
	foodCost = 5,
}, RansomBoardConfig)
assertTrue(type(terms) == "table", "build payment terms")
assertEqual(terms.foodCost, 5, "terms food cost")
assertEqual(terms.custodianUserId, 100, "terms custodian")
assertEqual(terms.targetUserId, 200, "terms target")
assertTrue(terms.offerExpiresAt > 12, "terms offer expiry future")
assertTrue(#terms.endConditions >= 4, "terms include end conditions")

local posted = RansomBoardState.ResolvePost(state, {
	now = 12,
	custodianUserId = 100,
	targetUserId = 200,
	record = makeRecord(),
	settlementKind = RansomBoardConfig.SettlementKinds.PaymentFood,
	foodCost = 5,
	offerId = "ransom_test_1",
}, RansomBoardConfig)
assertTrue(posted.accepted == true, "post accepted")
assertTrue(posted.offer ~= nil, "post returns offer")
state = posted.state

local duplicate = RansomBoardState.ResolvePost(state, {
	now = 12.5,
	custodianUserId = 100,
	targetUserId = 200,
	record = makeRecord(),
	settlementKind = RansomBoardConfig.SettlementKinds.PaymentFood,
	foodCost = 6,
	offerId = "ransom_test_2",
}, RansomBoardConfig)
assertFalse(duplicate.accepted, "duplicate post rejected")

local settled = RansomBoardState.ResolveSettle(state, {
	now = 13,
	offerId = "ransom_test_1",
	payerUserId = 300,
	record = makeRecord(),
	canAffordFood = true,
	settlementReady = false,
})
assertTrue(settled.accepted == true, "payment settle accepted")
state = settled.state
assertTrue(RansomBoardState.GetActiveOfferByOfferId(state, "ransom_test_1") == nil, "offer removed after settle")

state = RansomBoardState.NewState()
local objectivePosted = RansomBoardState.ResolvePost(state, {
	now = 20,
	custodianUserId = 100,
	targetUserId = 200,
	record = makeRecord({ startedAt = 18, expiresAt = 26, captivityAnchorAt = 18 }),
	settlementKind = RansomBoardConfig.SettlementKinds.ObjectiveEscapeReady,
	foodCost = 0,
	offerId = "ransom_objective_1",
}, RansomBoardConfig)
assertTrue(objectivePosted.accepted == true, "objective post accepted")
state = objectivePosted.state

local objectiveRejected = RansomBoardState.ResolveSettle(state, {
	now = 21,
	offerId = "ransom_objective_1",
	payerUserId = 300,
	record = makeRecord({ startedAt = 18, expiresAt = 26, captivityAnchorAt = 18 }),
	canAffordFood = true,
	settlementReady = false,
})
assertFalse(objectiveRejected.accepted, "objective settle rejected when threshold not met")

local objectiveSettled = RansomBoardState.ResolveSettle(state, {
	now = 21,
	offerId = "ransom_objective_1",
	payerUserId = 300,
	record = makeRecord({ startedAt = 18, expiresAt = 26, captivityAnchorAt = 18 }),
	canAffordFood = true,
	settlementReady = true,
})
assertTrue(objectiveSettled.accepted == true, "objective settle accepted when ready")

state = RansomBoardState.NewState()
local cancelPosted = RansomBoardState.ResolvePost(state, {
	now = 30,
	custodianUserId = 100,
	targetUserId = 200,
	record = makeRecord({ startedAt = 28, expiresAt = 36, captivityAnchorAt = 28 }),
	settlementKind = RansomBoardConfig.SettlementKinds.PaymentFood,
	foodCost = 4,
	offerId = "ransom_cancel_1",
}, RansomBoardConfig)
state = cancelPosted.state

local cancelled = RansomBoardState.ResolveCancel(state, {
	now = 31,
	offerId = "ransom_cancel_1",
	actorUserId = 100,
})
assertTrue(cancelled.accepted == true, "custodian cancel accepted")

local expiredState = RansomBoardState.NewState()
local expiredPosted = RansomBoardState.ResolvePost(expiredState, {
	now = 0,
	custodianUserId = 100,
	targetUserId = 200,
	record = makeRecord({ startedAt = 0, expiresAt = 8, captivityAnchorAt = 0 }),
	settlementKind = RansomBoardConfig.SettlementKinds.PaymentFood,
	foodCost = 3,
	offerId = "ransom_expired_1",
}, RansomBoardConfig)
expiredState = expiredPosted.state
expiredState = RansomBoardState.PruneExpired(expiredState, 100)
assertTrue(RansomBoardState.GetActiveOfferByTargetUserId(expiredState, 200) == nil, "expired offer pruned")

print("ransom_board_state: all checks passed")
