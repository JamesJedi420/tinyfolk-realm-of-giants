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

print("giant_realm_resource_resolver.spec.luau: all checks passed")
