--!strict

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PlayerLocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")

local PlayerLocationAssignmentSyncCaller = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PlayerLocationAssignmentSyncCaller"))
	else (require :: any)("./PlayerLocationAssignmentSyncCaller")

local Operations = PlayerLocationState.Operations
local TransitReason = PlayerLocationState.TransitReason
local Location = PlayerLocationState.Location

local PlayerLocationTransitionCaller = {}

local function getLocationApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	return globalValue._PlayerLocationService_QueryAPI
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

local function applyTransition(userId: number, payload: any): any?
	return PlayerLocationAssignmentSyncCaller.ApplyLocationWithAssignmentSync(userId, payload)
end

function PlayerLocationTransitionCaller.ApplyCapture(userId: number, at: number?): any?
	local resolvedAt = if type(at) == "number" then at else os.time()
	return applyTransition(userId, {
		operation = Operations.Capture,
		now = resolvedAt,
	})
end

function PlayerLocationTransitionCaller.ApplyContain(userId: number, at: number?): any?
	local resolvedAt = if type(at) == "number" then at else os.time()
	return applyTransition(userId, {
		operation = Operations.Contain,
		now = resolvedAt,
	})
end

function PlayerLocationTransitionCaller.ApplyBeginEscape(userId: number, at: number?): any?
	local resolvedAt = if type(at) == "number" then at else os.time()
	return applyTransition(userId, {
		operation = Operations.BeginEscape,
		now = resolvedAt,
	})
end

function PlayerLocationTransitionCaller.ApplyEscapeSucceeded(userId: number, at: number?): any?
	local resolvedAt = if type(at) == "number" then at else os.time()
	return applyTransition(userId, {
		operation = Operations.EscapeSucceeded,
		now = resolvedAt,
	})
end

function PlayerLocationTransitionCaller.ApplyEscapeFailed(userId: number, at: number?): any?
	local resolvedAt = if type(at) == "number" then at else os.time()
	return applyTransition(userId, {
		operation = Operations.EscapeFailed,
		now = resolvedAt,
	})
end

function PlayerLocationTransitionCaller.ApplyReturnToHub(userId: number, at: number?): any?
	local resolvedAt = if type(at) == "number" then at else os.time()
	local snapshot = getLocationSnapshot(userId)
	if snapshot == nil then
		return nil
	end

	if snapshot.location == Location.Escaping then
		return applyTransition(userId, {
			operation = Operations.EscapeSucceeded,
			now = resolvedAt,
		})
	end

	if snapshot.location == Location.Transit and snapshot.transitReason == TransitReason.EscapeReturn then
		return applyTransition(userId, {
			operation = Operations.ConfirmHubReturn,
			now = resolvedAt,
		})
	end

	if
		snapshot.location == Location.Captured
		or snapshot.location == Location.Contained
		or snapshot.location == Location.RealmGuest
		or snapshot.location == Location.RealmInvader
	then
		local pendingResult = applyTransition(userId, {
			operation = Operations.SetReturnPending,
			now = resolvedAt,
		})
		if type(pendingResult) ~= "table" or pendingResult.accepted ~= true then
			return pendingResult
		end
		return applyTransition(userId, {
			operation = Operations.ResolveHub,
			now = resolvedAt,
		})
	end

	if snapshot.location == Location.ReturnPending or snapshot.location == Location.DisconnectedInRealm then
		return applyTransition(userId, {
			operation = Operations.ResolveHub,
			now = resolvedAt,
		})
	end

	return nil
end

function PlayerLocationTransitionCaller.ApplyEscapeReturnTransit(
	userId: number,
	realmOwnerUserId: number,
	realmId: string,
	at: number?
): any?
	local resolvedAt = if type(at) == "number" then at else os.time()
	local beginResult = applyTransition(userId, {
		operation = Operations.BeginTransit,
		now = resolvedAt,
		realmOwnerUserId = realmOwnerUserId,
		realmId = realmId,
		transitReason = TransitReason.EscapeReturn,
	})
	if type(beginResult) ~= "table" or beginResult.accepted ~= true then
		return beginResult
	end
	return applyTransition(userId, {
		operation = Operations.ConfirmHubReturn,
		now = resolvedAt,
	})
end

return PlayerLocationTransitionCaller
