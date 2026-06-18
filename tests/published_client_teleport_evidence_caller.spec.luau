--!nocheck

local PublishedClientTeleportEvidence =
	require("../src/ReplicatedStorage/Shared/GiantRealm/PublishedClientTeleportEvidence")
local PublishedClientTeleportEvidenceCaller =
	require("../src/ServerScriptService/Services/PublishedClientTeleportEvidenceCaller")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local logLines: { string } = {}

PublishedClientTeleportEvidenceCaller.ResetForTests()
PublishedClientTeleportEvidenceCaller.SetTestOverrides({
	environmentProvider = function()
		return {
			placeId = 4242,
			jobId = "job-test",
			privateServerId = "ps-test",
		}
	end,
	nowFn = function()
		return 99.5
	end,
	logSink = function(line: string)
		table.insert(logLines, line)
	end,
})

do
	local flow = PublishedClientTeleportEvidenceCaller.InferFlow({
		assignmentReason = "escape_return",
	})
	assertEqual(flow, PublishedClientTeleportEvidence.Flows.EscapeReturn, "infer escape return from assignment reason")
end

do
	local flow = PublishedClientTeleportEvidenceCaller.InferFlow({
		partyId = "tinyfolk_party:abc",
	})
	assertEqual(flow, PublishedClientTeleportEvidence.Flows.PartyTransfer, "infer party transfer from party id")
end

do
	local accepted = PublishedClientTeleportEvidenceCaller.Record({
		userId = 9001,
		realmId = "giant_realm_9001",
		phase = PublishedClientTeleportEvidence.Phases.Requested,
		resultReason = "accepted",
		locationState = "transit",
		partyId = "party-1",
		operationId = "op-1",
	})
	assertTrue(accepted, "record realm entry requested")
	assertEqual(#logLines, 1, "one log line emitted")
	assertTrue(string.find(logLines[1], "flow=realm_entry", 1, true) ~= nil, "log line flow tag")
	assertTrue(string.find(logLines[1], "phase=requested", 1, true) ~= nil, "log line phase tag")

	local diag = PublishedClientTeleportEvidenceCaller.GetDiagnostics()
	assertEqual(diag.acceptedEmissions, 1, "accepted emission count")
	assertEqual(diag.lastFlow, "realm_entry", "last flow")
end

do
	PublishedClientTeleportEvidenceCaller.ResetForTests()
	logLines = {}
	PublishedClientTeleportEvidenceCaller.SetTestOverrides({
		environmentProvider = function()
			return {
				placeId = 4242,
				jobId = "job-test",
				privateServerId = "",
			}
		end,
		logSink = function(line: string)
			table.insert(logLines, line)
		end,
	})

	local emitted = PublishedClientTeleportEvidenceCaller.RecordForMembers({ 1, 2 }, {
		realmId = "giant_realm_42",
		phase = PublishedClientTeleportEvidence.Phases.Failed,
		resultReason = "dispatch_failed",
		forceFailedTransfer = true,
		partyMemberCount = 2,
	})
	assertEqual(emitted, 2, "record for members count")
	assertEqual(#logLines, 2, "two member log lines")
	assertTrue(string.find(logLines[1], "flow=failed_transfer", 1, true) ~= nil, "failed transfer flow")
end

do
	local terminalPhase =
		PublishedClientTeleportEvidenceCaller.ResolveTerminalPhase(PublishedClientTeleportEvidence.Flows.EscapeReturn)
	assertEqual(terminalPhase, PublishedClientTeleportEvidence.Phases.Returned, "escape return terminal phase")
end

print("published_client_teleport_evidence_caller.spec.luau: all checks passed")
