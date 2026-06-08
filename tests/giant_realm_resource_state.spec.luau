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
	local amounts = GiantRealmResourceState.ComputeAwardAmounts(
		GiantRealmResourceState.SourceKinds.ShrineTributeTick,
		{ generatedAmount = 4 },
		1
	)
	assertTrue(amounts.accepted, "shrine tribute accepted")
	assertEqual(amounts.essence, 2, "shrine tribute essence half rounded")
end

do
	local amounts = GiantRealmResourceState.ComputeAwardAmounts(
		GiantRealmResourceState.SourceKinds.RescueContractDefenseFailure,
		{},
		1
	)
	assertTrue(amounts.accepted, "rescue defense failure accepted")
	assertEqual(amounts.essence, 4, "rescue defense essence")
	assertEqual(amounts.wood, 2, "rescue defense wood")
	assertEqual(amounts.stone, 2, "rescue defense stone")
end

do
	local ledger = GiantRealmResourceState.CreateEmptyLedger()
	ledger.wood = 20
	ledger.stone = 10

	local spent = GiantRealmResourceState.ApplySpend(ledger, {
		operationId = "structure-spend-1",
		spendKind = GiantRealmResourceState.SpendKinds.StructurePlacement,
		spentAt = 2,
		essence = 0,
		wood = 12,
		stone = 8,
	})
	assertTrue(spent.accepted, "structure spend accepted")
	assertEqual(spent.ledger.wood, 8, "ledger wood after spend")
	assertEqual(spent.ledger.stone, 2, "ledger stone after spend")
	assertEqual(#spent.ledger.recentSpends, 1, "recent spend count")
end

do
	local ledger = GiantRealmResourceState.CreateEmptyLedger()
	ledger.essence = 8
	ledger.wood = 20
	ledger.stone = 10

	local spent = GiantRealmResourceState.ApplySpend(ledger, {
		operationId = "worksite-spend-1",
		spendKind = GiantRealmResourceState.SpendKinds.WorksiteUpgrade,
		spentAt = 3,
		essence = 8,
		wood = 10,
		stone = 4,
	})
	assertTrue(spent.accepted, "worksite upgrade spend accepted")
	assertEqual(spent.ledger.essence, 0, "worksite upgrade ledger essence after spend")
	assertEqual(spent.ledger.wood, 10, "worksite upgrade ledger wood after spend")
	assertEqual(spent.spend.spendKind, "worksite_upgrade", "worksite upgrade spend kind")
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

do
	local amounts =
		GiantRealmResourceState.ComputeAwardAmounts(GiantRealmResourceState.SourceKinds.DefendedRaidRoutePressure, {
			stationId = "GiantControlStation_A",
			routeId = "EscapeRoute_A",
		}, 1)
	assertTrue(amounts.accepted, "defended raid amounts accepted")
	assertEqual(amounts.essence, 3, "defended raid essence")
	assertEqual(amounts.wood, 2, "defended raid wood")
	assertEqual(amounts.stone, 1, "defended raid stone")
end

print("giant_realm_resource_state.spec.luau: all checks passed")
