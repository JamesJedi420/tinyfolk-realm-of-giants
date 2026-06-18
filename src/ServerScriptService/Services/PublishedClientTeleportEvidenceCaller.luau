--!strict

local PublishedClientTeleportEvidence = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PublishedClientTeleportEvidence")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PublishedClientTeleportEvidence")

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmAssignmentProfileState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PlayerLocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")

local PublishedClientTeleportEvidenceCaller: any = {}

local Flows = PublishedClientTeleportEvidence.Flows
local Phases = PublishedClientTeleportEvidence.Phases
local AssignmentReason = RealmAssignmentProfileState.AssignmentReason

local TINYFOLK_PARTY_ID_PREFIX = "tinyfolk_party:"
local UNRESOLVED_REALM_ID = "giant_realm_unresolved"
local UNAVAILABLE_LOCATION_STATE = "location_unavailable"

local enabled = true
local logSink: ((string) -> ())? = nil
local environmentProvider: (() -> any)? = nil
local nowFn: (() -> number)? = nil

local diagnostics = {
	totalEmissions = 0,
	acceptedEmissions = 0,
	rejectedEmissions = 0,
	lastLogLine = nil :: string?,
	lastFlow = nil :: string?,
	lastPhase = nil :: string?,
}

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function defaultNow(): number
	return os.clock()
end

local function defaultEnvironment(): any
	if game ~= nil and type(game.GetService) == "function" then
		local okPlace, placeId = pcall(function()
			return game.PlaceId
		end)
		local okJob, jobId = pcall(function()
			return game.JobId
		end)
		local okPrivate, privateServerId = pcall(function()
			return game.PrivateServerId
		end)
		if okPlace and isPositiveInteger(placeId) and okJob and isNonEmptyString(jobId) then
			return {
				placeId = placeId,
				jobId = jobId,
				privateServerId = if okPrivate and type(privateServerId) == "string" then privateServerId else "",
			}
		end
	end

	return {
		placeId = 1,
		jobId = "job-unavailable",
		privateServerId = "",
	}
end

local function getEnvironment(): any
	if type(environmentProvider) == "function" then
		local ok, environment = pcall(environmentProvider)
		if ok and type(environment) == "table" then
			return environment
		end
	end
	return defaultEnvironment()
end

local function getLocationApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	return globalValue._PlayerLocationService_QueryAPI
end

local function resolveLocationState(userId: number): string
	local locationApi = getLocationApi()
	if type(locationApi) ~= "table" or type(locationApi.GetLocationSnapshot) ~= "function" then
		return UNAVAILABLE_LOCATION_STATE
	end

	local ok, result = pcall(function()
		return locationApi.GetLocationSnapshot(userId)
	end)
	if not ok or type(result) ~= "table" or result.accepted ~= true or type(result.snapshot) ~= "table" then
		return UNAVAILABLE_LOCATION_STATE
	end

	local snapshot = PlayerLocationState.NormalizeSnapshot(result.snapshot)
	if type(snapshot) ~= "table" or not isNonEmptyString(snapshot.location) then
		return UNAVAILABLE_LOCATION_STATE
	end

	return snapshot.location
end

local function resolveRealmId(input: any): string?
	if type(input) ~= "table" then
		return nil
	end
	if isNonEmptyString(input.realmId) then
		return input.realmId
	end
	if isNonEmptyString(input.targetRealmId) then
		return input.targetRealmId
	end
	return nil
end

local function isPartyTransferContext(input: any): boolean
	if type(input) ~= "table" then
		return false
	end

	if input.forcePartyTransfer == true then
		return true
	end

	local partyMemberCount = input.partyMemberCount
	if type(partyMemberCount) == "number" and partyMemberCount > 1 then
		return true
	end

	local partyId = input.partyId
	if type(partyId) == "string" and string.sub(partyId, 1, #TINYFOLK_PARTY_ID_PREFIX) == TINYFOLK_PARTY_ID_PREFIX then
		return true
	end

	return false
end

function PublishedClientTeleportEvidenceCaller.InferFlow(input: any): string
	if type(input) ~= "table" then
		return Flows.RealmEntry
	end

	local explicitFlow = input.flow
	if explicitFlow == Flows.RealmEntry then
		return Flows.RealmEntry
	end
	if explicitFlow == Flows.EscapeReturn then
		return Flows.EscapeReturn
	end
	if explicitFlow == Flows.FailedTransfer then
		return Flows.FailedTransfer
	end
	if explicitFlow == Flows.PartyTransfer then
		return Flows.PartyTransfer
	end

	if input.forceFailedTransfer == true then
		return Flows.FailedTransfer
	end

	local assignmentReason = input.assignmentReason
	if assignmentReason == AssignmentReason.EscapeReturn then
		return Flows.EscapeReturn
	end

	local contextFlow = input.contextFlow
	if contextFlow == "escape_return" or contextFlow == "realm_to_hub" then
		return Flows.EscapeReturn
	end

	if isPartyTransferContext(input) then
		return Flows.PartyTransfer
	end

	return Flows.RealmEntry
end

local function resolveTerminalPhase(flow: string): string
	if flow == Flows.EscapeReturn then
		return Phases.Returned
	end
	if flow == Flows.FailedTransfer then
		return Phases.Failed
	end
	return Phases.Arrived
end

function PublishedClientTeleportEvidenceCaller.ResolveTerminalPhase(flow: string): string
	return resolveTerminalPhase(flow)
end

local function recordHook(flow: string, payloadInput: any): any
	if flow == Flows.EscapeReturn then
		return PublishedClientTeleportEvidence.DebugRecordEscapeReturnTeleportEvidence(payloadInput)
	end
	if flow == Flows.FailedTransfer then
		return PublishedClientTeleportEvidence.DebugRecordFailedTransferTeleportEvidence(payloadInput)
	end
	if flow == Flows.PartyTransfer then
		return PublishedClientTeleportEvidence.DebugRecordPartyTransferTeleportEvidence(payloadInput)
	end
	return PublishedClientTeleportEvidence.DebugRecordRealmEntryTeleportEvidence(payloadInput)
end

local function emitLogLine(logLine: string?)
	if type(logLine) ~= "string" or logLine == "" then
		return
	end

	if type(logSink) == "function" then
		local ok = pcall(logSink, logLine)
		if ok then
			return
		end
	end

	print(logLine)
end

function PublishedClientTeleportEvidenceCaller.Record(input: any): boolean
	if enabled ~= true then
		return false
	end
	if type(input) ~= "table" then
		return false
	end

	local userId = input.userId
	if not isPositiveInteger(userId) then
		return false
	end

	local phase = input.phase
	if not isNonEmptyString(phase) then
		return false
	end

	local resultReason = input.resultReason
	if not isNonEmptyString(resultReason) then
		return false
	end

	local flow = PublishedClientTeleportEvidenceCaller.InferFlow(input)
	local realmId = resolveRealmId(input)
	if not isNonEmptyString(realmId) then
		if phase == Phases.Failed or input.allowUnresolvedRealmId == true then
			realmId = UNRESOLVED_REALM_ID
		else
			return false
		end
	end

	local environment = getEnvironment()
	local placeId = environment.placeId
	local jobId = environment.jobId
	local privateServerId = environment.privateServerId
	if not isPositiveInteger(placeId) or not isNonEmptyString(jobId) or type(privateServerId) ~= "string" then
		return false
	end

	local timestamp = if type(input.timestamp) == "number"
		then input.timestamp
		else (if type(nowFn) == "function" then nowFn() else defaultNow())

	local payloadInput: any = {
		flow = flow,
		phase = phase,
		resultReason = resultReason,
		timestamp = timestamp,
		placeId = placeId,
		jobId = jobId,
		privateServerId = privateServerId,
		realmId = realmId,
		userId = userId,
		locationState = if isNonEmptyString(input.locationState)
			then input.locationState
			else resolveLocationState(userId),
		sourcePlaceId = input.sourcePlaceId,
		targetPlaceId = input.targetPlaceId,
		role = input.role,
		partyId = input.partyId,
		transferId = if isNonEmptyString(input.transferId) then input.transferId else input.operationId,
	}

	diagnostics.totalEmissions += 1
	diagnostics.lastFlow = flow
	diagnostics.lastPhase = phase

	local ok, hookResult = pcall(function()
		return recordHook(flow, payloadInput)
	end)
	if not ok or type(hookResult) ~= "table" then
		diagnostics.rejectedEmissions += 1
		warn("[PublishedClientTeleportEvidenceCaller] evidence hook fault")
		return false
	end

	if hookResult.accepted ~= true then
		diagnostics.rejectedEmissions += 1
		return false
	end

	diagnostics.acceptedEmissions += 1
	diagnostics.lastLogLine = hookResult.logLine
	emitLogLine(hookResult.logLine)
	return true
end

function PublishedClientTeleportEvidenceCaller.RecordForMembers(memberUserIds: any, input: any): number
	if type(memberUserIds) ~= "table" then
		return 0
	end

	local emitted = 0
	for _, memberUserId in ipairs(memberUserIds) do
		if not isPositiveInteger(memberUserId) then
			continue
		end

		local memberInput: any = {
			userId = memberUserId,
		}
		if type(input) == "table" then
			for key, value in pairs(input) do
				if key ~= "userId" then
					memberInput[key] = value
				end
			end
		end
		if PublishedClientTeleportEvidenceCaller.Record(memberInput) then
			emitted += 1
		end
	end

	return emitted
end

function PublishedClientTeleportEvidenceCaller.GetDiagnostics(): any
	return {
		totalEmissions = diagnostics.totalEmissions,
		acceptedEmissions = diagnostics.acceptedEmissions,
		rejectedEmissions = diagnostics.rejectedEmissions,
		lastLogLine = diagnostics.lastLogLine,
		lastFlow = diagnostics.lastFlow,
		lastPhase = diagnostics.lastPhase,
	}
end

function PublishedClientTeleportEvidenceCaller.ResetForTests()
	enabled = true
	logSink = nil
	environmentProvider = nil
	nowFn = nil
	diagnostics = {
		totalEmissions = 0,
		acceptedEmissions = 0,
		rejectedEmissions = 0,
		lastLogLine = nil,
		lastFlow = nil,
		lastPhase = nil,
	}
end

function PublishedClientTeleportEvidenceCaller.SetTestOverrides(overrides: any)
	if type(overrides) ~= "table" then
		return
	end

	if overrides.enabled == false then
		enabled = false
	elseif overrides.enabled == true then
		enabled = true
	end

	if type(overrides.logSink) == "function" then
		logSink = overrides.logSink
	end
	if type(overrides.environmentProvider) == "function" then
		environmentProvider = overrides.environmentProvider
	end
	if type(overrides.nowFn) == "function" then
		nowFn = overrides.nowFn
	end
end

return PublishedClientTeleportEvidenceCaller
