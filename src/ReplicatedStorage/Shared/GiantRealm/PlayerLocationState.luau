--!strict

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAssignmentProfileState"))
	else (require :: any)("./RealmAssignmentProfileState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferState"))
	else (require :: any)("./RealmTransferState")

local PlayerLocationState: any = {}

PlayerLocationState.SCHEMA_VERSION = 1

PlayerLocationState.Location = {
	SharedHub = "shared_hub",
	RealmGuest = "realm_guest",
	RealmInvader = "realm_invader",
	Captured = "captured",
	Contained = "contained",
	Escaping = "escaping",
	Transit = "transit",
	DisconnectedInRealm = "disconnected_in_realm",
	ReturnPending = "return_pending",
}

PlayerLocationState.TransitReason = {
	Capture = "capture",
	Rescue = "rescue",
	Trade = "trade",
	PartyAdmission = "party_admission",
	EscapeReturn = "escape_return",
	Raid = "raid",
	Return = "return",
}

PlayerLocationState.Operations = {
	SetSharedHub = "set_shared_hub",
	BeginTransit = "begin_transit",
	AbortTransit = "abort_transit",
	ConfirmRealmGuest = "confirm_realm_guest",
	ConfirmRealmInvader = "confirm_realm_invader",
	ConfirmCaptured = "confirm_captured",
	ConfirmHubReturn = "confirm_hub_return",
	Capture = "capture",
	Contain = "contain",
	BeginEscape = "begin_escape",
	EscapeFailed = "escape_failed",
	EscapeSucceeded = "escape_succeeded",
	SetReturnPending = "set_return_pending",
	ResolveHub = "resolve_hub",
	ResolveReturnPending = "resolve_return_pending",
	MarkDisconnected = "mark_disconnected",
}

PlayerLocationState.DisconnectActions = {
	NoOp = "no_op",
	SetReturnPending = "set_return_pending",
	ResolveHub = "resolve_hub",
}

local Location = PlayerLocationState.Location
local Operations = PlayerLocationState.Operations
local TransitReason = PlayerLocationState.TransitReason

local IN_REALM_LOCATIONS: { [string]: boolean } = {
	[Location.RealmGuest] = true,
	[Location.RealmInvader] = true,
	[Location.Captured] = true,
	[Location.Contained] = true,
	[Location.Escaping] = true,
}

local GUEST_INGRESS_REASONS: { [string]: boolean } = {
	[TransitReason.PartyAdmission] = true,
	[TransitReason.Rescue] = true,
	[TransitReason.Trade] = true,
}

local validLocationSet: { [string]: boolean } = {}
for _, locationName in pairs(Location) do
	validLocationSet[locationName] = true
end

local validTransitReasonSet: { [string]: boolean } = {}
for _, reasonName in pairs(TransitReason) do
	validTransitReasonSet[reasonName] = true
end

export type Snapshot = {
	location: string,
	realmId: string?,
	realmOwnerUserId: number?,
	transitReason: string?,
	resumeLocation: string?,
	updatedAt: number,
}

export type TransitionInput = {
	operation: string,
	now: number,
	realmOwnerUserId: number?,
	realmId: string?,
	transitReason: string?,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	snapshot: Snapshot?,
}

export type DisconnectInput = {
	now: number,
}

export type DisconnectResult = {
	accepted: boolean,
	reason: string,
	snapshot: Snapshot,
	action: string,
	persistReturnPending: boolean,
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
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
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

local function cloneSnapshot(snapshot: Snapshot): Snapshot
	return {
		location = snapshot.location,
		realmId = snapshot.realmId,
		realmOwnerUserId = snapshot.realmOwnerUserId,
		transitReason = snapshot.transitReason,
		resumeLocation = snapshot.resumeLocation,
		updatedAt = snapshot.updatedAt,
	}
end

local function reject(reason: string, snapshot: Snapshot?): TransitionResult
	return {
		accepted = false,
		reason = reason,
		snapshot = if snapshot ~= nil then cloneSnapshot(snapshot) else nil,
	}
end

local function accept(snapshot: Snapshot): TransitionResult
	return {
		accepted = true,
		reason = "accepted",
		snapshot = cloneSnapshot(snapshot),
	}
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

local function buildSnapshot(
	location: string,
	realmId: string?,
	realmOwnerUserId: number?,
	transitReason: string?,
	resumeLocation: string?,
	now: number
): Snapshot
	return {
		location = location,
		realmId = realmId,
		realmOwnerUserId = realmOwnerUserId,
		transitReason = transitReason,
		resumeLocation = resumeLocation,
		updatedAt = now,
	}
end

function PlayerLocationState.NewSharedHub(now: number): Snapshot
	return buildSnapshot(Location.SharedHub, nil, nil, nil, nil, now)
end

function PlayerLocationState.IsInRealm(location: string): boolean
	return IN_REALM_LOCATIONS[location] == true
end

function PlayerLocationState.RequiresSafeReturn(location: string): boolean
	return location == Location.ReturnPending
		or location == Location.DisconnectedInRealm
		or location == Location.Transit
		or IN_REALM_LOCATIONS[location] == true
end

function PlayerLocationState.NormalizeSnapshot(value: any): Snapshot?
	if type(value) ~= "table" then
		return nil
	end

	local location = nonEmptyString(value.location)
	if location == nil or validLocationSet[location] ~= true then
		return nil
	end

	local updatedAt = if isFiniteNumber(value.updatedAt) and value.updatedAt >= 0 then value.updatedAt else nil
	if updatedAt == nil then
		return nil
	end

	local realmId = nonEmptyString(value.realmId)
	local realmOwnerUserId = if isPositiveInteger(value.realmOwnerUserId) then value.realmOwnerUserId else nil
	local transitReason = nonEmptyString(value.transitReason)
	local resumeLocation = nonEmptyString(value.resumeLocation)

	if transitReason ~= nil and validTransitReasonSet[transitReason] ~= true then
		return nil
	end
	if resumeLocation ~= nil and validLocationSet[resumeLocation] ~= true then
		return nil
	end

	if location == Location.SharedHub then
		if realmId ~= nil or realmOwnerUserId ~= nil or transitReason ~= nil or resumeLocation ~= nil then
			return nil
		end
		return buildSnapshot(location, nil, nil, nil, nil, updatedAt)
	end

	if location == Location.ReturnPending or location == Location.DisconnectedInRealm then
		if realmId == nil or realmOwnerUserId == nil then
			return nil
		end
		if realmId ~= RealmTransferState.FormatRealmId(realmOwnerUserId) then
			return nil
		end
		return buildSnapshot(location, realmId, realmOwnerUserId, nil, nil, updatedAt)
	end

	if location == Location.Transit then
		if realmId == nil or realmOwnerUserId == nil or transitReason == nil then
			return nil
		end
		if realmId ~= RealmTransferState.FormatRealmId(realmOwnerUserId) then
			return nil
		end
		return buildSnapshot(location, realmId, realmOwnerUserId, transitReason, nil, updatedAt)
	end

	if location == Location.Escaping then
		if realmId == nil or realmOwnerUserId == nil or resumeLocation == nil then
			return nil
		end
		if resumeLocation ~= Location.Captured and resumeLocation ~= Location.Contained then
			return nil
		end
		if realmId ~= RealmTransferState.FormatRealmId(realmOwnerUserId) then
			return nil
		end
		return buildSnapshot(location, realmId, realmOwnerUserId, nil, resumeLocation, updatedAt)
	end

	if realmId == nil or realmOwnerUserId == nil then
		return nil
	end
	if realmId ~= RealmTransferState.FormatRealmId(realmOwnerUserId) then
		return nil
	end
	if transitReason ~= nil or resumeLocation ~= nil then
		return nil
	end

	return buildSnapshot(location, realmId, realmOwnerUserId, nil, nil, updatedAt)
end

local function assignmentReasonToTransitReason(assignmentReason: string?): string?
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.Capture then
		return TransitReason.Capture
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.Rescue then
		return TransitReason.Rescue
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.Trade then
		return TransitReason.Trade
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.PartyAdmission then
		return TransitReason.PartyAdmission
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.EscapeReturn then
		return TransitReason.EscapeReturn
	end
	return nil
end

function PlayerLocationState.DeriveFromRealmAssignment(assignment: any, now: number): Snapshot
	if type(assignment) ~= "table" then
		return PlayerLocationState.NewSharedHub(now)
	end

	local category = nonEmptyString(assignment.locationCategory)
	if category == RealmAssignmentProfileState.LocationCategory.SharedHub then
		return PlayerLocationState.NewSharedHub(now)
	end

	local realmId = nonEmptyString(assignment.realmId)
	local realmOwnerUserId = if isPositiveInteger(assignment.realmOwnerUserId) then assignment.realmOwnerUserId else nil
	if realmId == nil or realmOwnerUserId == nil then
		return PlayerLocationState.NewSharedHub(now)
	end

	if category == RealmAssignmentProfileState.LocationCategory.GiantRealm then
		return buildSnapshot(Location.RealmGuest, realmId, realmOwnerUserId, nil, nil, now)
	end

	if category == RealmAssignmentProfileState.LocationCategory.TransferInFlight then
		local transitReason = assignmentReasonToTransitReason(nonEmptyString(assignment.assignmentReason))
		if transitReason == nil then
			return PlayerLocationState.NewSharedHub(now)
		end
		return buildSnapshot(Location.Transit, realmId, realmOwnerUserId, transitReason, nil, now)
	end

	return PlayerLocationState.NewSharedHub(now)
end

function PlayerLocationState.ResolveTransition(currentSnapshot: Snapshot, input: TransitionInput): TransitionResult
	local current = cloneSnapshot(currentSnapshot)

	if not validNow(input.now) then
		return reject("transition_now_invalid", current)
	end

	local operation = input.operation
	if type(operation) ~= "string" or operation == "" then
		return reject("transition_operation_invalid", current)
	end

	local now = input.now
	local realmId, realmOwnerUserId, targetReason = resolveTargetRealm(input)

	if operation == Operations.SetSharedHub then
		if current.location == Location.SharedHub then
			return accept(PlayerLocationState.NewSharedHub(now))
		end
		if
			current.location == Location.ReturnPending
			or current.location == Location.DisconnectedInRealm
			or current.location == Location.Transit
		then
			return accept(PlayerLocationState.NewSharedHub(now))
		end
		return reject("transition_not_allowed", current)
	end

	if operation == Operations.BeginTransit then
		if
			current.location ~= Location.SharedHub
			and current.location ~= Location.RealmGuest
			and current.location ~= Location.RealmInvader
			and current.location ~= Location.ReturnPending
		then
			return reject("transition_not_allowed", current)
		end
		if realmId == nil or realmOwnerUserId == nil then
			return reject(targetReason or "realm_target_invalid", current)
		end
		local transitReason = nonEmptyString(input.transitReason)
		if transitReason == nil or validTransitReasonSet[transitReason] ~= true then
			return reject("transit_reason_invalid", current)
		end
		return accept(buildSnapshot(Location.Transit, realmId, realmOwnerUserId, transitReason, nil, now))
	end

	if operation == Operations.AbortTransit then
		if current.location ~= Location.Transit then
			return reject("transition_not_allowed", current)
		end
		return accept(PlayerLocationState.NewSharedHub(now))
	end

	if operation == Operations.ConfirmRealmGuest then
		if current.location ~= Location.Transit then
			return reject("transition_not_allowed", current)
		end
		if current.transitReason == nil or GUEST_INGRESS_REASONS[current.transitReason] ~= true then
			return reject("confirm_realm_guest_reason_invalid", current)
		end
		if realmId == nil or realmOwnerUserId == nil then
			return reject(targetReason or "realm_target_invalid", current)
		end
		if realmId ~= current.realmId or realmOwnerUserId ~= current.realmOwnerUserId then
			return reject("confirm_realm_guest_target_mismatch", current)
		end
		return accept(buildSnapshot(Location.RealmGuest, realmId, realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.ConfirmRealmInvader then
		if current.location ~= Location.Transit then
			return reject("transition_not_allowed", current)
		end
		if current.transitReason ~= TransitReason.Raid then
			return reject("confirm_realm_invader_reason_invalid", current)
		end
		if realmId == nil or realmOwnerUserId == nil then
			return reject(targetReason or "realm_target_invalid", current)
		end
		if realmId ~= current.realmId or realmOwnerUserId ~= current.realmOwnerUserId then
			return reject("confirm_realm_invader_target_mismatch", current)
		end
		return accept(buildSnapshot(Location.RealmInvader, realmId, realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.ConfirmCaptured then
		if current.location ~= Location.Transit then
			return reject("transition_not_allowed", current)
		end
		if current.transitReason ~= TransitReason.Capture then
			return reject("confirm_captured_reason_invalid", current)
		end
		if realmId == nil or realmOwnerUserId == nil then
			return reject(targetReason or "realm_target_invalid", current)
		end
		if realmId ~= current.realmId or realmOwnerUserId ~= current.realmOwnerUserId then
			return reject("confirm_captured_target_mismatch", current)
		end
		return accept(buildSnapshot(Location.Captured, realmId, realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.ConfirmHubReturn then
		if current.location ~= Location.Transit then
			return reject("transition_not_allowed", current)
		end
		if current.transitReason ~= TransitReason.EscapeReturn then
			return reject("confirm_hub_return_reason_invalid", current)
		end
		return accept(PlayerLocationState.NewSharedHub(now))
	end

	if operation == Operations.Capture then
		if current.location ~= Location.RealmGuest and current.location ~= Location.RealmInvader then
			return reject("transition_not_allowed", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("capture_source_invalid", current)
		end
		return accept(buildSnapshot(Location.Captured, current.realmId, current.realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.Contain then
		if current.location ~= Location.Captured then
			return reject("transition_not_allowed", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("contain_source_invalid", current)
		end
		return accept(buildSnapshot(Location.Contained, current.realmId, current.realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.BeginEscape then
		if current.location ~= Location.Captured and current.location ~= Location.Contained then
			return reject("transition_not_allowed", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("escape_source_invalid", current)
		end
		return accept(
			buildSnapshot(Location.Escaping, current.realmId, current.realmOwnerUserId, nil, current.location, now)
		)
	end

	if operation == Operations.EscapeFailed then
		if current.location ~= Location.Escaping then
			return reject("transition_not_allowed", current)
		end
		local resumeLocation = current.resumeLocation
		if resumeLocation ~= Location.Captured and resumeLocation ~= Location.Contained then
			return reject("escape_resume_invalid", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("escape_source_invalid", current)
		end
		local resume = resumeLocation :: string
		return accept(buildSnapshot(resume, current.realmId, current.realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.EscapeSucceeded then
		if current.location ~= Location.Escaping then
			return reject("transition_not_allowed", current)
		end
		return accept(PlayerLocationState.NewSharedHub(now))
	end

	if operation == Operations.SetReturnPending then
		if
			current.location ~= Location.Captured
			and current.location ~= Location.Contained
			and current.location ~= Location.RealmGuest
			and current.location ~= Location.RealmInvader
			and current.location ~= Location.Escaping
		then
			return reject("transition_not_allowed", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("return_pending_source_invalid", current)
		end
		return accept(buildSnapshot(Location.ReturnPending, current.realmId, current.realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.ResolveHub then
		if current.location ~= Location.ReturnPending and current.location ~= Location.DisconnectedInRealm then
			return reject("transition_not_allowed", current)
		end
		return accept(PlayerLocationState.NewSharedHub(now))
	end

	if operation == Operations.ResolveReturnPending then
		if current.location ~= Location.DisconnectedInRealm then
			return reject("transition_not_allowed", current)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("return_pending_source_invalid", current)
		end
		return accept(buildSnapshot(Location.ReturnPending, current.realmId, current.realmOwnerUserId, nil, nil, now))
	end

	if operation == Operations.MarkDisconnected then
		if
			current.location ~= Location.RealmGuest
			and current.location ~= Location.RealmInvader
			and current.location ~= Location.Captured
			and current.location ~= Location.Contained
			and current.location ~= Location.Escaping
			and current.location ~= Location.Transit
		then
			return reject("transition_not_allowed", current)
		end
		if current.location == Location.Transit then
			if current.realmId == nil or current.realmOwnerUserId == nil then
				return reject("disconnect_transit_invalid", current)
			end
			return accept(
				buildSnapshot(Location.DisconnectedInRealm, current.realmId, current.realmOwnerUserId, nil, nil, now)
			)
		end
		if current.realmId == nil or current.realmOwnerUserId == nil then
			return reject("disconnect_source_invalid", current)
		end
		return accept(
			buildSnapshot(Location.DisconnectedInRealm, current.realmId, current.realmOwnerUserId, nil, nil, now)
		)
	end

	return reject("transition_operation_unknown", current)
end

function PlayerLocationState.ResolveDisconnect(currentSnapshot: Snapshot, input: DisconnectInput): DisconnectResult
	local current = cloneSnapshot(currentSnapshot)

	if not validNow(input.now) then
		return {
			accepted = false,
			reason = "disconnect_now_invalid",
			snapshot = current,
			action = PlayerLocationState.DisconnectActions.NoOp,
			persistReturnPending = false,
		}
	end

	if current.location == Location.SharedHub then
		return {
			accepted = true,
			reason = "accepted",
			snapshot = current,
			action = PlayerLocationState.DisconnectActions.NoOp,
			persistReturnPending = false,
		}
	end

	if current.location == Location.ReturnPending then
		return {
			accepted = true,
			reason = "accepted",
			snapshot = current,
			action = PlayerLocationState.DisconnectActions.SetReturnPending,
			persistReturnPending = true,
		}
	end

	if current.location == Location.DisconnectedInRealm then
		local pending = PlayerLocationState.ResolveTransition(current, {
			operation = Operations.ResolveReturnPending,
			now = input.now,
		})
		if pending.accepted ~= true or pending.snapshot == nil then
			return {
				accepted = false,
				reason = pending.reason,
				snapshot = current,
				action = PlayerLocationState.DisconnectActions.NoOp,
				persistReturnPending = false,
			}
		end
		return {
			accepted = true,
			reason = "accepted",
			snapshot = pending.snapshot,
			action = PlayerLocationState.DisconnectActions.SetReturnPending,
			persistReturnPending = true,
		}
	end

	if current.location == Location.Transit and current.transitReason == TransitReason.EscapeReturn then
		local hub = PlayerLocationState.NewSharedHub(input.now)
		return {
			accepted = true,
			reason = "accepted",
			snapshot = hub,
			action = PlayerLocationState.DisconnectActions.ResolveHub,
			persistReturnPending = false,
		}
	end

	if
		current.location == Location.RealmGuest
		or current.location == Location.RealmInvader
		or current.location == Location.Captured
		or current.location == Location.Contained
		or current.location == Location.Escaping
		or current.location == Location.Transit
	then
		local marked = PlayerLocationState.ResolveTransition(current, {
			operation = Operations.MarkDisconnected,
			now = input.now,
		})
		if marked.accepted ~= true or marked.snapshot == nil then
			return {
				accepted = false,
				reason = marked.reason,
				snapshot = current,
				action = PlayerLocationState.DisconnectActions.NoOp,
				persistReturnPending = false,
			}
		end

		local pending = PlayerLocationState.ResolveTransition(marked.snapshot, {
			operation = Operations.ResolveReturnPending,
			now = input.now,
		})
		if pending.accepted ~= true or pending.snapshot == nil then
			return {
				accepted = false,
				reason = pending.reason,
				snapshot = current,
				action = PlayerLocationState.DisconnectActions.NoOp,
				persistReturnPending = false,
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			snapshot = pending.snapshot,
			action = PlayerLocationState.DisconnectActions.SetReturnPending,
			persistReturnPending = true,
		}
	end

	return {
		accepted = false,
		reason = "disconnect_location_unhandled",
		snapshot = current,
		action = PlayerLocationState.DisconnectActions.NoOp,
		persistReturnPending = false,
	}
end

return PlayerLocationState
