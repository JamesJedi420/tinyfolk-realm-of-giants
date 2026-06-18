--!strict

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAssignmentProfileState"))
	else (require :: any)("./RealmAssignmentProfileState")

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PlayerLocationState"))
	else (require :: any)("./PlayerLocationState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferState"))
	else (require :: any)("./RealmTransferState")

local PlayerLocationAssignmentSync: any = {}

local Location = PlayerLocationState.Location
local LocationOps = PlayerLocationState.Operations
local TransitReason = PlayerLocationState.TransitReason
local AssignmentReason = RealmAssignmentProfileState.AssignmentReason
local LocationCategory = RealmAssignmentProfileState.LocationCategory
local TransferOps = RealmTransferState.Operations

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

function PlayerLocationAssignmentSync.ResolveBeginAssignmentOperation(transitReason: string?): string?
	local reason = nonEmptyString(transitReason)
	if reason == TransitReason.Capture then
		return TransferOps.BeginCapture
	end
	if reason == TransitReason.Rescue then
		return TransferOps.BeginRescue
	end
	if reason == TransitReason.Trade then
		return TransferOps.BeginTrade
	end
	if reason == TransitReason.PartyAdmission or reason == TransitReason.Raid then
		return TransferOps.BeginPartyAdmission
	end
	if reason == TransitReason.EscapeReturn then
		return TransferOps.BeginEscapeReturn
	end
	return nil
end

function PlayerLocationAssignmentSync.ResolveConfirmAssignmentOperation(
	locationOperation: string,
	assignmentReason: string?
): string?
	if locationOperation == LocationOps.ConfirmHubReturn then
		return TransferOps.ConfirmHubReturn
	end
	if
		locationOperation == LocationOps.ConfirmRealmGuest
		or locationOperation == LocationOps.ConfirmRealmInvader
		or locationOperation == LocationOps.ConfirmCaptured
	then
		return TransferOps.ConfirmArrival
	end
	if nonEmptyString(assignmentReason) == AssignmentReason.EscapeReturn then
		return TransferOps.ConfirmHubReturn
	end
	return nil
end

function PlayerLocationAssignmentSync.ResolveAssignmentOperationForLocationOperation(
	locationOperation: string,
	context: any?
): string?
	if locationOperation == LocationOps.BeginTransit then
		if type(context) ~= "table" then
			return nil
		end
		return PlayerLocationAssignmentSync.ResolveBeginAssignmentOperation(context.transitReason)
	end

	if locationOperation == LocationOps.AbortTransit then
		return TransferOps.AbortToHub
	end

	if
		locationOperation == LocationOps.EscapeSucceeded
		or locationOperation == LocationOps.ResolveHub
		or locationOperation == LocationOps.SetSharedHub
	then
		return TransferOps.SetSharedHub
	end

	if locationOperation == LocationOps.ConfirmHubReturn then
		return TransferOps.ConfirmHubReturn
	end

	if
		locationOperation == LocationOps.ConfirmRealmGuest
		or locationOperation == LocationOps.ConfirmRealmInvader
		or locationOperation == LocationOps.ConfirmCaptured
	then
		local assignmentReason = if type(context) == "table" then context.assignmentReason else nil
		return PlayerLocationAssignmentSync.ResolveConfirmAssignmentOperation(locationOperation, assignmentReason)
	end

	if locationOperation == LocationOps.SetSharedHub then
		return TransferOps.SetSharedHub
	end

	return nil
end

function PlayerLocationAssignmentSync.ResolveLocationOperationForAssignmentOperation(
	assignmentOperation: string,
	context: any?
): any?
	if assignmentOperation == TransferOps.SetSharedHub then
		return {
			operation = LocationOps.SetSharedHub,
		}
	end

	if assignmentOperation == TransferOps.AbortToHub then
		return {
			operation = LocationOps.AbortTransit,
			sequence = { LocationOps.AbortTransit, LocationOps.ResolveHub },
		}
	end

	if assignmentOperation == TransferOps.ConfirmHubReturn then
		return {
			operation = LocationOps.ConfirmHubReturn,
		}
	end

	if assignmentOperation == TransferOps.ConfirmArrival then
		local assignmentReason = if type(context) == "table" then context.assignmentReason else nil
		if assignmentReason == AssignmentReason.Capture then
			return {
				operation = LocationOps.ConfirmCaptured,
			}
		end
		local transitReason = if type(context) == "table" then context.transitReason else nil
		if transitReason == TransitReason.Raid then
			return {
				operation = LocationOps.ConfirmRealmInvader,
			}
		end
		return {
			operation = LocationOps.ConfirmRealmGuest,
		}
	end

	local beginReasonMap: { [string]: string } = {
		[TransferOps.BeginCapture] = TransitReason.Capture,
		[TransferOps.BeginRescue] = TransitReason.Rescue,
		[TransferOps.BeginTrade] = TransitReason.Trade,
		[TransferOps.BeginPartyAdmission] = TransitReason.PartyAdmission,
		[TransferOps.BeginEscapeReturn] = TransitReason.EscapeReturn,
	}
	local transitReason = beginReasonMap[assignmentOperation]
	if transitReason ~= nil then
		return {
			operation = LocationOps.BeginTransit,
			transitReason = transitReason,
		}
	end

	return nil
end

function PlayerLocationAssignmentSync.IsMatchingTransitPair(
	locationSnapshot: any,
	assignmentSnapshot: any,
	targetRealmId: string?,
	transitReason: string?
): boolean
	if type(locationSnapshot) ~= "table" or type(assignmentSnapshot) ~= "table" then
		return false
	end
	if locationSnapshot.location ~= Location.Transit then
		return false
	end
	if assignmentSnapshot.locationCategory ~= LocationCategory.TransferInFlight then
		return false
	end
	if nonEmptyString(targetRealmId) ~= nil and locationSnapshot.realmId ~= targetRealmId then
		return false
	end
	if nonEmptyString(targetRealmId) ~= nil and assignmentSnapshot.realmId ~= targetRealmId then
		return false
	end
	if nonEmptyString(transitReason) ~= nil and locationSnapshot.transitReason ~= transitReason then
		return false
	end
	return true
end

function PlayerLocationAssignmentSync.IsAssignmentSyncReasonIgnorable(reason: string): boolean
	return reason == "transfer_already_in_flight"
end

function PlayerLocationAssignmentSync.IsLocationSyncReasonIgnorable(reason: string): boolean
	return reason == "already_in_transit" or reason == "not_in_transit"
end

function PlayerLocationAssignmentSync.BuildRealmTargetInput(
	realmOwnerUserId: any,
	realmId: any,
	now: number,
	transitReason: string?
): any?
	if not isPositiveInteger(realmOwnerUserId) then
		local parsedOwner = RealmTransferState.ParseRealmOwnerUserId(realmId)
		if parsedOwner == nil then
			return nil
		end
		realmOwnerUserId = parsedOwner
	end
	local resolvedRealmId = nonEmptyString(realmId)
	if resolvedRealmId == nil then
		resolvedRealmId = RealmTransferState.FormatRealmId(realmOwnerUserId)
	end
	local payload: any = {
		now = now,
		realmOwnerUserId = realmOwnerUserId,
		realmId = resolvedRealmId,
	}
	if nonEmptyString(transitReason) ~= nil then
		payload.transitReason = transitReason
	end
	return payload
end

return PlayerLocationAssignmentSync
