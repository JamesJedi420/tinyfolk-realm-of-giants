--!strict

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAssignmentProfileState"))
	else (require :: any)("./RealmAssignmentProfileState")

local RealmTransferHandoffState: any = {}

RealmTransferHandoffState.DEFAULT_TOKEN_TTL_SECONDS = 90

export type HandoffEntry = {
	handoffToken: string,
	userId: number,
	operationId: string,
	assignmentReason: string,
	targetRealmId: string,
	realmOwnerUserId: number?,
	startedAt: number,
	expiresAt: number,
}

export type SessionRecord = {
	realmId: string,
	updatedAt: number,
	handoffsByToken: { [string]: HandoffEntry },
}

export type BeginInput = {
	userId: number,
	targetRealmId: string,
	operationId: string?,
	assignmentReason: string?,
	now: number,
	ttlSeconds: number?,
	realmOwnerUserId: number?,
}

export type ConsumeInput = {
	userId: number,
	handoffToken: string,
	now: number,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	sessionRecord: SessionRecord?,
	handoffEntry: HandoffEntry?,
}

local validAssignmentReasonSet: { [string]: boolean } = {
	[RealmAssignmentProfileState.AssignmentReason.Capture] = true,
	[RealmAssignmentProfileState.AssignmentReason.Rescue] = true,
	[RealmAssignmentProfileState.AssignmentReason.EscapeReturn] = true,
	[RealmAssignmentProfileState.AssignmentReason.Trade] = true,
	[RealmAssignmentProfileState.AssignmentReason.PartyAdmission] = true,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
end

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function validNow(now: any): boolean
	return isFiniteNumber(now) and (now :: number) >= 0
end

local function validTtlSeconds(value: any): number
	if isFiniteNumber(value) and (value :: number) > 0 then
		return value :: number
	end
	return RealmTransferHandoffState.DEFAULT_TOKEN_TTL_SECONDS
end

local function cloneHandoffEntry(entry: HandoffEntry): HandoffEntry
	return {
		handoffToken = entry.handoffToken,
		userId = entry.userId,
		operationId = entry.operationId,
		assignmentReason = entry.assignmentReason,
		targetRealmId = entry.targetRealmId,
		realmOwnerUserId = entry.realmOwnerUserId,
		startedAt = entry.startedAt,
		expiresAt = entry.expiresAt,
	}
end

local function cloneSessionRecord(record: SessionRecord): SessionRecord
	local handoffsByToken: { [string]: HandoffEntry } = {}
	for token, entry in pairs(record.handoffsByToken) do
		handoffsByToken[token] = cloneHandoffEntry(entry)
	end
	return {
		realmId = record.realmId,
		updatedAt = record.updatedAt,
		handoffsByToken = handoffsByToken,
	}
end

local function reject(reason: string, sessionRecord: SessionRecord?, handoffEntry: HandoffEntry?): TransitionResult
	return {
		accepted = false,
		reason = reason,
		sessionRecord = if sessionRecord ~= nil then cloneSessionRecord(sessionRecord) else nil,
		handoffEntry = if handoffEntry ~= nil then cloneHandoffEntry(handoffEntry) else nil,
	}
end

local function accept(sessionRecord: SessionRecord, handoffEntry: HandoffEntry?): TransitionResult
	return {
		accepted = true,
		reason = "accepted",
		sessionRecord = cloneSessionRecord(sessionRecord),
		handoffEntry = if handoffEntry ~= nil then cloneHandoffEntry(handoffEntry) else nil,
	}
end

local function normalizeAssignmentReason(value: any): string
	local normalized = nonEmptyString(value)
	if normalized ~= nil and validAssignmentReasonSet[normalized] == true then
		return normalized
	end
	return RealmAssignmentProfileState.AssignmentReason.PartyAdmission
end

function RealmTransferHandoffState.NewSessionRecord(realmId: string, now: number): SessionRecord
	return {
		realmId = realmId,
		updatedAt = now,
		handoffsByToken = {},
	}
end

function RealmTransferHandoffState.FormatHandoffToken(userId: number, sequence: number): string
	return string.format("handoff:%d:%d", userId, sequence)
end

function RealmTransferHandoffState.PruneExpired(record: SessionRecord, now: number): SessionRecord
	local nextRecord = cloneSessionRecord(record)
	for token, entry in pairs(nextRecord.handoffsByToken) do
		if entry.expiresAt <= now then
			nextRecord.handoffsByToken[token] = nil
		end
	end
	nextRecord.updatedAt = now
	return nextRecord
end

function RealmTransferHandoffState.GetHandoffEntry(record: SessionRecord, handoffToken: string): HandoffEntry?
	local entry = record.handoffsByToken[handoffToken]
	if entry == nil then
		return nil
	end
	return cloneHandoffEntry(entry)
end

function RealmTransferHandoffState.BeginHandoff(record: SessionRecord?, input: BeginInput): TransitionResult
	if not validNow(input.now) then
		return reject("handoff_now_invalid", record, nil)
	end
	if not isPositiveInteger(input.userId) then
		return reject("handoff_user_id_invalid", record, nil)
	end

	local targetRealmId = nonEmptyString(input.targetRealmId)
	if targetRealmId == nil then
		return reject("handoff_target_realm_invalid", record, nil)
	end

	local now = input.now
	local ttlSeconds = validTtlSeconds(input.ttlSeconds)
	local operationId = nonEmptyString(input.operationId)
	local handoffToken = operationId
	if handoffToken == nil then
		return reject("handoff_operation_id_invalid", record, nil)
	end

	local nextRecord = if record ~= nil
		then RealmTransferHandoffState.PruneExpired(record, now)
		else RealmTransferHandoffState.NewSessionRecord(targetRealmId, now)

	if nextRecord.realmId ~= targetRealmId then
		return reject("handoff_realm_mismatch", nextRecord, nil)
	end

	if nextRecord.handoffsByToken[handoffToken] ~= nil then
		return reject("handoff_token_already_active", nextRecord, nil)
	end

	local realmOwnerUserId = if isPositiveInteger(input.realmOwnerUserId) then input.realmOwnerUserId else nil
	local entry: HandoffEntry = {
		handoffToken = handoffToken,
		userId = input.userId,
		operationId = handoffToken,
		assignmentReason = normalizeAssignmentReason(input.assignmentReason),
		targetRealmId = targetRealmId,
		realmOwnerUserId = realmOwnerUserId,
		startedAt = now,
		expiresAt = now + ttlSeconds,
	}

	nextRecord.handoffsByToken[handoffToken] = entry
	nextRecord.updatedAt = now
	return accept(nextRecord, entry)
end

function RealmTransferHandoffState.ConsumeHandoff(record: SessionRecord?, input: ConsumeInput): TransitionResult
	if record == nil then
		return reject("session_record_missing", nil, nil)
	end
	if not validNow(input.now) then
		return reject("handoff_now_invalid", record, nil)
	end
	if not isPositiveInteger(input.userId) then
		return reject("handoff_user_id_invalid", record, nil)
	end

	local handoffToken = nonEmptyString(input.handoffToken)
	if handoffToken == nil then
		return reject("handoff_token_invalid", record, nil)
	end

	local now = input.now
	local entryBeforePrune = record.handoffsByToken[handoffToken]
	local nextRecord = RealmTransferHandoffState.PruneExpired(record, now)
	local entry = nextRecord.handoffsByToken[handoffToken]
	if entry == nil then
		if entryBeforePrune ~= nil and entryBeforePrune.expiresAt <= now then
			nextRecord.updatedAt = now
			return reject("handoff_token_expired", nextRecord, nil)
		end
		return reject("handoff_token_not_found", nextRecord, nil)
	end
	if entry.expiresAt <= now then
		nextRecord.handoffsByToken[handoffToken] = nil
		nextRecord.updatedAt = now
		return reject("handoff_token_expired", nextRecord, nil)
	end
	if entry.userId ~= input.userId then
		return reject("handoff_user_mismatch", nextRecord, cloneHandoffEntry(entry))
	end

	nextRecord.handoffsByToken[handoffToken] = nil
	nextRecord.updatedAt = now
	return accept(nextRecord, cloneHandoffEntry(entry))
end

return RealmTransferHandoffState
