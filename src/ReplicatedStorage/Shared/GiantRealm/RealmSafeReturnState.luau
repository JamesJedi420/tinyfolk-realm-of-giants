--!strict

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PlayerLocationState"))
	else (require :: any)("./PlayerLocationState")

local RealmSafeReturnState: any = {}

RealmSafeReturnState.ReturnTrigger = {
	Escape = "escape",
	Timeout = "timeout",
	Logout = "logout",
	ServerShutdown = "server_shutdown",
	GiantDisconnect = "giant_disconnect",
	ModerationFallback = "moderation_fallback",
}

RealmSafeReturnState.ReturnPath = {
	NoOp = "no_op",
	OnlineHub = "online_hub",
	PersistPending = "persist_pending",
	OnlineCaptivitySafeReturn = "online_captivity_safe_return",
	ResolveDisconnect = "resolve_disconnect",
}

RealmSafeReturnState.ProfileReturnReason = {
	Logout = "logout",
	SafeReturn = "safe_return",
}

local Location = PlayerLocationState.Location
local Operations = PlayerLocationState.Operations
local ReturnTrigger = RealmSafeReturnState.ReturnTrigger
local ReturnPath = RealmSafeReturnState.ReturnPath

local validTriggerSet: { [string]: boolean } = {}
for _, triggerName in pairs(ReturnTrigger) do
	validTriggerSet[triggerName] = true
end

export type LocationOperation = {
	operation: string,
	realmOwnerUserId: number?,
	realmId: string?,
	transitReason: string?,
}

export type ReturnPlan = {
	accepted: boolean,
	reason: string,
	returnPath: string,
	locationOperations: { LocationOperation },
	persistSafeLocation: boolean,
	profileReturnReason: string?,
	sourceId: string?,
	applyOnlineCaptivitySafeReturn: boolean,
	abortAssignment: boolean,
	invalidateHandoff: boolean,
	useResolveDisconnect: boolean,
}

export type JoinResolutionPlan = {
	accepted: boolean,
	reason: string,
	locationOperations: { LocationOperation },
	abortAssignment: boolean,
	requiresSafeLocationSpawn: boolean,
}

local function reject(reason: string): ReturnPlan
	return {
		accepted = false,
		reason = reason,
		returnPath = ReturnPath.NoOp,
		locationOperations = {},
		persistSafeLocation = false,
		profileReturnReason = nil,
		sourceId = nil,
		applyOnlineCaptivitySafeReturn = false,
		abortAssignment = false,
		invalidateHandoff = false,
		useResolveDisconnect = false,
	}
end

local function accept(plan: {
	returnPath: string,
	locationOperations: { LocationOperation }?,
	persistSafeLocation: boolean?,
	profileReturnReason: string?,
	sourceId: string?,
	applyOnlineCaptivitySafeReturn: boolean?,
	abortAssignment: boolean?,
	invalidateHandoff: boolean?,
	useResolveDisconnect: boolean?,
}): ReturnPlan
	return {
		accepted = true,
		reason = "accepted",
		returnPath = plan.returnPath,
		locationOperations = plan.locationOperations or {},
		persistSafeLocation = plan.persistSafeLocation == true,
		profileReturnReason = plan.profileReturnReason,
		sourceId = plan.sourceId,
		applyOnlineCaptivitySafeReturn = plan.applyOnlineCaptivitySafeReturn == true,
		abortAssignment = plan.abortAssignment == true,
		invalidateHandoff = plan.invalidateHandoff == true,
		useResolveDisconnect = plan.useResolveDisconnect == true,
	}
end

local function op(operation: string, snapshot: any?, transitReason: string?): LocationOperation
	return {
		operation = operation,
		realmOwnerUserId = if snapshot ~= nil then snapshot.realmOwnerUserId else nil,
		realmId = if snapshot ~= nil then snapshot.realmId else nil,
		transitReason = transitReason,
	}
end

local function hubReturnOps(snapshot: any): { LocationOperation }
	if
		snapshot ~= nil
		and (snapshot.location == Location.ReturnPending or snapshot.location == Location.DisconnectedInRealm)
	then
		return { op(Operations.ResolveHub, snapshot) }
	end
	if snapshot.location == Location.Transit then
		return {
			op(Operations.AbortTransit, snapshot),
			op(Operations.ResolveHub, snapshot),
		}
	end
	if snapshot.location == Location.Escaping then
		return { op(Operations.EscapeSucceeded, snapshot) }
	end
	return {
		op(Operations.SetReturnPending, snapshot),
		op(Operations.ResolveHub, snapshot),
	}
end

function RealmSafeReturnState.ResolveReturnPlan(input: any): ReturnPlan
	if type(input) ~= "table" then
		return reject("return_plan_input_invalid")
	end

	local trigger = input.trigger
	if type(trigger) ~= "string" or validTriggerSet[trigger] ~= true then
		return reject("return_trigger_invalid")
	end

	local snapshot = PlayerLocationState.NormalizeSnapshot(input.locationSnapshot)
	if snapshot == nil then
		return reject("location_snapshot_invalid")
	end

	if snapshot.location == Location.SharedHub then
		return accept({
			returnPath = ReturnPath.NoOp,
		})
	end

	if trigger == ReturnTrigger.Escape then
		if snapshot.location ~= Location.Escaping then
			return reject("escape_location_invalid")
		end
		return accept({
			returnPath = ReturnPath.OnlineHub,
			locationOperations = { op(Operations.EscapeSucceeded, snapshot) },
			abortAssignment = true,
			invalidateHandoff = true,
			sourceId = "realm_safe_return_escape",
		})
	end

	if trigger == ReturnTrigger.Timeout then
		if snapshot.location ~= Location.Captured and snapshot.location ~= Location.Contained then
			return reject("timeout_location_invalid")
		end
		return accept({
			returnPath = ReturnPath.OnlineCaptivitySafeReturn,
			locationOperations = hubReturnOps(snapshot),
			persistSafeLocation = input.isOnline ~= true,
			profileReturnReason = RealmSafeReturnState.ProfileReturnReason.SafeReturn,
			sourceId = "realm_safe_return_timeout",
			applyOnlineCaptivitySafeReturn = input.isOnline == true,
			abortAssignment = true,
			invalidateHandoff = true,
		})
	end

	if trigger == ReturnTrigger.Logout then
		if not PlayerLocationState.RequiresSafeReturn(snapshot.location) then
			return reject("logout_location_invalid")
		end
		return accept({
			returnPath = ReturnPath.ResolveDisconnect,
			useResolveDisconnect = true,
			persistSafeLocation = true,
			profileReturnReason = RealmSafeReturnState.ProfileReturnReason.Logout,
			sourceId = "realm_safe_return_logout",
			abortAssignment = true,
			invalidateHandoff = true,
		})
	end

	if trigger == ReturnTrigger.ServerShutdown then
		if not PlayerLocationState.RequiresSafeReturn(snapshot.location) then
			return reject("server_shutdown_location_invalid")
		end
		return accept({
			returnPath = ReturnPath.PersistPending,
			locationOperations = hubReturnOps(snapshot),
			persistSafeLocation = true,
			profileReturnReason = RealmSafeReturnState.ProfileReturnReason.SafeReturn,
			sourceId = "realm_safe_return_server_shutdown",
			abortAssignment = true,
			invalidateHandoff = true,
		})
	end

	if trigger == ReturnTrigger.GiantDisconnect then
		if
			snapshot.location ~= Location.RealmGuest
			and snapshot.location ~= Location.RealmInvader
			and snapshot.location ~= Location.Transit
		then
			return reject("giant_disconnect_location_invalid")
		end
		return accept({
			returnPath = ReturnPath.OnlineHub,
			locationOperations = hubReturnOps(snapshot),
			persistSafeLocation = input.isOnline ~= true,
			profileReturnReason = RealmSafeReturnState.ProfileReturnReason.SafeReturn,
			sourceId = "realm_safe_return_giant_disconnect",
			abortAssignment = true,
			invalidateHandoff = true,
		})
	end

	if trigger == ReturnTrigger.ModerationFallback then
		if snapshot.location == Location.Captured or snapshot.location == Location.Contained then
			return accept({
				returnPath = ReturnPath.OnlineCaptivitySafeReturn,
				locationOperations = hubReturnOps(snapshot),
				persistSafeLocation = input.isOnline ~= true,
				profileReturnReason = RealmSafeReturnState.ProfileReturnReason.SafeReturn,
				sourceId = "realm_safe_return_moderation",
				applyOnlineCaptivitySafeReturn = input.isOnline == true,
				abortAssignment = true,
				invalidateHandoff = true,
			})
		end
		return accept({
			returnPath = ReturnPath.OnlineHub,
			locationOperations = hubReturnOps(snapshot),
			persistSafeLocation = input.isOnline ~= true,
			profileReturnReason = RealmSafeReturnState.ProfileReturnReason.SafeReturn,
			sourceId = "realm_safe_return_moderation",
			abortAssignment = true,
			invalidateHandoff = true,
		})
	end

	return reject("return_trigger_unhandled")
end

function RealmSafeReturnState.ResolveJoinPlan(input: any): JoinResolutionPlan
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "join_plan_input_invalid",
			locationOperations = {},
			abortAssignment = false,
			requiresSafeLocationSpawn = false,
		}
	end

	local snapshot = PlayerLocationState.NormalizeSnapshot(input.locationSnapshot)

	if input.hasSafeLocation == true then
		if snapshot ~= nil and snapshot.location == Location.SharedHub then
			return {
				accepted = true,
				reason = "accepted",
				locationOperations = {},
				abortAssignment = true,
				requiresSafeLocationSpawn = true,
			}
		end
		return {
			accepted = true,
			reason = "accepted",
			locationOperations = { op(Operations.ResolveHub, snapshot) },
			abortAssignment = true,
			requiresSafeLocationSpawn = true,
		}
	end

	if
		snapshot ~= nil
		and (snapshot.location == Location.ReturnPending or snapshot.location == Location.DisconnectedInRealm)
	then
		return {
			accepted = true,
			reason = "accepted",
			locationOperations = { op(Operations.ResolveHub, snapshot) },
			abortAssignment = true,
			requiresSafeLocationSpawn = false,
		}
	end

	return {
		accepted = true,
		reason = "no_pending_return",
		locationOperations = {},
		abortAssignment = false,
		requiresSafeLocationSpawn = false,
	}
end

function RealmSafeReturnState.ShouldReturnVisitorsForGiantDisconnect(
	locationSnapshot: any,
	giantOwnerUserId: any
): boolean
	local snapshot = PlayerLocationState.NormalizeSnapshot(locationSnapshot)
	if snapshot == nil then
		return false
	end
	if type(giantOwnerUserId) ~= "number" or giantOwnerUserId <= 0 or giantOwnerUserId % 1 ~= 0 then
		return false
	end
	if snapshot.realmOwnerUserId ~= giantOwnerUserId then
		return false
	end
	return snapshot.location == Location.RealmGuest
		or snapshot.location == Location.RealmInvader
		or snapshot.location == Location.Transit
end

return RealmSafeReturnState
