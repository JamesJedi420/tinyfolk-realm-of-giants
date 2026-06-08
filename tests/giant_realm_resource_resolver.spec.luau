--!strict

local GiantRealmResourceResolver = require("../src/ServerScriptService/Services/GiantRealmResourceResolver")
local GiantRealmResourceState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local ledger = GiantRealmResourceState.CreateEmptyLedger()
local eventLogEntries = {}

local resolver = GiantRealmResourceResolver.Create({
	now = function()
		return 100
	end,
	ledgerApi = {
		ApplyResourceAward = function(award: any): any
			local result = GiantRealmResourceState.ApplyAward(ledger, award)
			if type(result) == "table" and type(result.ledger) == "table" then
				ledger = result.ledger
			end
			return result
		end,
	},
	eventLogApi = {
		RecordEvent = function(category: string, message: string, severity: string, at: number, metadata: any)
			table.insert(eventLogEntries, {
				category = category,
				message = message,
				severity = severity,
				at = at,
				metadata = metadata,
			})
		end,
	},
})

do
	local result = resolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd,
		operationId = "containment-op-1",
		ownerUserId = 9402,
		counterpartyUserId = 101,
		metadata = {
			endReason = "released",
			contributionRatio = 1,
		},
	})
	assertTrue(result.accepted, "containment resolve accepted")
	assertTrue(result.awardGranted, "containment award granted")
	assertEqual(ledger.essence, 20, "ledger essence after containment")
	assertEqual(#eventLogEntries, 1, "event log entry count")
end

do
	local result = resolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.ContainmentCustodyEnd,
		operationId = "containment-op-2",
		ownerUserId = 9402,
		counterpartyUserId = 101,
		metadata = {
			endReason = "released",
			contributionRatio = 1,
		},
	})
	assertTrue(result.accepted, "second pair resolve accepted")
	assertTrue(result.awardGranted, "second pair award granted")
	assertEqual(result.essence, 10, "second pair essence halved")
end

do
	local result = resolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.DefenseEscapeOutcome,
		operationId = "escape-op-1",
		ownerUserId = 9402,
		counterpartyUserId = 202,
		metadata = {
			lootValue = 8,
			difficulty = 1,
		},
	})
	assertTrue(result.awardGranted, "defense escape award granted")
	assertEqual(ledger.wood >= 6, true, "ledger wood increased")
end

do
	local result = resolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.ShrineTributeTick,
		operationId = "shrine-tribute-op-1",
		ownerUserId = 9402,
		metadata = {
			generatedAmount = 6,
			shrineId = "Shrine_A",
			tickCount = 3,
		},
	})
	assertTrue(result.awardGranted, "shrine tribute award granted")
	assertEqual(result.essence, 3, "shrine tribute essence")
end

do
	local result = resolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.RescueContractDefenseFailure,
		operationId = "rescue-defense-op-1",
		ownerUserId = 9402,
		counterpartyUserId = 303,
		metadata = {},
	})
	assertTrue(result.awardGranted, "rescue defense failure award granted")
	assertEqual(result.wood, 2, "rescue defense failure wood")
end

do
	local pairStore = {
		_counts = {},
		ReadPairCount = function(_self: any, pairKey: string, _at: number): number
			return _self._counts[pairKey] or 0
		end,
		WritePairCount = function(_self: any, pairKey: string, count: number, _at: number): boolean
			_self._counts[pairKey] = count
			return true
		end,
	}
	local storeLedger = GiantRealmResourceState.CreateEmptyLedger()
	local storeResolver = GiantRealmResourceResolver.Create({
		now = function()
			return 300
		end,
		pairHistoryStore = pairStore,
		ledgerApi = {
			ApplyResourceAward = function(award: any): any
				local result = GiantRealmResourceState.ApplyAward(storeLedger, award)
				if type(result) == "table" and type(result.ledger) == "table" then
					storeLedger = result.ledger
				end
				return result
			end,
		},
	})
	local first = storeResolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.DefenseEscapeOutcome,
		operationId = "pair-store-op-1",
		ownerUserId = 9402,
		counterpartyUserId = 404,
		metadata = { lootValue = 4, difficulty = 1 },
	})
	assertTrue(first.awardGranted, "pair store first award granted")
	local second = storeResolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.DefenseEscapeOutcome,
		operationId = "pair-store-op-2",
		ownerUserId = 9402,
		counterpartyUserId = 404,
		metadata = { lootValue = 4, difficulty = 1 },
	})
	assertEqual(second.essence, math.floor((6 + 2) * 0.5 + 0.5), "pair store second award halved")
end

do
	local defended = resolver.Resolve({
		sourceKind = GiantRealmResourceState.SourceKinds.DefendedRaidRoutePressure,
		operationId = "defended-raid-op-1",
		ownerUserId = 9402,
		metadata = {
			stationId = "GiantControlStation_A",
			routeId = "EscapeRoute_A",
		},
	})
	assertTrue(defended.awardGranted, "defended raid resolve granted")
	assertEqual(defended.essence, 3, "defended raid resolve essence")
end

print("giant_realm_resource_resolver.spec.luau: all checks passed")
