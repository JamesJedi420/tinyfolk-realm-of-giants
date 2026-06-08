--!strict

local GiantRealmResourceState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local amounts =
		GiantRealmResourceState.ComputeAwardAmounts(GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd, {
			endReason = "released",
			contributionRatio = 1,
		}, 1)
	assertTrue(amounts.accepted, "containment released accepted")
	assertEqual(amounts.essence, 20, "containment essence")
	assertEqual(amounts.wood, 8, "containment wood")
	assertEqual(amounts.stone, 4, "containment stone")
end

do
	local amounts =
		GiantRealmResourceState.ComputeAwardAmounts(GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd, {
			endReason = "escaped",
			contributionRatio = 1,
		}, 1)
	assertEqual(amounts.accepted, false, "escaped not rewarded")
	assertEqual(amounts.reason, "containment_end_reason_not_rewarded", "escaped reason")
end

do
	local amounts =
		GiantRealmResourceState.ComputeAwardAmounts(GiantRealmResourceState.SourceKinds.DefenseEscapeOutcome, {
			lootValue = 20,
			difficulty = 2,
		}, 1)
	assertTrue(amounts.accepted, "defense escape accepted")
	assertEqual(amounts.wood, 9, "defense wood")
	assertEqual(amounts.stone, 4, "defense stone")
	assertEqual(amounts.essence, 10, "defense essence")
end

do
	local ledger = GiantRealmResourceState.CreateEmptyLedger()
	local applied = GiantRealmResourceState.ApplyAward(ledger, {
		operationId = "award-1",
		sourceKind = GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd,
		awardedAt = 10,
		essence = 5,
		wood = 2,
		stone = 1,
		counterpartyUserId = 202,
	})
	assertTrue(applied.accepted, "apply award accepted")
	assertEqual(applied.ledger.essence, 5, "ledger essence total")
	assertEqual(#applied.ledger.recentAwards, 1, "recent award count")

	local duplicate = GiantRealmResourceState.ApplyAward(applied.ledger, {
		operationId = "award-1",
		sourceKind = GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd,
		awardedAt = 11,
		essence = 1,
		wood = 1,
		stone = 1,
	})
	assertEqual(duplicate.reason, "duplicate_operation", "duplicate operation")
end

do
	local reconciled = GiantRealmResourceState.ReconcileLedger({
		essence = 12,
		wood = 3,
		stone = 2,
		recentAwards = {
			{
				operationId = "award-2",
				sourceKind = GiantRealmResourceState.SourceKinds.DefenseEscapeOutcome,
				awardedAt = 20,
				essence = 1,
				wood = 1,
				stone = 1,
			},
		},
	})
	assertEqual(reconciled.essence, 12, "reconciled essence")
	assertEqual(#reconciled.recentAwards, 1, "reconciled awards")
end

print("giant_realm_resource_state.spec.luau: all checks passed")
