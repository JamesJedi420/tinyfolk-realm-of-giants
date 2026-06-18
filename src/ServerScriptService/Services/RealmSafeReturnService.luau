--!strict

local EscapeConfig = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("EscapeConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/EscapeConfig")

local RealmSafeReturnConfig = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Config")
			:WaitForChild("RealmSafeReturnConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/RealmSafeReturnConfig")

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PlayerLocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")

local RealmSafeReturnState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmSafeReturnState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmSafeReturnState")

local SafeLocationProfileState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Escape")
			:WaitForChild("SafeLocationProfileState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Escape/SafeLocationProfileState")

local CaptivitySafeReturnCaller = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("CaptivitySafeReturnCaller"))
	else (require :: any)("./CaptivitySafeReturnCaller")

local RealmSafeReturnService: any = {}
local globalEnv: any = getfenv()

export type ReturnDiagnostics = {
	totalReturnAttempts: number,
	totalReturnSucceeded: number,
	totalReturnFailed: number,
	totalJoinResolutions: number,
	lastTrigger: string,
	lastReason: string,
	lastUserId: number?,
}

local diagnostics: ReturnDiagnostics = {
	totalReturnAttempts = 0,
	totalReturnSucceeded = 0,
	totalReturnFailed = 0,
	totalJoinResolutions = 0,
	lastTrigger = "none",
	lastReason = "not_started",
	lastUserId = nil,
}

local locationApiOverride: any = nil
local assignmentApiOverride: any = nil
local handoffApiOverride: any = nil
local profileGatewayOverride: any = nil
local nowFnOverride: (() -> number)? = nil

local function cloneDiagnostics(): ReturnDiagnostics
	return {
		totalReturnAttempts = diagnostics.totalReturnAttempts,
		totalReturnSucceeded = diagnostics.totalReturnSucceeded,
		totalReturnFailed = diagnostics.totalReturnFailed,
		totalJoinResolutions = diagnostics.totalJoinResolutions,
		lastTrigger = diagnostics.lastTrigger,
		lastReason = diagnostics.lastReason,
		lastUserId = diagnostics.lastUserId,
	}
end

local function debugLog(message: string)
	print(string.format("[RealmSafeReturnService] %s", message))
end

local function now(): number
	if type(nowFnOverride) == "function" then
		local at = nowFnOverride()
		if type(at) == "number" and at == at then
			return at
		end
	end
	return os.time()
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

local function getHandoffApi(): any?
	if handoffApiOverride ~= nil then
		return handoffApiOverride
	end
	return getGlobalTable("_RealmTransferHandoffService_QueryAPI")
end

local function getProfileGateway(): any?
	if profileGatewayOverride ~= nil then
		return profileGatewayOverride
	end
	local gateway = getGlobalTable("_ProfilePersistenceGateway_QueryAPI")
	if type(gateway) == "table" then
		return gateway
	end
	if script ~= nil and script.Parent ~= nil then
		local ok, loaded = pcall(function()
			return require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
		end)
		if ok and type(loaded) == "table" then
			return loaded
		end
	end
	return nil
end

local function makePlayerStub(userId: number): any
	return {
		UserId = userId,
	}
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

local function applyLocationOperation(userId: number, operation: any, at: number)
	local locationApi = getLocationApi()
	if type(locationApi) ~= "table" or type(locationApi.ApplyTransition) ~= "function" then
		return
	end
	pcall(function()
		locationApi.ApplyTransition(userId, {
			operation = operation.operation,
			now = at,
			realmOwnerUserId = operation.realmOwnerUserId,
			realmId = operation.realmId,
			transitReason = operation.transitReason,
		})
	end)
end

local function abortAssignment(userId: number, at: number)
	local assignmentApi = getAssignmentApi()
	if type(assignmentApi) ~= "table" or type(assignmentApi.ApplyTransition) ~= "function" then
		return
	end
	pcall(function()
		assignmentApi.ApplyTransition(userId, {
			operation = "abort_to_hub",
			now = at,
		})
	end)
end

local function invalidateHandoff(userId: number, snapshot: any?, at: number)
	local handoffApi = getHandoffApi()
	if type(handoffApi) ~= "table" or type(handoffApi.InvalidateHandoffOnAbort) ~= "function" then
		return
	end
	pcall(function()
		handoffApi.InvalidateHandoffOnAbort({
			userId = userId,
			targetRealmId = if snapshot ~= nil then snapshot.realmId else nil,
			now = at,
		})
	end)
end

local function persistSafeLocation(
	userId: number,
	snapshot: any?,
	profileReturnReason: string,
	sourceId: string,
	at: number
): (boolean, string)
	local gateway = getProfileGateway()
	if type(gateway) ~= "table" or type(gateway.UpdateLoadedPlayerProfileData) ~= "function" then
		return false, "profile_gateway_missing"
	end

	local safeLocationInput = {
		returnPointName = EscapeConfig.TinyfolkReturnPointName,
		returnedAt = at,
		returnReason = profileReturnReason,
		realmId = if snapshot ~= nil then snapshot.realmId else nil,
		realmOwnerUserId = if snapshot ~= nil then snapshot.realmOwnerUserId else nil,
		sourceId = sourceId,
	}

	local ok, result = pcall(
		gateway.UpdateLoadedPlayerProfileData,
		makePlayerStub(userId),
		function(currentData: any): any
			if type(currentData) ~= "table" then
				return nil, "profile_data_invalid"
			end
			local safeLocationResult = SafeLocationProfileState.ApplySafeReturn(currentData, safeLocationInput)
			if safeLocationResult.accepted ~= true then
				return nil, safeLocationResult.reason
			end
			return safeLocationResult.profileData
		end
	)

	if not ok or type(result) ~= "table" or result.ok ~= true then
		return false,
			if type(result) == "table" and type(result.reason) == "string"
				then result.reason
				else "profile_update_failed"
	end

	return true, "return_pending_persisted"
end

local function recordReturnDiagnostics(userId: number, trigger: string, accepted: boolean, reason: string)
	diagnostics.totalReturnAttempts += 1
	if accepted then
		diagnostics.totalReturnSucceeded += 1
	else
		diagnostics.totalReturnFailed += 1
	end
	diagnostics.lastTrigger = trigger
	diagnostics.lastReason = reason
	diagnostics.lastUserId = userId
end

function RealmSafeReturnService.ResetForTests()
	diagnostics = {
		totalReturnAttempts = 0,
		totalReturnSucceeded = 0,
		totalReturnFailed = 0,
		totalJoinResolutions = 0,
		lastTrigger = "none",
		lastReason = "reset",
		lastUserId = nil,
	}
	locationApiOverride = nil
	assignmentApiOverride = nil
	handoffApiOverride = nil
	profileGatewayOverride = nil
	nowFnOverride = nil
end

function RealmSafeReturnService.SetTestOverrides(overrides: any)
	if type(overrides) ~= "table" then
		return
	end
	if overrides.locationApi ~= nil then
		locationApiOverride = overrides.locationApi
	end
	if overrides.assignmentApi ~= nil then
		assignmentApiOverride = overrides.assignmentApi
	end
	if overrides.handoffApi ~= nil then
		handoffApiOverride = overrides.handoffApi
	end
	if overrides.profileGateway ~= nil then
		profileGatewayOverride = overrides.profileGateway
	end
	if type(overrides.nowFn) == "function" then
		nowFnOverride = overrides.nowFn
	end
end

function RealmSafeReturnService.ApplyReturnRequest(userId: any, input: any): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end
	if type(input) ~= "table" then
		recordReturnDiagnostics(userId, "invalid", false, "return_input_invalid")
		return {
			accepted = false,
			reason = "return_input_invalid",
		}
	end

	local trigger = input.trigger
	local resolvedAt = if type(input.now) == "number" then input.now else now()
	local snapshot = getLocationSnapshot(userId)
	if snapshot == nil then
		recordReturnDiagnostics(userId, tostring(trigger), false, "location_snapshot_unavailable")
		return {
			accepted = false,
			reason = "location_snapshot_unavailable",
		}
	end

	local plan = RealmSafeReturnState.ResolveReturnPlan({
		trigger = trigger,
		locationSnapshot = snapshot,
		isOnline = input.isOnline,
	})
	if plan.accepted ~= true then
		recordReturnDiagnostics(userId, tostring(trigger), false, plan.reason)
		return {
			accepted = false,
			reason = plan.reason,
			returnPath = plan.returnPath,
		}
	end

	if plan.useResolveDisconnect then
		local locationApi = getLocationApi()
		if type(locationApi) ~= "table" or type(locationApi.ResolveDisconnect) ~= "function" then
			recordReturnDiagnostics(userId, tostring(trigger), false, "location_api_missing")
			return {
				accepted = false,
				reason = "location_api_missing",
			}
		end
		local disconnectResult = locationApi.ResolveDisconnect(userId, { now = resolvedAt })
		if disconnectResult.accepted ~= true then
			recordReturnDiagnostics(userId, tostring(trigger), false, disconnectResult.reason)
			return {
				accepted = false,
				reason = disconnectResult.reason,
			}
		end
		snapshot = PlayerLocationState.NormalizeSnapshot(disconnectResult.snapshot) or snapshot
		if plan.persistSafeLocation and disconnectResult.persistReturnPending == true then
			local profileReason = plan.profileReturnReason or RealmSafeReturnState.ProfileReturnReason.SafeReturn
			local sourceId = plan.sourceId or RealmSafeReturnConfig.SourceIds.Logout
			local persisted, persistReason = persistSafeLocation(userId, snapshot, profileReason, sourceId, resolvedAt)
			if not persisted then
				recordReturnDiagnostics(userId, tostring(trigger), false, persistReason)
				return {
					accepted = false,
					reason = persistReason,
				}
			end
		end
	else
		if plan.applyOnlineCaptivitySafeReturn then
			local captivityResult =
				CaptivitySafeReturnCaller.Apply(userId, resolvedAt, RealmSafeReturnState.ProfileReturnReason.SafeReturn)
			if type(captivityResult) ~= "table" or captivityResult.accepted ~= true then
				recordReturnDiagnostics(
					userId,
					tostring(trigger),
					false,
					if type(captivityResult) == "table" and type(captivityResult.reason) == "string"
						then captivityResult.reason
						else "captivity_safe_return_failed"
				)
				return {
					accepted = false,
					reason = if type(captivityResult) == "table" and type(captivityResult.reason) == "string"
						then captivityResult.reason
						else "captivity_safe_return_failed",
				}
			end
		end

		for _, locationOperation in ipairs(plan.locationOperations) do
			applyLocationOperation(userId, locationOperation, resolvedAt)
		end

		if plan.persistSafeLocation then
			local profileReason = plan.profileReturnReason or RealmSafeReturnState.ProfileReturnReason.SafeReturn
			local sourceId = plan.sourceId or RealmSafeReturnConfig.SourceIds.ServerShutdown
			local persisted, persistReason = persistSafeLocation(userId, snapshot, profileReason, sourceId, resolvedAt)
			if not persisted then
				recordReturnDiagnostics(userId, tostring(trigger), false, persistReason)
				return {
					accepted = false,
					reason = persistReason,
				}
			end
		end
	end

	if plan.abortAssignment then
		abortAssignment(userId, resolvedAt)
	end
	if plan.invalidateHandoff then
		invalidateHandoff(userId, snapshot, resolvedAt)
	end

	recordReturnDiagnostics(userId, tostring(trigger), true, "accepted")
	debugLog(string.format("return applied userId=%d trigger=%s path=%s", userId, tostring(trigger), plan.returnPath))

	return {
		accepted = true,
		reason = "accepted",
		returnPath = plan.returnPath,
		persistedSafeLocation = plan.persistSafeLocation or plan.useResolveDisconnect,
	}
end

function RealmSafeReturnService.ResolvePendingReturnOnJoin(userId: any, input: any?): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end

	local payload = if type(input) == "table" then input else {}
	local snapshot = getLocationSnapshot(userId)
	local hasSafeLocation = payload.hasSafeLocation == true
	local joinPlan = RealmSafeReturnState.ResolveJoinPlan({
		locationSnapshot = snapshot,
		hasSafeLocation = hasSafeLocation,
	})
	diagnostics.totalJoinResolutions += 1

	if joinPlan.accepted ~= true or #joinPlan.locationOperations == 0 then
		return {
			accepted = joinPlan.accepted,
			reason = joinPlan.reason,
			requiresSafeLocationSpawn = joinPlan.requiresSafeLocationSpawn,
		}
	end

	local resolvedAt = if type(payload.now) == "number" then payload.now else now()
	for _, locationOperation in ipairs(joinPlan.locationOperations) do
		applyLocationOperation(userId, locationOperation, resolvedAt)
	end
	if joinPlan.abortAssignment then
		abortAssignment(userId, resolvedAt)
	end

	return {
		accepted = true,
		reason = "accepted",
		requiresSafeLocationSpawn = joinPlan.requiresSafeLocationSpawn,
	}
end

function RealmSafeReturnService.HandleGiantDisconnect(giantOwnerUserId: any, input: any?): any
	if not isValidUserId(giantOwnerUserId) then
		return {
			accepted = false,
			reason = "giant_owner_user_id_invalid",
			returnedUserIds = {},
		}
	end

	local payload = if type(input) == "table" then input else {}
	local candidateUserIds = if type(payload.candidateUserIds) == "table" then payload.candidateUserIds else {}
	local returnedUserIds: { number } = {}

	for _, candidateUserId in ipairs(candidateUserIds) do
		if isValidUserId(candidateUserId) then
			local snapshot = getLocationSnapshot(candidateUserId)
			if
				snapshot ~= nil
				and RealmSafeReturnState.ShouldReturnVisitorsForGiantDisconnect(snapshot, giantOwnerUserId)
			then
				local result = RealmSafeReturnService.ApplyReturnRequest(candidateUserId, {
					trigger = RealmSafeReturnState.ReturnTrigger.GiantDisconnect,
					isOnline = payload.isOnline,
					now = payload.now,
				})
				if result.accepted == true then
					table.insert(returnedUserIds, candidateUserId)
				end
			end
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		returnedUserIds = returnedUserIds,
	}
end

function RealmSafeReturnService.ApplyCaptureLogoutSideEffects(userId: any, logoutPlan: any, at: any?): any
	if not isValidUserId(userId) then
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end
	if type(logoutPlan) ~= "table" or logoutPlan.accepted ~= true then
		return {
			accepted = false,
			reason = "logout_plan_invalid",
		}
	end

	local resolvedAt = if type(at) == "number" then at else now()
	local appliedTargetReturns = 0

	if type(logoutPlan.targetsToSafeReturn) == "table" then
		for _, targetUserId in ipairs(logoutPlan.targetsToSafeReturn) do
			if isValidUserId(targetUserId) then
				local result = RealmSafeReturnService.ApplyReturnRequest(targetUserId, {
					trigger = RealmSafeReturnState.ReturnTrigger.ModerationFallback,
					isOnline = true,
					now = resolvedAt,
				})
				if result.accepted == true then
					appliedTargetReturns += 1
				end
			end
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		appliedTargetReturns = appliedTargetReturns,
	}
end

function RealmSafeReturnService.GetDiagnostics(): ReturnDiagnostics
	return cloneDiagnostics()
end

globalEnv._RealmSafeReturnService_QueryAPI = {
	ApplyReturnRequest = function(userId: any, input: any): any
		return RealmSafeReturnService.ApplyReturnRequest(userId, input)
	end,
	ApplyCaptureLogoutSideEffects = function(userId: any, logoutPlan: any, at: any?): any
		return RealmSafeReturnService.ApplyCaptureLogoutSideEffects(userId, logoutPlan, at)
	end,
	ResolvePendingReturnOnJoin = function(userId: any, input: any?): any
		return RealmSafeReturnService.ResolvePendingReturnOnJoin(userId, input)
	end,
	HandleGiantDisconnect = function(giantOwnerUserId: any, input: any?): any
		return RealmSafeReturnService.HandleGiantDisconnect(giantOwnerUserId, input)
	end,
	GetDiagnostics = function(): ReturnDiagnostics
		return RealmSafeReturnService.GetDiagnostics()
	end,
	ResetForTests = function()
		RealmSafeReturnService.ResetForTests()
	end,
	SetTestOverrides = function(overrides: any)
		RealmSafeReturnService.SetTestOverrides(overrides)
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RealmSafeReturnService_QueryAPI", globalEnv._RealmSafeReturnService_QueryAPI)
end

return RealmSafeReturnService
