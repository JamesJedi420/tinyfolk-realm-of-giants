--!strict

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PlayerLocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")

local RealmTransferAssignmentService = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferAssignmentService"))
	else (require :: any)("./RealmTransferAssignmentService")

local PlayerLocationService: any = {}
local globalEnv: any = getfenv()

export type LocationDiagnostics = {
	totalTransitions: number,
	acceptedTransitions: number,
	rejectedTransitions: number,
	totalDisconnectResolutions: number,
	lastOperation: string,
	lastReason: string,
	lastUserId: number?,
}

local snapshotByUserId: { [number]: PlayerLocationState.Snapshot? } = {}
local diagnostics: LocationDiagnostics = {
	totalTransitions = 0,
	acceptedTransitions = 0,
	rejectedTransitions = 0,
	totalDisconnectResolutions = 0,
	lastOperation = "none",
	lastReason = "not_started",
	lastUserId = nil,
}

local function debugLog(message: string)
	print(string.format("[PlayerLocationService] %s", message))
end

local function cloneDiagnostics(): LocationDiagnostics
	return {
		totalTransitions = diagnostics.totalTransitions,
		acceptedTransitions = diagnostics.acceptedTransitions,
		rejectedTransitions = diagnostics.rejectedTransitions,
		totalDisconnectResolutions = diagnostics.totalDisconnectResolutions,
		lastOperation = diagnostics.lastOperation,
		lastReason = diagnostics.lastReason,
		lastUserId = diagnostics.lastUserId,
	}
end

local function isValidUserId(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function recordTransitionDiagnostics(userId: number, operation: string, accepted: boolean, reason: string)
	diagnostics.totalTransitions += 1
	if accepted then
		diagnostics.acceptedTransitions += 1
	else
		diagnostics.rejectedTransitions += 1
	end
	diagnostics.lastOperation = operation
	diagnostics.lastReason = reason
	diagnostics.lastUserId = userId
end

local function defaultSnapshot(now: number?): PlayerLocationState.Snapshot
	local at = if type(now) == "number" and now == now and now >= 0 then now else os.time()
	return PlayerLocationState.NewSharedHub(at)
end

local function hydrateFromRealmAssignment(userId: number): PlayerLocationState.Snapshot?
	local assignmentResult = RealmTransferAssignmentService.GetAssignmentSnapshot(userId)
	if assignmentResult.accepted ~= true or type(assignmentResult.assignment) ~= "table" then
		return nil
	end

	return PlayerLocationState.DeriveFromRealmAssignment(assignmentResult.assignment, os.time())
end

function PlayerLocationService.ResetForTests()
	snapshotByUserId = {}
	diagnostics = {
		totalTransitions = 0,
		acceptedTransitions = 0,
		rejectedTransitions = 0,
		totalDisconnectResolutions = 0,
		lastOperation = "none",
		lastReason = "reset",
		lastUserId = nil,
	}
end

function PlayerLocationService.GetLocationSnapshot(userId: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
			snapshot = nil,
		}
	end

	local cached = snapshotByUserId[userId]
	if cached ~= nil then
		return {
			accepted = true,
			reason = "accepted",
			snapshot = cached,
		}
	end

	local hydrated = hydrateFromRealmAssignment(userId)
	if hydrated == nil then
		local initial = defaultSnapshot(os.time())
		snapshotByUserId[userId] = initial
		return {
			accepted = true,
			reason = "accepted",
			snapshot = initial,
		}
	end

	snapshotByUserId[userId] = hydrated
	return {
		accepted = true,
		reason = "accepted",
		snapshot = hydrated,
	}
end

function PlayerLocationService.HydrateFromRealmAssignment(userId: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end

	local hydrated = hydrateFromRealmAssignment(userId)
	if hydrated == nil then
		return {
			accepted = false,
			reason = "realm_assignment_unavailable",
		}
	end

	snapshotByUserId[userId] = hydrated
	return {
		accepted = true,
		reason = "accepted",
		snapshot = hydrated,
	}
end

function PlayerLocationService.ApplyTransition(userId: any, input: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
			snapshot = nil,
		}
	end

	if type(input) ~= "table" then
		recordTransitionDiagnostics(userId, "invalid", false, "transition_input_invalid")
		return {
			accepted = false,
			reason = "transition_input_invalid",
			snapshot = snapshotByUserId[userId],
		}
	end

	local operation = input.operation
	if type(operation) ~= "string" or operation == "" then
		recordTransitionDiagnostics(userId, "invalid", false, "transition_operation_invalid")
		return {
			accepted = false,
			reason = "transition_operation_invalid",
			snapshot = snapshotByUserId[userId],
		}
	end

	local snapshotResult = PlayerLocationService.GetLocationSnapshot(userId)
	local currentSnapshot = if snapshotResult.accepted == true and type(snapshotResult.snapshot) == "table"
		then snapshotResult.snapshot
		else defaultSnapshot(input.now)

	local transitionInput: PlayerLocationState.TransitionInput = {
		operation = operation,
		now = input.now,
		realmOwnerUserId = input.realmOwnerUserId,
		realmId = input.realmId,
		transitReason = input.transitReason,
	}

	local transitionResult = PlayerLocationState.ResolveTransition(currentSnapshot, transitionInput)
	recordTransitionDiagnostics(userId, operation, transitionResult.accepted == true, transitionResult.reason)

	if transitionResult.accepted == true and transitionResult.snapshot ~= nil then
		snapshotByUserId[userId] = transitionResult.snapshot
		debugLog(
			string.format(
				"transition userId=%d operation=%s location=%s reason=%s",
				userId,
				operation,
				transitionResult.snapshot.location,
				transitionResult.reason
			)
		)
	else
		debugLog(
			string.format(
				"transition_rejected userId=%d operation=%s reason=%s",
				userId,
				operation,
				transitionResult.reason
			)
		)
	end

	return {
		accepted = transitionResult.accepted == true,
		reason = transitionResult.reason,
		snapshot = if transitionResult.snapshot ~= nil then transitionResult.snapshot else currentSnapshot,
	}
end

function PlayerLocationService.ResolveDisconnect(userId: any, input: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
			snapshot = nil,
			action = PlayerLocationState.DisconnectActions.NoOp,
			persistReturnPending = false,
		}
	end

	local snapshotResult = PlayerLocationService.GetLocationSnapshot(userId)
	local currentSnapshot = if snapshotResult.accepted == true and type(snapshotResult.snapshot) == "table"
		then snapshotResult.snapshot
		else defaultSnapshot(if type(input) == "table" then input.now else nil)

	local disconnectInput: PlayerLocationState.DisconnectInput = {
		now = if type(input) == "table" and type(input.now) == "number" then input.now else os.time(),
	}

	local disconnectResult = PlayerLocationState.ResolveDisconnect(currentSnapshot, disconnectInput)
	diagnostics.totalDisconnectResolutions += 1
	diagnostics.lastOperation = "resolve_disconnect"
	diagnostics.lastReason = disconnectResult.reason
	diagnostics.lastUserId = userId

	if disconnectResult.accepted == true then
		snapshotByUserId[userId] = disconnectResult.snapshot
	end

	return {
		accepted = disconnectResult.accepted,
		reason = disconnectResult.reason,
		snapshot = disconnectResult.snapshot,
		action = disconnectResult.action,
		persistReturnPending = disconnectResult.persistReturnPending,
	}
end

function PlayerLocationService.GetDiagnostics(): LocationDiagnostics
	return cloneDiagnostics()
end

globalEnv._PlayerLocationService_QueryAPI = {
	GetLocationSnapshot = function(userId: any): any
		return PlayerLocationService.GetLocationSnapshot(userId)
	end,
	HydrateFromRealmAssignment = function(userId: any): any
		return PlayerLocationService.HydrateFromRealmAssignment(userId)
	end,
	ApplyTransition = function(userId: any, input: any): any
		return PlayerLocationService.ApplyTransition(userId, input)
	end,
	ResolveDisconnect = function(userId: any, input: any): any
		return PlayerLocationService.ResolveDisconnect(userId, input)
	end,
	GetDiagnostics = function(): LocationDiagnostics
		return PlayerLocationService.GetDiagnostics()
	end,
	ResetForTests = function()
		PlayerLocationService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_PlayerLocationService_QueryAPI", globalEnv._PlayerLocationService_QueryAPI)
end

return PlayerLocationService
