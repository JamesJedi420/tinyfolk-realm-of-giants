--!nocheck
local PublishedClientTeleportEvidence =
	require("../src/ReplicatedStorage/Shared/GiantRealm/PublishedClientTeleportEvidence")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function baselineInput()
	return {
		flow = PublishedClientTeleportEvidence.Flows.RealmEntry,
		phase = PublishedClientTeleportEvidence.Phases.Arrived,
		resultReason = "accepted",
		timestamp = 123.5,
		placeId = 101,
		jobId = "job-abc",
		privateServerId = "private-xyz",
		realmId = "giant_realm_9001",
		userId = 42,
		locationState = "realm",
		sourcePlaceId = 100,
		targetPlaceId = 101,
		role = "Tinyfolk",
		partyId = "party-1",
		transferId = "transfer-1",
	}
end

do
	local result = PublishedClientTeleportEvidence.BuildPayload(baselineInput())
	assertTrue(result.accepted, "valid payload accepted")
	assertEqual(result.reason, "accepted", "valid payload reason")
	assertEqual(result.payload.schemaVersion, 1, "schema version set")
	assertEqual(result.payload.flow, "realm_entry", "flow copied")
	assertEqual(result.payload.phase, "arrived", "phase copied")
	assertEqual(result.payload.placeId, 101, "placeId copied")
	assertEqual(result.payload.jobId, "job-abc", "jobId copied")
	assertEqual(result.payload.privateServerId, "private-xyz", "privateServerId copied")
	assertEqual(result.payload.realmId, "giant_realm_9001", "realmId copied")
	assertEqual(result.payload.locationState, "realm", "locationState copied")
end

do
	local result = PublishedClientTeleportEvidence.BuildPayload(nil)
	assertFalse(result.accepted, "nil input rejected")
	assertEqual(result.reason, "input_invalid", "nil input reason")
end

do
	local input = baselineInput()
	input.privateServerId = ""
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertTrue(result.accepted, "empty private server id accepted for public servers")
	assertEqual(result.payload.privateServerId, "", "empty private server id retained")
end

do
	local input = baselineInput()
	input.flow = "unknown_flow"
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "invalid flow rejected")
	assertEqual(result.reason, "flow_invalid", "invalid flow reason")
end

do
	local input = baselineInput()
	input.phase = "unknown_phase"
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "invalid phase rejected")
	assertEqual(result.reason, "phase_invalid", "invalid phase reason")
end

do
	local input = baselineInput()
	input.placeId = 0
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "zero place id rejected")
	assertEqual(result.reason, "place_id_invalid", "zero place id reason")
end

do
	local input = baselineInput()
	input.userId = 0
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "zero user id rejected")
	assertEqual(result.reason, "user_id_invalid", "zero user id reason")
end

do
	local input = baselineInput()
	input.sourcePlaceId = -1
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "negative source place id rejected")
	assertEqual(result.reason, "source_place_id_invalid", "negative source place id reason")
end

do
	local input = baselineInput()
	input.role = 12
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "non-string role rejected")
	assertEqual(result.reason, "role_invalid", "non-string role reason")
end

do
	local input = baselineInput()
	input.realmId = ""
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "missing realm id rejected")
	assertEqual(result.reason, "realm_id_invalid", "missing realm id reason")
end

do
	local input = baselineInput()
	input.jobId = ""
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "missing job id rejected")
	assertEqual(result.reason, "job_id_invalid", "missing job id reason")
end

do
	local input = baselineInput()
	input.locationState = ""
	local result = PublishedClientTeleportEvidence.BuildPayload(input)
	assertFalse(result.accepted, "missing location state rejected")
	assertEqual(result.reason, "location_state_invalid", "missing location state reason")
end

do
	local result = PublishedClientTeleportEvidence.BuildPayload(baselineInput())
	local line = PublishedClientTeleportEvidence.FormatLogLine(result.payload)
	assertTrue(string.find(line, "placeId=101", 1, true) ~= nil, "log line includes placeId")
	assertTrue(string.find(line, "jobId=job-abc", 1, true) ~= nil, "log line includes jobId")
	assertTrue(string.find(line, "privateServerId=private-xyz", 1, true) ~= nil, "log line includes privateServerId")
	assertTrue(string.find(line, "realmId=giant_realm_9001", 1, true) ~= nil, "log line includes realmId")
	assertTrue(string.find(line, "locationState=realm", 1, true) ~= nil, "log line includes locationState")
end

do
	local input = baselineInput()
	input.flow = "caller_supplied_wrong_flow"
	local result = PublishedClientTeleportEvidence.DebugRecordRealmEntryTeleportEvidence(input)
	assertTrue(result.accepted, "realm entry hook accepted")
	assertEqual(result.payload.flow, "realm_entry", "realm entry hook pins flow")
	assertTrue(string.find(result.logLine, "flow=realm_entry", 1, true) ~= nil, "realm entry hook returns log line")
end

do
	local input = baselineInput()
	input.phase = ""
	local result = PublishedClientTeleportEvidence.DebugRecordRealmEntryTeleportEvidence(input)
	assertFalse(result.accepted, "hook rejects invalid input")
	assertEqual(result.reason, "phase_invalid", "hook invalid input reason")
	assertEqual(result.logLine, nil, "hook invalid input has no log line")
end

do
	local result = PublishedClientTeleportEvidence.DebugRecordRealmEntryTeleportEvidence(nil)
	assertFalse(result.accepted, "hook rejects nil input")
	assertEqual(result.reason, "input_invalid", "hook nil input reason")
	assertEqual(result.logLine, nil, "hook nil input has no log line")
end

do
	local input = baselineInput()
	local result = PublishedClientTeleportEvidence.DebugRecordEscapeReturnTeleportEvidence(input)
	assertTrue(result.accepted, "escape return hook accepted")
	assertEqual(result.payload.flow, "escape_return", "escape return hook pins flow")
end

do
	local input = baselineInput()
	local result = PublishedClientTeleportEvidence.DebugRecordFailedTransferTeleportEvidence(input)
	assertTrue(result.accepted, "failed transfer hook accepted")
	assertEqual(result.payload.flow, "failed_transfer", "failed transfer hook pins flow")
end

do
	local input = baselineInput()
	local result = PublishedClientTeleportEvidence.DebugRecordPartyTransferTeleportEvidence(input)
	assertTrue(result.accepted, "party transfer hook accepted")
	assertEqual(result.payload.flow, "party_transfer", "party transfer hook pins flow")
end

print("published_client_teleport_evidence: all checks passed")
