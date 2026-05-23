--!strict

local PublishedClientTeleportEvidence = {}

PublishedClientTeleportEvidence.Flows = {
	RealmEntry = "realm_entry",
	EscapeReturn = "escape_return",
	FailedTransfer = "failed_transfer",
	PartyTransfer = "party_transfer",
}

PublishedClientTeleportEvidence.Phases = {
	Requested = "requested",
	Reserved = "reserved",
	Teleporting = "teleporting",
	Arrived = "arrived",
	Returned = "returned",
	Failed = "failed",
}

export type EvidenceInput = {
	flow: string,
	phase: string,
	resultReason: string,
	timestamp: number,
	placeId: number,
	jobId: string,
	privateServerId: string,
	realmId: string,
	userId: number,
	locationState: string,
	sourcePlaceId: number?,
	targetPlaceId: number?,
	role: string?,
	partyId: string?,
	transferId: string?,
}

export type EvidencePayload = EvidenceInput & {
	schemaVersion: number,
}

export type EvidenceResult = {
	accepted: boolean,
	reason: string,
	payload: EvidencePayload?,
}

export type DebugHookResult = EvidenceResult & {
	logLine: string?,
}

local SCHEMA_VERSION = 1

local VALID_FLOWS = {
	[PublishedClientTeleportEvidence.Flows.RealmEntry] = true,
	[PublishedClientTeleportEvidence.Flows.EscapeReturn] = true,
	[PublishedClientTeleportEvidence.Flows.FailedTransfer] = true,
	[PublishedClientTeleportEvidence.Flows.PartyTransfer] = true,
}

local VALID_PHASES = {
	[PublishedClientTeleportEvidence.Phases.Requested] = true,
	[PublishedClientTeleportEvidence.Phases.Reserved] = true,
	[PublishedClientTeleportEvidence.Phases.Teleporting] = true,
	[PublishedClientTeleportEvidence.Phases.Arrived] = true,
	[PublishedClientTeleportEvidence.Phases.Returned] = true,
	[PublishedClientTeleportEvidence.Phases.Failed] = true,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isNonNegativeNumber(value: any): boolean
	return isFiniteNumber(value) and value >= 0
end

local function isPositiveNumber(value: any): boolean
	return isFiniteNumber(value) and value > 0
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function optionalNumberIsValid(value: any): boolean
	return value == nil or isPositiveNumber(value)
end

local function optionalStringIsValid(value: any): boolean
	return value == nil or type(value) == "string"
end

local function flowIsValid(flow: any): boolean
	return type(flow) == "string" and VALID_FLOWS[flow] == true
end

local function phaseIsValid(phase: any): boolean
	return type(phase) == "string" and VALID_PHASES[phase] == true
end

function PublishedClientTeleportEvidence.BuildPayload(input: any): EvidenceResult
	if type(input) ~= "table" then
		return { accepted = false, reason = "input_invalid", payload = nil }
	end

	if not flowIsValid(input.flow) then
		return { accepted = false, reason = "flow_invalid", payload = nil }
	end

	if not phaseIsValid(input.phase) then
		return { accepted = false, reason = "phase_invalid", payload = nil }
	end

	if not isNonEmptyString(input.resultReason) then
		return { accepted = false, reason = "result_reason_invalid", payload = nil }
	end

	if not isNonNegativeNumber(input.timestamp) then
		return { accepted = false, reason = "timestamp_invalid", payload = nil }
	end

	if not isPositiveNumber(input.placeId) then
		return { accepted = false, reason = "place_id_invalid", payload = nil }
	end

	if not isNonEmptyString(input.jobId) then
		return { accepted = false, reason = "job_id_invalid", payload = nil }
	end

	if type(input.privateServerId) ~= "string" then
		return { accepted = false, reason = "private_server_id_invalid", payload = nil }
	end

	if not isNonEmptyString(input.realmId) then
		return { accepted = false, reason = "realm_id_invalid", payload = nil }
	end

	if not isPositiveNumber(input.userId) then
		return { accepted = false, reason = "user_id_invalid", payload = nil }
	end

	if not isNonEmptyString(input.locationState) then
		return { accepted = false, reason = "location_state_invalid", payload = nil }
	end

	if not optionalNumberIsValid(input.sourcePlaceId) then
		return { accepted = false, reason = "source_place_id_invalid", payload = nil }
	end

	if not optionalNumberIsValid(input.targetPlaceId) then
		return { accepted = false, reason = "target_place_id_invalid", payload = nil }
	end

	if not optionalStringIsValid(input.role) then
		return { accepted = false, reason = "role_invalid", payload = nil }
	end

	if not optionalStringIsValid(input.partyId) then
		return { accepted = false, reason = "party_id_invalid", payload = nil }
	end

	if not optionalStringIsValid(input.transferId) then
		return { accepted = false, reason = "transfer_id_invalid", payload = nil }
	end

	return {
		accepted = true,
		reason = "accepted",
		payload = {
			schemaVersion = SCHEMA_VERSION,
			flow = input.flow,
			phase = input.phase,
			resultReason = input.resultReason,
			timestamp = input.timestamp,
			placeId = input.placeId,
			jobId = input.jobId,
			privateServerId = input.privateServerId,
			realmId = input.realmId,
			userId = input.userId,
			locationState = input.locationState,
			sourcePlaceId = input.sourcePlaceId,
			targetPlaceId = input.targetPlaceId,
			role = input.role,
			partyId = input.partyId,
			transferId = input.transferId,
		},
	}
end

function PublishedClientTeleportEvidence.FormatLogLine(payload: EvidencePayload): string
	return string.format(
		"[TeleportEvidence] schemaVersion=%d flow=%s phase=%s resultReason=%s placeId=%d jobId=%s privateServerId=%s realmId=%s userId=%d locationState=%s sourcePlaceId=%s targetPlaceId=%s role=%s partyId=%s transferId=%s timestamp=%.3f",
		payload.schemaVersion,
		payload.flow,
		payload.phase,
		payload.resultReason,
		payload.placeId,
		payload.jobId,
		payload.privateServerId,
		payload.realmId,
		payload.userId,
		payload.locationState,
		tostring(payload.sourcePlaceId),
		tostring(payload.targetPlaceId),
		tostring(payload.role),
		tostring(payload.partyId),
		tostring(payload.transferId),
		payload.timestamp
	)
end

local function withFlow(input: EvidenceInput, flow: string): EvidenceInput
	return {
		flow = flow,
		phase = input.phase,
		resultReason = input.resultReason,
		timestamp = input.timestamp,
		placeId = input.placeId,
		jobId = input.jobId,
		privateServerId = input.privateServerId,
		realmId = input.realmId,
		userId = input.userId,
		locationState = input.locationState,
		sourcePlaceId = input.sourcePlaceId,
		targetPlaceId = input.targetPlaceId,
		role = input.role,
		partyId = input.partyId,
		transferId = input.transferId,
	}
end

local function buildDebugHookResult(flow: string, input: EvidenceInput): DebugHookResult
	if type(input) ~= "table" then
		local invalidResult = PublishedClientTeleportEvidence.BuildPayload(input)
		return {
			accepted = invalidResult.accepted,
			reason = invalidResult.reason,
			payload = nil,
			logLine = nil,
		}
	end

	local result = PublishedClientTeleportEvidence.BuildPayload(withFlow(input, flow))
	if result.payload == nil then
		return {
			accepted = result.accepted,
			reason = result.reason,
			payload = nil,
			logLine = nil,
		}
	end

	return {
		accepted = result.accepted,
		reason = result.reason,
		payload = result.payload,
		logLine = PublishedClientTeleportEvidence.FormatLogLine(result.payload),
	}
end

function PublishedClientTeleportEvidence.DebugRecordRealmEntryTeleportEvidence(input: EvidenceInput): DebugHookResult
	return buildDebugHookResult(PublishedClientTeleportEvidence.Flows.RealmEntry, input)
end

function PublishedClientTeleportEvidence.DebugRecordEscapeReturnTeleportEvidence(input: EvidenceInput): DebugHookResult
	return buildDebugHookResult(PublishedClientTeleportEvidence.Flows.EscapeReturn, input)
end

function PublishedClientTeleportEvidence.DebugRecordFailedTransferTeleportEvidence(
	input: EvidenceInput
): DebugHookResult
	return buildDebugHookResult(PublishedClientTeleportEvidence.Flows.FailedTransfer, input)
end

function PublishedClientTeleportEvidence.DebugRecordPartyTransferTeleportEvidence(input: EvidenceInput): DebugHookResult
	return buildDebugHookResult(PublishedClientTeleportEvidence.Flows.PartyTransfer, input)
end

return PublishedClientTeleportEvidence
