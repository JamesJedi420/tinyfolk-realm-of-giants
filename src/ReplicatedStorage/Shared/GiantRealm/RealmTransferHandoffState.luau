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

export type InvalidateInput = {
	handoffToken: string,
	now: number,
}

export type ValidationResult = {
	ok: boolean,
	reason: string?,
	sessionRecord: SessionRecord?,
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

local function encodeHandoffEntry(entry: HandoffEntry): string
	local ownerUserId = if entry.realmOwnerUserId ~= nil then tostring(entry.realmOwnerUserId) else "0"
	return table.concat({
		entry.handoffToken,
		tostring(entry.userId),
		entry.operationId,
		entry.assignmentReason,
		entry.targetRealmId,
		ownerUserId,
		tostring(entry.startedAt),
		tostring(entry.expiresAt),
	}, ";")
end

local function decodeHandoffEntry(encoded: string): HandoffEntry?
	local parts = string.split(encoded, ";")
	if #parts ~= 8 then
		return nil
	end

	local userId = tonumber(parts[2])
	local realmOwnerUserId = tonumber(parts[6])
	local startedAt = tonumber(parts[7])
	local expiresAt = tonumber(parts[8])
	if userId == nil or not isPositiveInteger(userId) then
		return nil
	end
	if startedAt == nil or not validNow(startedAt) then
		return nil
	end
	if expiresAt == nil or not validNow(expiresAt) then
		return nil
	end
	if nonEmptyString(parts[1]) == nil then
		return nil
	end
	if nonEmptyString(parts[3]) == nil then
		return nil
	end
	if nonEmptyString(parts[4]) == nil then
		return nil
	end
	if nonEmptyString(parts[5]) == nil then
		return nil
	end

	return {
		handoffToken = parts[1],
		userId = userId,
		operationId = parts[3],
		assignmentReason = parts[4],
		targetRealmId = parts[5],
		realmOwnerUserId = if realmOwnerUserId ~= nil and isPositiveInteger(realmOwnerUserId)
			then realmOwnerUserId
			else nil,
		startedAt = startedAt,
		expiresAt = expiresAt,
	}
end

function RealmTransferHandoffState.ValidateSessionRecord(record: any): ValidationResult
	if type(record) ~= "table" then
		return {
			ok = false,
			reason = "session_record_invalid",
		}
	end

	local realmId = nonEmptyString(record.realmId)
	if realmId == nil then
		return {
			ok = false,
			reason = "session_realm_id_invalid",
		}
	end
	if not validNow(record.updatedAt) then
		return {
			ok = false,
			reason = "session_updated_at_invalid",
		}
	end
	if type(record.handoffsByToken) ~= "table" then
		return {
			ok = false,
			reason = "session_handoffs_invalid",
		}
	end

	local handoffsByToken: { [string]: HandoffEntry } = {}
	for token, entry in pairs(record.handoffsByToken) do
		if type(token) ~= "string" or token == "" then
			return {
				ok = false,
				reason = "session_handoff_token_invalid",
			}
		end
		if type(entry) ~= "table" then
			return {
				ok = false,
				reason = "session_handoff_entry_invalid",
			}
		end
		if entry.handoffToken ~= token then
			return {
				ok = false,
				reason = "session_handoff_token_mismatch",
			}
		end
		if not isPositiveInteger(entry.userId) then
			return {
				ok = false,
				reason = "session_handoff_user_invalid",
			}
		end
		if nonEmptyString(entry.operationId) == nil then
			return {
				ok = false,
				reason = "session_handoff_operation_invalid",
			}
		end
		if nonEmptyString(entry.assignmentReason) == nil then
			return {
				ok = false,
				reason = "session_handoff_reason_invalid",
			}
		end
		if nonEmptyString(entry.targetRealmId) == nil or entry.targetRealmId ~= realmId then
			return {
				ok = false,
				reason = "session_handoff_target_invalid",
			}
		end
		if not validNow(entry.startedAt) or not validNow(entry.expiresAt) then
			return {
				ok = false,
				reason = "session_handoff_timing_invalid",
			}
		end
		if entry.expiresAt < entry.startedAt then
			return {
				ok = false,
				reason = "session_handoff_expiry_invalid",
			}
		end
		handoffsByToken[token] = cloneHandoffEntry(entry :: HandoffEntry)
	end

	return {
		ok = true,
		reason = nil,
		sessionRecord = {
			realmId = realmId,
			updatedAt = record.updatedAt,
			handoffsByToken = handoffsByToken,
		},
	}
end

function RealmTransferHandoffState.EncodeSessionRecord(record: SessionRecord): (string?, string?)
	local validation = RealmTransferHandoffState.ValidateSessionRecord(record)
	if validation.ok ~= true or validation.sessionRecord == nil then
		return nil, validation.reason or "session_record_invalid"
	end

	local validatedRecord = validation.sessionRecord
	local handoffLines = {}
	for token, entry in pairs(validatedRecord.handoffsByToken) do
		if token ~= entry.handoffToken then
			return nil, "session_handoff_token_mismatch"
		end
		table.insert(handoffLines, encodeHandoffEntry(entry))
	end
	table.sort(handoffLines)

	local header = table.concat({
		"v1",
		validatedRecord.realmId,
		tostring(validatedRecord.updatedAt),
		tostring(#handoffLines),
	}, "|")
	if #handoffLines == 0 then
		return header, nil
	end
	return header .. "\n" .. table.concat(handoffLines, "\n"), nil
end

function RealmTransferHandoffState.DecodeSessionRecord(encoded: any): (SessionRecord?, string?)
	if type(encoded) ~= "string" or encoded == "" then
		return nil, "stored_payload_invalid"
	end

	local newlineIndex = string.find(encoded, "\n", 1, true)
	local header = if newlineIndex ~= nil then string.sub(encoded, 1, newlineIndex - 1) else encoded
	local body = if newlineIndex ~= nil then string.sub(encoded, newlineIndex + 1) else ""

	local headerParts = string.split(header, "|")
	if #headerParts ~= 4 or headerParts[1] ~= "v1" then
		return nil, "stored_payload_invalid"
	end

	local realmId = nonEmptyString(headerParts[2])
	local updatedAt = tonumber(headerParts[3])
	local handoffCount = tonumber(headerParts[4])
	if realmId == nil or updatedAt == nil or handoffCount == nil then
		return nil, "stored_payload_invalid"
	end
	if not validNow(updatedAt) or handoffCount < 0 or handoffCount % 1 ~= 0 then
		return nil, "stored_payload_invalid"
	end

	local handoffsByToken: { [string]: HandoffEntry } = {}
	if handoffCount > 0 then
		if body == "" then
			return nil, "stored_payload_invalid"
		end
		local handoffLines = string.split(body, "\n")
		if #handoffLines ~= handoffCount then
			return nil, "stored_payload_invalid"
		end
		for _, line in ipairs(handoffLines) do
			local entry = decodeHandoffEntry(line)
			if entry == nil then
				return nil, "stored_handoff_invalid"
			end
			if entry.targetRealmId ~= realmId then
				return nil, "stored_handoff_target_invalid"
			end
			handoffsByToken[entry.handoffToken] = entry
		end
	end

	return RealmTransferHandoffState.ValidateSessionRecord({
		realmId = realmId,
		updatedAt = updatedAt,
		handoffsByToken = handoffsByToken,
	}).sessionRecord,
		nil
end

function RealmTransferHandoffState.InvalidateHandoff(record: SessionRecord?, input: InvalidateInput): TransitionResult
	if record == nil then
		return reject("session_record_missing", nil, nil)
	end
	if not validNow(input.now) then
		return reject("handoff_now_invalid", record, nil)
	end

	local handoffToken = nonEmptyString(input.handoffToken)
	if handoffToken == nil then
		return reject("handoff_token_invalid", record, nil)
	end

	local now = input.now
	local entryBeforePrune = record.handoffsByToken[handoffToken]
	local nextRecord = RealmTransferHandoffState.PruneExpired(record, now)
	local entry = nextRecord.handoffsByToken[handoffToken]
	if entry == nil and entryBeforePrune == nil then
		return reject("handoff_token_not_found", nextRecord, nil)
	end

	local removedEntry = if entry ~= nil
		then cloneHandoffEntry(entry)
		else cloneHandoffEntry(entryBeforePrune :: HandoffEntry)
	nextRecord.handoffsByToken[handoffToken] = nil
	nextRecord.updatedAt = now
	return accept(nextRecord, removedEntry)
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
