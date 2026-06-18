--!strict

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PlayerLocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")

local RealmAdmissionLocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmAdmissionLocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmAdmissionLocationState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTransferState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local RealmAdmissionLocationCaller: any = {}
local globalEnv: any = getfenv()

local Location = PlayerLocationState.Location
local Operations = PlayerLocationState.Operations

local locationApiOverride: any = nil

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

local function applyTransition(userId: number, payload: any): any
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

function RealmAdmissionLocationCaller.ResetForTests()
	locationApiOverride = nil
end

function RealmAdmissionLocationCaller.SetTestOverrides(overrides: any)
	if type(overrides) ~= "table" then
		return
	end
	if overrides.locationApi ~= nil then
		locationApiOverride = overrides.locationApi
	end
end

function RealmAdmissionLocationCaller.ApplyBeginForAdmission(userId: any, input: any): any
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

	local targetRealmId = input.targetRealmId
	local realmOwnerUserId = if isPositiveInteger(input.realmOwnerUserId)
		then input.realmOwnerUserId
		else RealmTransferState.ParseRealmOwnerUserId(targetRealmId)
	if realmOwnerUserId == nil then
		return {
			accepted = true,
			reason = "realm_target_skipped",
		}
	end

	local transitReason = RealmAdmissionLocationState.ResolveTransitReason(input)
	if transitReason == nil then
		return {
			accepted = false,
			reason = "transit_reason_invalid",
		}
	end

	local resolvedAt = if type(input.now) == "number" then input.now else os.time()
	local snapshot = getLocationSnapshot(userId)
	if snapshot ~= nil and RealmAdmissionLocationState.IsMatchingTransit(snapshot, targetRealmId, transitReason) then
		return {
			accepted = true,
			reason = "already_in_transit",
		}
	end

	return applyTransition(userId, {
		operation = Operations.BeginTransit,
		now = resolvedAt,
		realmOwnerUserId = realmOwnerUserId,
		realmId = targetRealmId,
		transitReason = transitReason,
	})
end

function RealmAdmissionLocationCaller.ApplyBeginForAdmissionMembers(memberUserIds: any, input: any): any
	if type(memberUserIds) ~= "table" or #memberUserIds <= 0 then
		return {
			accepted = false,
			reason = "admission_party_members_invalid",
		}
	end

	local begunUserIds: { number } = {}
	for _, userId in ipairs(memberUserIds) do
		local beginResult = RealmAdmissionLocationCaller.ApplyBeginForAdmission(userId, input)
		if type(beginResult) ~= "table" or beginResult.accepted ~= true then
			for _, begunUserId in ipairs(begunUserIds) do
				RealmAdmissionLocationCaller.ApplyAbortRollback(begunUserId, input)
			end
			return {
				accepted = false,
				reason = if type(beginResult) == "table" and type(beginResult.reason) == "string"
					then beginResult.reason
					else "location_begin_failed",
			}
		end
		if beginResult.reason ~= "already_in_transit" then
			table.insert(begunUserIds, userId)
		end
	end

	return {
		accepted = true,
		reason = "accepted",
	}
end

function RealmAdmissionLocationCaller.ApplyConfirmForArrival(userId: any, input: any): any
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

	local targetRealmId = input.targetRealmId
	local realmOwnerUserId = if isPositiveInteger(input.realmOwnerUserId)
		then input.realmOwnerUserId
		else RealmTransferState.ParseRealmOwnerUserId(targetRealmId)
	if realmOwnerUserId == nil then
		return {
			accepted = true,
			reason = "realm_target_skipped",
		}
	end

	local resolvedAt = if type(input.now) == "number" then input.now else os.time()
	local snapshot = getLocationSnapshot(userId)
	local confirmOperation = RealmAdmissionLocationState.ResolveConfirmOperation({
		assignmentReason = input.assignmentReason,
		transitReason = if snapshot ~= nil then snapshot.transitReason else nil,
	})

	return applyTransition(userId, {
		operation = confirmOperation,
		now = resolvedAt,
		realmOwnerUserId = realmOwnerUserId,
		realmId = targetRealmId,
	})
end

function RealmAdmissionLocationCaller.ApplyAbortRollback(userId: any, input: any?): any
	if not isPositiveInteger(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end

	local resolvedAt = if type(input) == "table" and type(input.now) == "number" then input.now else os.time()
	local snapshot = getLocationSnapshot(userId)
	if snapshot == nil or snapshot.location ~= Location.Transit then
		return {
			accepted = true,
			reason = "not_in_transit",
		}
	end

	local abortResult = applyTransition(userId, {
		operation = Operations.AbortTransit,
		now = resolvedAt,
	})
	if type(abortResult) ~= "table" or abortResult.accepted ~= true then
		return abortResult
	end

	return applyTransition(userId, {
		operation = Operations.ResolveHub,
		now = resolvedAt,
	})
end

function RealmAdmissionLocationCaller.ApplyAbortRollbackForMembers(memberUserIds: any, input: any?): any
	if type(memberUserIds) ~= "table" then
		return {
			accepted = true,
			reason = "no_members",
		}
	end

	for _, userId in ipairs(memberUserIds) do
		RealmAdmissionLocationCaller.ApplyAbortRollback(userId, input)
	end

	return {
		accepted = true,
		reason = "accepted",
	}
end

return RealmAdmissionLocationCaller
