--!strict

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAssignmentProfileState"))
	else (require :: any)("./RealmAssignmentProfileState")

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PlayerLocationState"))
	else (require :: any)("./PlayerLocationState")

local RealmAdmissionLocationState: any = {}

local LocationOps = PlayerLocationState.Operations
local TransitReason = PlayerLocationState.TransitReason
local AssignmentReason = RealmAssignmentProfileState.AssignmentReason

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

function RealmAdmissionLocationState.ResolveTransitReason(input: any): string?
	if type(input) ~= "table" then
		return TransitReason.PartyAdmission
	end

	local assignmentReason = input.assignmentReason
	if assignmentReason == AssignmentReason.Capture then
		return TransitReason.Capture
	end
	if assignmentReason == AssignmentReason.Rescue then
		return TransitReason.Rescue
	end
	if assignmentReason == AssignmentReason.Trade then
		return TransitReason.Trade
	end
	if assignmentReason == AssignmentReason.EscapeReturn then
		return TransitReason.EscapeReturn
	end

	local entryType = input.entryType
	if entryType == "rescue_contract" then
		return TransitReason.Rescue
	end

	return TransitReason.PartyAdmission
end

function RealmAdmissionLocationState.ResolveConfirmOperation(input: any): string?
	if type(input) ~= "table" then
		return LocationOps.ConfirmRealmGuest
	end

	local assignmentReason = input.assignmentReason
	if assignmentReason == AssignmentReason.EscapeReturn then
		return LocationOps.ConfirmHubReturn
	end
	if assignmentReason == AssignmentReason.Capture then
		return LocationOps.ConfirmCaptured
	end

	local transitReason = input.transitReason
	if transitReason == TransitReason.Raid then
		return LocationOps.ConfirmRealmInvader
	end

	return LocationOps.ConfirmRealmGuest
end

function RealmAdmissionLocationState.IsMatchingTransit(
	snapshot: any,
	targetRealmId: string,
	transitReason: string
): boolean
	if type(snapshot) ~= "table" then
		return false
	end
	if snapshot.location ~= PlayerLocationState.Location.Transit then
		return false
	end
	if not isNonEmptyString(snapshot.realmId) or snapshot.realmId ~= targetRealmId then
		return false
	end
	if snapshot.transitReason ~= transitReason then
		return false
	end
	return true
end

return RealmAdmissionLocationState
