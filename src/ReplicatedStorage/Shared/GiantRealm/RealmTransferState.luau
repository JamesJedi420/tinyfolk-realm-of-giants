--!strict

local PendingRecoveryProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PendingRecoveryProfileState"))
	else (require :: any)("./PendingRecoveryProfileState")

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAssignmentProfileState"))
	else (require :: any)("./RealmAssignmentProfileState")

local RealmTransferState: any = {}

RealmTransferState.SCHEMA_VERSION = 1

RealmTransferState.Operations = {
	BeginCapture = "begin_capture",
	BeginRescue = "begin_rescue",
	BeginTrade = "begin_trade",
	BeginPartyAdmission = "begin_party_admission",
	BeginEscapeReturn = "begin_escape_return",
	ConfirmArrival = "confirm_arrival",
	ConfirmHubReturn = "confirm_hub_return",
	AbortToHub = "abort_to_hub",
	SetSharedHub = "set_shared_hub",
}

local INGRESS_REASONS: { [string]: boolean } = {
	[RealmAssignmentProfileState.AssignmentReason.Capture] = true,
	[RealmAssignmentProfileState.AssignmentReason.Rescue] = true,
	[RealmAssignmentProfileState.AssignmentReason.Trade] = true,
	[RealmAssignmentProfileState.AssignmentReason.PartyAdmission] = true,
}

RealmTransferState.AssignmentReason = RealmAssignmentProfileState.AssignmentReason

export type AssignmentSnapshot = {
	locationCategory: string,
	realmId: string?,
	realmOwnerUserId: number?,
	assignmentReason: string?,
	updatedAt: number,
}

export type TransitionInput = {
	operation: string,
	now: number,
	realmOwnerUserId: number?,
	realmId: string?,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	assignment: AssignmentSnapshot?,
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

local function cloneAssignment(assignment: AssignmentSnapshot): AssignmentSnapshot
	return {
		locationCategory = assignment.locationCategory,
		realmId = assignment.realmId,
		realmOwnerUserId = assignment.realmOwnerUserId,
		assignmentReason = assignment.assignmentReason,
		updatedAt = assignment.updatedAt,
	}
end

function RealmTransferState.FormatRealmId(realmOwnerUserId: number): string
	return string.format("giant_realm_%d", realmOwnerUserId)
end

function RealmTransferState.ParseRealmOwnerUserId(realmId: any): number?
	local normalizedRealmId = nonEmptyString(realmId)
	if normalizedRealmId == nil then
		return nil
	end

	local ownerText = string.match(normalizedRealmId, "^giant_realm_(%d+)$")
	if ownerText == nil then
		return nil
	end

	local ownerUserId = tonumber(ownerText)
	if ownerUserId == nil or not isPositiveInteger(ownerUserId) then
		return nil
	end

	return ownerUserId
end

function RealmTransferState.NewSharedHubAssignment(now: number): AssignmentSnapshot
	return {
		locationCategory = RealmAssignmentProfileState.LocationCategory.SharedHub,
		realmId = nil,
		realmOwnerUserId = nil,
		assignmentReason = nil,
		updatedAt = now,
	}
end

function RealmTransferState.ResolveCurrentAssignment(profileData: any, fallbackNow: number): AssignmentSnapshot
	local persisted = RealmAssignmentProfileState.GetAssignment(profileData)
	if persisted ~= nil then
		return persisted
	end

	return RealmTransferState.NewSharedHubAssignment(fallbackNow)
end

function RealmTransferState.DeriveEffectiveLocationCategory(input: any): string
	if type(input) ~= "table" then
		return RealmAssignmentProfileState.LocationCategory.SharedHub
	end

	local profileData = input.profileData
	local persisted = if type(profileData) == "table"
		then RealmAssignmentProfileState.GetAssignment(profileData)
		else nil
	if persisted ~= nil then
		return persisted.locationCategory
	end

	if type(profileData) == "table" then
		local recovery = PendingRecoveryProfileState.GetRecovery(profileData)
		if recovery ~= nil and recovery.status == PendingRecoveryProfileState.Status.AwaitingDestination then
			return RealmAssignmentProfileState.LocationCategory.TransferInFlight
		end
	end

	local serverRealmOwnerUserId = input.serverRealmOwnerUserId
	if isPositiveInteger(serverRealmOwnerUserId) then
		local activeRealmId = RealmTransferState.FormatRealmId(serverRealmOwnerUserId :: number)
		if type(profileData) == "table" then
			local recovery = PendingRecoveryProfileState.GetRecovery(profileData)
			if recovery ~= nil and recovery.targetRealmId == activeRealmId then
				return RealmAssignmentProfileState.LocationCategory.GiantRealm
			end
		end
		if input.hasValidatedRealmAssignment == true then
			return RealmAssignmentProfileState.LocationCategory.GiantRealm
		end
	end

	return RealmAssignmentProfileState.LocationCategory.SharedHub
end

local function resolveTargetRealm(input: TransitionInput): (string?, number?, string?)
	local realmOwnerUserId = if isPositiveInteger(input.realmOwnerUserId) then input.realmOwnerUserId else nil
	local realmId = nonEmptyString(input.realmId)

	if realmOwnerUserId ~= nil and realmId == nil then
		realmId = RealmTransferState.FormatRealmId(realmOwnerUserId)
	end

	if realmId ~= nil and realmOwnerUserId == nil then
		realmOwnerUserId = RealmTransferState.ParseRealmOwnerUserId(realmId)
	end

	if realmOwnerUserId == nil or realmId == nil then
		return nil, nil, "realm_target_invalid"
	end

	if realmId ~= RealmTransferState.FormatRealmId(realmOwnerUserId) then
		return nil, nil, "realm_target_mismatch"
	end

	return realmId, realmOwnerUserId, "accepted"
end

local function reject(reason: string, assignment: AssignmentSnapshot?): TransitionResult
	return {
		accepted = false,
		reason = reason,
		assignment = if assignment ~= nil then cloneAssignment(assignment) else nil,
	}
end

local function accept(assignment: AssignmentSnapshot): TransitionResult
	return {
		accepted = true,
		reason = "accepted",
		assignment = cloneAssignment(assignment),
	}
end

local function buildInFlightAssignment(
	reason: string,
	realmId: string,
	realmOwnerUserId: number,
	now: number
): AssignmentSnapshot
	return {
		locationCategory = RealmAssignmentProfileState.LocationCategory.TransferInFlight,
		realmId = realmId,
		realmOwnerUserId = realmOwnerUserId,
		assignmentReason = reason,
		updatedAt = now,
	}
end

local function buildGiantRealmAssignment(realmId: string, realmOwnerUserId: number, now: number): AssignmentSnapshot
	return {
		locationCategory = RealmAssignmentProfileState.LocationCategory.GiantRealm,
		realmId = realmId,
		realmOwnerUserId = realmOwnerUserId,
		assignmentReason = nil,
		updatedAt = now,
	}
end

function RealmTransferState.ResolveTransition(
	currentAssignment: AssignmentSnapshot,
	input: TransitionInput
): TransitionResult
	local current = cloneAssignment(currentAssignment)

	if not validNow(input.now) then
		return reject("transition_now_invalid", current)
	end

	local operation = input.operation
	if type(operation) ~= "string" or operation == "" then
		return reject("transition_operation_invalid", current)
	end

	local now = input.now

	if operation == RealmTransferState.Operations.SetSharedHub then
		return accept(RealmTransferState.NewSharedHubAssignment(now))
	end

	if operation == RealmTransferState.Operations.AbortToHub then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.TransferInFlight then
			return reject("transfer_not_in_flight", current)
		end
		return accept(RealmTransferState.NewSharedHubAssignment(now))
	end

	if operation == RealmTransferState.Operations.ConfirmHubReturn then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.TransferInFlight then
			return reject("transfer_not_in_flight", current)
		end
		if current.assignmentReason ~= RealmAssignmentProfileState.AssignmentReason.EscapeReturn then
			return reject("confirm_hub_return_reason_invalid", current)
		end
		return accept(RealmTransferState.NewSharedHubAssignment(now))
	end

	if operation == RealmTransferState.Operations.ConfirmArrival then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.TransferInFlight then
			return reject("transfer_not_in_flight", current)
		end
		if current.assignmentReason == nil or INGRESS_REASONS[current.assignmentReason] ~= true then
			return reject("confirm_arrival_reason_invalid", current)
		end

		local realmId, realmOwnerUserId, targetReason = resolveTargetRealm(input)
		if realmId == nil or realmOwnerUserId == nil then
			return reject(targetReason or "realm_target_invalid", current)
		end
		if realmId ~= current.realmId or realmOwnerUserId ~= current.realmOwnerUserId then
			return reject("confirm_arrival_target_mismatch", current)
		end

		return accept(buildGiantRealmAssignment(realmId, realmOwnerUserId, now))
	end

	if current.locationCategory == RealmAssignmentProfileState.LocationCategory.TransferInFlight then
		return reject("transfer_already_in_flight", current)
	end

	local realmId, realmOwnerUserId, targetReason = resolveTargetRealm(input)
	if realmId == nil or realmOwnerUserId == nil then
		return reject(targetReason or "realm_target_invalid", current)
	end

	if operation == RealmTransferState.Operations.BeginCapture then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.SharedHub then
			return reject("begin_capture_requires_shared_hub", current)
		end
		return accept(
			buildInFlightAssignment(
				RealmAssignmentProfileState.AssignmentReason.Capture,
				realmId,
				realmOwnerUserId,
				now
			)
		)
	end

	if operation == RealmTransferState.Operations.BeginRescue then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.SharedHub then
			return reject("begin_rescue_requires_shared_hub", current)
		end
		return accept(
			buildInFlightAssignment(RealmAssignmentProfileState.AssignmentReason.Rescue, realmId, realmOwnerUserId, now)
		)
	end

	if operation == RealmTransferState.Operations.BeginPartyAdmission then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.SharedHub then
			return reject("begin_party_admission_requires_shared_hub", current)
		end
		return accept(
			buildInFlightAssignment(
				RealmAssignmentProfileState.AssignmentReason.PartyAdmission,
				realmId,
				realmOwnerUserId,
				now
			)
		)
	end

	if operation == RealmTransferState.Operations.BeginEscapeReturn then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.GiantRealm then
			return reject("begin_escape_return_requires_giant_realm", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("begin_escape_return_source_invalid", current)
		end
		if realmId ~= current.realmId or realmOwnerUserId ~= current.realmOwnerUserId then
			return reject("begin_escape_return_target_must_match_source", current)
		end
		return accept(
			buildInFlightAssignment(
				RealmAssignmentProfileState.AssignmentReason.EscapeReturn,
				realmId,
				realmOwnerUserId,
				now
			)
		)
	end

	if operation == RealmTransferState.Operations.BeginTrade then
		if current.locationCategory ~= RealmAssignmentProfileState.LocationCategory.GiantRealm then
			return reject("begin_trade_requires_giant_realm", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("begin_trade_source_invalid", current)
		end
		if realmId == current.realmId then
			return reject("begin_trade_target_must_differ", current)
		end
		return accept(
			buildInFlightAssignment(RealmAssignmentProfileState.AssignmentReason.Trade, realmId, realmOwnerUserId, now)
		)
	end

	return reject("transition_operation_unknown", current)
end

return RealmTransferState
