--!strict

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PlayerLocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")

local PlayerLocationAssignmentSync = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PlayerLocationAssignmentSync")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationAssignmentSync")

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmAssignmentProfileState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTransferState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local PlayerLocationAssignmentSyncCaller: any = {}
local globalEnv: any = getfenv()

local Location = PlayerLocationState.Location
local LocationOps = PlayerLocationState.Operations
local TransferOps = RealmTransferState.Operations

local locationApiOverride: any = nil
local assignmentApiOverride: any = nil

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function getLocationApi(): any?
	if locationApiOverride ~= nil then
		return locationApiOverride
	end
	return getGlobalTable("_PlayerLocationService_QueryAPI")
end

local function getAssignmentApi(): any?
	if assignmentApiOverride ~= nil then
		return assignmentApiOverride
	end
	return getGlobalTable("_RealmTransferAssignmentService_QueryAPI")
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

local function getLocationSnapshot(userId: number): any?
	local locationApi = getLocationApi()
	if type(locationApi) ~= "table" or type(locationApi.GetLocationSnapshot) ~= "function" then
		return nil
	end
	local result = locationApi.GetLocationSnapshot(userId)
	if type(result) ~= "table" or result.accepted ~= true or type(result.snapshot) ~= "table" then
		return nil
	end
	return PlayerLocationState.NormalizeSnapshot(result.snapshot)
end

local function getAssignmentSnapshot(userId: number): any?
	local assignmentApi = getAssignmentApi()
	if type(assignmentApi) ~= "table" or type(assignmentApi.GetAssignmentSnapshot) ~= "function" then
		return nil
	end
	local result = assignmentApi.GetAssignmentSnapshot(userId)
	if type(result) ~= "table" or result.accepted ~= true or type(result.assignment) ~= "table" then
		return nil
	end
	return result.assignment
end

local function applyLocationTransition(userId: number, payload: any): any
	local locationApi = getLocationApi()
	if type(locationApi) ~= "table" or type(locationApi.ApplyTransition) ~= "function" then
		return {
			accepted = true,
			reason = "location_api_unavailable",
		}
	end
	local ok, result = pcall(function()
		return locationApi.ApplyTransition(userId, payload)
	end)
	if not ok or type(result) ~= "table" then
		return {
			accepted = false,
			reason = "location_transition_failed",
		}
	end
	return result
end

local function applyAssignmentTransition(userId: number, payload: any): any
	local assignmentApi = getAssignmentApi()
	if type(assignmentApi) ~= "table" or type(assignmentApi.ApplyTransition) ~= "function" then
		return {
			accepted = true,
			reason = "assignment_api_unavailable",
		}
	end
	local ok, result = pcall(function()
		return assignmentApi.ApplyTransition(userId, payload)
	end)
	if not ok or type(result) ~= "table" then
		return {
			accepted = false,
			reason = "assignment_transition_failed",
		}
	end
	return result
end

local function buildSyncContext(input: any, fallbackSnapshot: any?): any
	return {
		now = if type(input) == "table" then input.now else nil,
		realmOwnerUserId = if type(input) == "table" then input.realmOwnerUserId else nil,
		realmId = if type(input) == "table" then input.realmId else nil,
		transitReason = if type(input) == "table"
			then input.transitReason
			elseif type(fallbackSnapshot) == "table" then fallbackSnapshot.transitReason
			else nil,
		assignmentReason = if type(input) == "table" then input.assignmentReason else nil,
	}
end

local function syncAssignmentAfterLocation(
	userId: number,
	locationOperation: string,
	locationResult: any,
	syncContext: any?
): any
	local assignmentOperation =
		PlayerLocationAssignmentSync.ResolveAssignmentOperationForLocationOperation(locationOperation, syncContext)
	if assignmentOperation == nil then
		return {
			accepted = true,
			reason = "assignment_sync_not_required",
		}
	end

	local resolvedAt = if type(syncContext) == "table" and type(syncContext.now) == "number"
		then syncContext.now
		else os.time()
	local realmOwnerUserId = if type(syncContext) == "table" then syncContext.realmOwnerUserId else nil
	local realmId = if type(syncContext) == "table" then syncContext.realmId else nil
	if type(locationResult) == "table" and type(locationResult.snapshot) == "table" then
		if realmOwnerUserId == nil then
			realmOwnerUserId = locationResult.snapshot.realmOwnerUserId
		end
		if realmId == nil then
			realmId = locationResult.snapshot.realmId
		end
	end

	local targetInput = PlayerLocationAssignmentSync.BuildRealmTargetInput(realmOwnerUserId, realmId, resolvedAt, nil)
	if targetInput == nil and assignmentOperation ~= TransferOps.SetSharedHub then
		return {
			accepted = true,
			reason = "assignment_target_skipped",
		}
	end

	local assignmentPayload: any = {
		operation = assignmentOperation,
		now = resolvedAt,
	}
	if targetInput ~= nil then
		assignmentPayload.realmOwnerUserId = targetInput.realmOwnerUserId
		assignmentPayload.realmId = targetInput.realmId
	end

	local assignmentResult = applyAssignmentTransition(userId, assignmentPayload)
	if assignmentResult.accepted == true then
		return assignmentResult
	end
	if
		type(assignmentResult.reason) == "string"
		and PlayerLocationAssignmentSync.IsAssignmentSyncReasonIgnorable(assignmentResult.reason)
	then
		local assignmentSnapshot = getAssignmentSnapshot(userId)
		local locationSnapshot = if type(locationResult) == "table" then locationResult.snapshot else nil
		local transitReason = if type(syncContext) == "table" then syncContext.transitReason else nil
		if
			PlayerLocationAssignmentSync.IsMatchingTransitPair(
				locationSnapshot,
				assignmentSnapshot,
				if type(targetInput) == "table" then targetInput.realmId else nil,
				transitReason
			)
		then
			return {
				accepted = true,
				reason = "assignment_already_synced",
			}
		end
	end
	return assignmentResult
end

local function syncLocationAfterAssignment(
	userId: number,
	assignmentOperation: string,
	assignmentResult: any,
	syncContext: any?
): any
	local locationMapping =
		PlayerLocationAssignmentSync.ResolveLocationOperationForAssignmentOperation(assignmentOperation, syncContext)
	if locationMapping == nil then
		return {
			accepted = true,
			reason = "location_sync_not_required",
		}
	end

	local resolvedAt = if type(syncContext) == "table" and type(syncContext.now) == "number"
		then syncContext.now
		else os.time()
	local realmOwnerUserId = if type(syncContext) == "table" then syncContext.realmOwnerUserId else nil
	local realmId = if type(syncContext) == "table" then syncContext.realmId else nil
	if type(assignmentResult) == "table" and type(assignmentResult.assignment) == "table" then
		if realmOwnerUserId == nil then
			realmOwnerUserId = assignmentResult.assignment.realmOwnerUserId
		end
		if realmId == nil then
			realmId = assignmentResult.assignment.realmId
		end
	end

	local targetInput = PlayerLocationAssignmentSync.BuildRealmTargetInput(
		realmOwnerUserId,
		realmId,
		resolvedAt,
		locationMapping.transitReason
	)
	if targetInput == nil and locationMapping.operation ~= LocationOps.SetSharedHub then
		return {
			accepted = true,
			reason = "location_target_skipped",
		}
	end

	local operations: { string } = if type(locationMapping.sequence) == "table"
		then locationMapping.sequence
		else { locationMapping.operation }

	local lastResult: any = {
		accepted = true,
		reason = "accepted",
	}
	for _, operation in ipairs(operations) do
		local payload: any = {
			operation = operation,
			now = resolvedAt,
		}
		if targetInput ~= nil then
			payload.realmOwnerUserId = targetInput.realmOwnerUserId
			payload.realmId = targetInput.realmId
			if operation == LocationOps.BeginTransit then
				payload.transitReason = targetInput.transitReason
			end
		end
		lastResult = applyLocationTransition(userId, payload)
		if lastResult.accepted ~= true then
			if
				type(lastResult.reason) == "string"
				and PlayerLocationAssignmentSync.IsLocationSyncReasonIgnorable(lastResult.reason)
			then
				continue
			end
			return lastResult
		end
	end

	return lastResult
end

function PlayerLocationAssignmentSyncCaller.ResetForTests()
	locationApiOverride = nil
	assignmentApiOverride = nil
end

function PlayerLocationAssignmentSyncCaller.SetTestOverrides(overrides: any)
	if type(overrides) ~= "table" then
		return
	end
	if overrides.locationApi ~= nil then
		locationApiOverride = overrides.locationApi
	end
	if overrides.assignmentApi ~= nil then
		assignmentApiOverride = overrides.assignmentApi
	end
end

function PlayerLocationAssignmentSyncCaller.ApplyLocationWithAssignmentSync(userId: any, input: any): any
	if not isPositiveInteger(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end
	if type(input) ~= "table" or type(input.operation) ~= "string" then
		return {
			accepted = false,
			reason = "transition_input_invalid",
		}
	end

	local locationResult = applyLocationTransition(userId, input)
	if locationResult.accepted ~= true then
		return locationResult
	end

	local syncContext = buildSyncContext(input, locationResult.snapshot)
	local assignmentSyncResult = syncAssignmentAfterLocation(userId, input.operation, locationResult, syncContext)
	if assignmentSyncResult.accepted ~= true then
		return {
			accepted = false,
			reason = assignmentSyncResult.reason or "assignment_sync_failed",
			snapshot = locationResult.snapshot,
		}
	end

	return locationResult
end

function PlayerLocationAssignmentSyncCaller.ApplyAssignmentWithLocationSync(userId: any, input: any): any
	if not isPositiveInteger(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end
	if type(input) ~= "table" or type(input.operation) ~= "string" then
		return {
			accepted = false,
			reason = "transition_input_invalid",
		}
	end

	local assignmentResult = applyAssignmentTransition(userId, input)
	if assignmentResult.accepted ~= true then
		return assignmentResult
	end

	local syncContext = buildSyncContext(input, nil)
	local locationSyncResult = syncLocationAfterAssignment(userId, input.operation, assignmentResult, syncContext)
	if locationSyncResult.accepted ~= true then
		return {
			accepted = false,
			reason = locationSyncResult.reason or "location_sync_failed",
			assignment = assignmentResult.assignment,
		}
	end

	return assignmentResult
end

function PlayerLocationAssignmentSyncCaller.ApplyCoupledConfirmForArrival(userId: any, input: any): any
	if not isPositiveInteger(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end
	if type(input) ~= "table" or type(input.targetRealmId) ~= "string" or input.targetRealmId == "" then
		return {
			accepted = false,
			reason = "target_realm_id_invalid",
		}
	end

	local resolvedAt = if type(input.now) == "number" then input.now else os.time()
	local realmOwnerUserId = if isPositiveInteger(input.realmOwnerUserId) then input.realmOwnerUserId else nil
	local realmId = input.targetRealmId
	local locationSnapshot = getLocationSnapshot(userId)
	local confirmOperation = if type(input.confirmOperation) == "string"
		then input.confirmOperation
		else LocationOps.ConfirmRealmGuest

	return PlayerLocationAssignmentSyncCaller.ApplyLocationWithAssignmentSync(userId, {
		operation = confirmOperation,
		now = resolvedAt,
		realmOwnerUserId = realmOwnerUserId,
		realmId = realmId,
		assignmentReason = input.assignmentReason,
		transitReason = if locationSnapshot ~= nil then locationSnapshot.transitReason else nil,
	})
end

function PlayerLocationAssignmentSyncCaller.ApplyCoupledAbortRollback(userId: any, input: any?): any
	if not isPositiveInteger(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end

	local resolvedAt = if type(input) == "table" and type(input.now) == "number" then input.now else os.time()
	local locationSnapshot = getLocationSnapshot(userId)
	if locationSnapshot == nil or locationSnapshot.location ~= Location.Transit then
		local assignmentSnapshot = getAssignmentSnapshot(userId)
		if
			assignmentSnapshot ~= nil
			and assignmentSnapshot.locationCategory == RealmAssignmentProfileState.LocationCategory.TransferInFlight
		then
			local assignmentAbort = applyAssignmentTransition(userId, {
				operation = TransferOps.AbortToHub,
				now = resolvedAt,
			})
			if assignmentAbort.accepted ~= true then
				return assignmentAbort
			end
		end
		return {
			accepted = true,
			reason = "not_in_transit",
		}
	end

	return PlayerLocationAssignmentSyncCaller.ApplyLocationWithAssignmentSync(userId, {
		operation = LocationOps.AbortTransit,
		now = resolvedAt,
	})
end

return PlayerLocationAssignmentSyncCaller
