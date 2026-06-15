--!strict

local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else (require :: any)("./ProfilePersistenceGateway")

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

local RealmTransferAssignmentService: any = {}
local globalEnv: any = getfenv()

export type AssignmentDiagnostics = {
	totalTransitions: number,
	acceptedTransitions: number,
	rejectedTransitions: number,
	lastOperation: string,
	lastReason: string,
	lastUserId: number?,
}

local function debugLog(message: string)
	print(string.format("[RealmTransferAssignmentService] %s", message))
end

local assignmentByUserId: { [number]: RealmTransferState.AssignmentSnapshot? } = {}
local diagnostics: AssignmentDiagnostics = {
	totalTransitions = 0,
	acceptedTransitions = 0,
	rejectedTransitions = 0,
	lastOperation = "none",
	lastReason = "not_started",
	lastUserId = nil,
}

local function cloneDiagnostics(): AssignmentDiagnostics
	return {
		totalTransitions = diagnostics.totalTransitions,
		acceptedTransitions = diagnostics.acceptedTransitions,
		rejectedTransitions = diagnostics.rejectedTransitions,
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

local function makePlayerStub(userId: number): any
	return {
		UserId = userId,
	}
end

local function recordDiagnostics(userId: number, operation: string, accepted: boolean, reason: string)
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

local function persistAssignment(userId: number, assignment: RealmTransferState.AssignmentSnapshot): (boolean, string)
	local player = makePlayerStub(userId)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local applyResult = RealmAssignmentProfileState.ApplyAssignment(currentData, assignment)
		if not applyResult.accepted then
			return nil, applyResult.reason
		end
		return applyResult.profileData
	end)
	if not updateResult.ok then
		return false, updateResult.reason or "realm_assignment_persist_failed"
	end

	local saveResult = ProfilePersistenceGateway.SavePlayerProfile(player)
	if not saveResult.ok then
		return false, saveResult.reason or "realm_assignment_save_failed"
	end

	return true, "accepted"
end

local function hydrateAssignmentFromProfile(userId: number): RealmTransferState.AssignmentSnapshot?
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(makePlayerStub(userId))
	if not profileResult.ok or type(profileResult.data) ~= "table" then
		return nil
	end

	return RealmTransferState.ResolveCurrentAssignment(profileResult.data, os.time())
end

function RealmTransferAssignmentService.ResetForTests()
	assignmentByUserId = {}
	diagnostics = {
		totalTransitions = 0,
		acceptedTransitions = 0,
		rejectedTransitions = 0,
		lastOperation = "none",
		lastReason = "reset",
		lastUserId = nil,
	}
end

function RealmTransferAssignmentService.GetAssignmentSnapshot(userId: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
			assignment = nil,
		}
	end

	local cached = assignmentByUserId[userId]
	if cached ~= nil then
		return {
			accepted = true,
			reason = "accepted",
			assignment = cached,
		}
	end

	local hydrated = hydrateAssignmentFromProfile(userId)
	if hydrated == nil then
		return {
			accepted = false,
			reason = "profile_not_loaded",
			assignment = nil,
		}
	end

	assignmentByUserId[userId] = hydrated
	return {
		accepted = true,
		reason = "accepted",
		assignment = hydrated,
	}
end

function RealmTransferAssignmentService.HydrateFromProfile(userId: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end

	local hydrated = hydrateAssignmentFromProfile(userId)
	if hydrated == nil then
		return {
			accepted = false,
			reason = "profile_not_loaded",
		}
	end

	assignmentByUserId[userId] = hydrated
	return {
		accepted = true,
		reason = "accepted",
		assignment = hydrated,
	}
end

function RealmTransferAssignmentService.ApplyTransition(userId: any, input: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
			assignment = nil,
		}
	end

	if type(input) ~= "table" then
		recordDiagnostics(userId, "invalid", false, "transition_input_invalid")
		return {
			accepted = false,
			reason = "transition_input_invalid",
			assignment = assignmentByUserId[userId],
		}
	end

	local operation = input.operation
	if type(operation) ~= "string" or operation == "" then
		recordDiagnostics(userId, "invalid", false, "transition_operation_invalid")
		return {
			accepted = false,
			reason = "transition_operation_invalid",
			assignment = assignmentByUserId[userId],
		}
	end

	local snapshotResult = RealmTransferAssignmentService.GetAssignmentSnapshot(userId)
	local currentAssignment = if snapshotResult.accepted == true and type(snapshotResult.assignment) == "table"
		then snapshotResult.assignment
		else RealmTransferState.NewSharedHubAssignment(os.time())

	local transitionInput: RealmTransferState.TransitionInput = {
		operation = operation,
		now = input.now,
		realmOwnerUserId = input.realmOwnerUserId,
		realmId = input.realmId,
	}

	local transitionResult = RealmTransferState.ResolveTransition(currentAssignment, transitionInput)
	recordDiagnostics(userId, operation, transitionResult.accepted == true, transitionResult.reason)

	if transitionResult.accepted == true and transitionResult.assignment ~= nil then
		debugLog(
			string.format(
				"transition userId=%d operation=%s category=%s reason=%s realmId=%s",
				userId,
				operation,
				transitionResult.assignment.locationCategory,
				tostring(transitionResult.assignment.assignmentReason),
				tostring(transitionResult.assignment.realmId)
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

	if transitionResult.accepted ~= true or transitionResult.assignment == nil then
		return {
			accepted = false,
			reason = transitionResult.reason,
			assignment = currentAssignment,
		}
	end

	local persistOk, persistReason = persistAssignment(userId, transitionResult.assignment)
	if not persistOk then
		diagnostics.rejectedTransitions += 1
		diagnostics.acceptedTransitions -= 1
		diagnostics.lastReason = persistReason
		return {
			accepted = false,
			reason = persistReason,
			assignment = currentAssignment,
		}
	end

	assignmentByUserId[userId] = transitionResult.assignment
	return {
		accepted = true,
		reason = "accepted",
		assignment = transitionResult.assignment,
	}
end

function RealmTransferAssignmentService.DeriveEffectiveLocationCategory(input: any): string
	return RealmTransferState.DeriveEffectiveLocationCategory(input)
end

function RealmTransferAssignmentService.GetDiagnostics(): AssignmentDiagnostics
	return cloneDiagnostics()
end

globalEnv._RealmTransferAssignmentService_QueryAPI = {
	GetAssignmentSnapshot = function(userId: any): any
		return RealmTransferAssignmentService.GetAssignmentSnapshot(userId)
	end,
	HydrateFromProfile = function(userId: any): any
		return RealmTransferAssignmentService.HydrateFromProfile(userId)
	end,
	ApplyTransition = function(userId: any, input: any): any
		return RealmTransferAssignmentService.ApplyTransition(userId, input)
	end,
	DeriveEffectiveLocationCategory = function(input: any): string
		return RealmTransferAssignmentService.DeriveEffectiveLocationCategory(input)
	end,
	GetDiagnostics = function(): AssignmentDiagnostics
		return RealmTransferAssignmentService.GetDiagnostics()
	end,
	ResetForTests = function()
		RealmTransferAssignmentService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RealmTransferAssignmentService_QueryAPI", globalEnv._RealmTransferAssignmentService_QueryAPI)
end

return RealmTransferAssignmentService
