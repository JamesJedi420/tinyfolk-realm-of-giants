--!strict

local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else (require :: any)("./ProfilePersistenceGateway")

local PendingRecoveryProfileState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PendingRecoveryProfileState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PendingRecoveryProfileState")

local DiscoveredRealmsProfileState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("DiscoveredRealmsProfileState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/DiscoveredRealmsProfileState")

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

local RealmTransferHandoffService = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferHandoffService"))
	else (require :: any)("./RealmTransferHandoffService")

local RealmTransferAssignmentService = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferAssignmentService"))
	else (require :: any)("./RealmTransferAssignmentService")

local GiantLevelTradeXpProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("GiantLevelTradeXpProducer"))
	else (require :: any)("./GiantLevelTradeXpProducer")

local RealmTradeConversionProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTradeConversionProducer"))
	else (require :: any)("./RealmTradeConversionProducer")

local ProfileTeleportHandoffService: any = {}
local globalEnv: any = getfenv()

export type HandoffResult = {
	ok: boolean,
	operation: string,
	reason: string?,
	retryable: boolean?,
	handoffToken: string?,
	fallbackRoute: string?,
}

export type AdmissionIngressDiagnostics = {
	totalAttempts: number,
	primaryAttempts: number,
	primarySucceeded: number,
	primaryFailed: number,
	fallbackAttempts: number,
	fallbackSucceeded: number,
	fallbackFailed: number,
	lastPath: string,
	lastReason: string,
	lastPrimaryReason: string,
	lastFallbackReason: string,
}

export type DestinationOrchestrationDiagnostics = {
	totalAttempts: number,
	confirmed: number,
	awaitingOwnership: number,
	noTransferSkipped: number,
	confirmFailed: number,
	capacityCommitted: number,
	capacitySkipped: number,
	lastReason: string,
}

local pendingHandoffByUserId: { [number]: { handoffToken: string, targetRealmId: string? }? } = {}
local releaseReadyCallbacksByUserId: { [number]: { (HandoffResult) -> () }? } = {}
local admissionIngressDiagnostics: AdmissionIngressDiagnostics = {
	totalAttempts = 0,
	primaryAttempts = 0,
	primarySucceeded = 0,
	primaryFailed = 0,
	fallbackAttempts = 0,
	fallbackSucceeded = 0,
	fallbackFailed = 0,
	lastPath = "none",
	lastReason = "none",
	lastPrimaryReason = "none",
	lastFallbackReason = "none",
}
local destinationOrchestrationStarted = false
local destinationAwaitingOwnershipByUserId: { [number]: boolean } = {}
local destinationOrchestrationDiagnostics: DestinationOrchestrationDiagnostics = {
	totalAttempts = 0,
	confirmed = 0,
	awaitingOwnership = 0,
	noTransferSkipped = 0,
	confirmFailed = 0,
	capacityCommitted = 0,
	capacitySkipped = 0,
	lastReason = "not_started",
}
local destinationTeleportContextResolver: ((player: any) -> any?)? = nil

local function cloneAdmissionIngressDiagnostics(): AdmissionIngressDiagnostics
	return {
		totalAttempts = admissionIngressDiagnostics.totalAttempts,
		primaryAttempts = admissionIngressDiagnostics.primaryAttempts,
		primarySucceeded = admissionIngressDiagnostics.primarySucceeded,
		primaryFailed = admissionIngressDiagnostics.primaryFailed,
		fallbackAttempts = admissionIngressDiagnostics.fallbackAttempts,
		fallbackSucceeded = admissionIngressDiagnostics.fallbackSucceeded,
		fallbackFailed = admissionIngressDiagnostics.fallbackFailed,
		lastPath = admissionIngressDiagnostics.lastPath,
		lastReason = admissionIngressDiagnostics.lastReason,
		lastPrimaryReason = admissionIngressDiagnostics.lastPrimaryReason,
		lastFallbackReason = admissionIngressDiagnostics.lastFallbackReason,
	}
end

local function cloneDestinationOrchestrationDiagnostics(): DestinationOrchestrationDiagnostics
	return {
		totalAttempts = destinationOrchestrationDiagnostics.totalAttempts,
		confirmed = destinationOrchestrationDiagnostics.confirmed,
		awaitingOwnership = destinationOrchestrationDiagnostics.awaitingOwnership,
		noTransferSkipped = destinationOrchestrationDiagnostics.noTransferSkipped,
		confirmFailed = destinationOrchestrationDiagnostics.confirmFailed,
		capacityCommitted = destinationOrchestrationDiagnostics.capacityCommitted,
		capacitySkipped = destinationOrchestrationDiagnostics.capacitySkipped,
		lastReason = destinationOrchestrationDiagnostics.lastReason,
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

local function getPlayerUserId(player: any): number?
	if type(player) ~= "table" and typeof(player) ~= "Instance" then
		return nil
	end

	local userId = player.UserId
	if not isValidUserId(userId) then
		return nil
	end

	return userId
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function makeResult(
	ok: boolean,
	operation: string,
	reason: string?,
	retryable: boolean?,
	handoffToken: string?,
	fallbackRoute: string?
): HandoffResult
	return {
		ok = ok,
		operation = operation,
		reason = reason,
		retryable = retryable,
		handoffToken = handoffToken,
		fallbackRoute = fallbackRoute,
	}
end

local function makePlayerStub(userId: number): any
	return {
		UserId = userId,
	}
end

local function persistPendingRecovery(
	player: any,
	handoffToken: string,
	targetRealmId: string,
	startedAt: number
): (boolean, string?)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local applyResult = PendingRecoveryProfileState.ApplyPendingHandoff(currentData, {
			handoffToken = handoffToken,
			targetRealmId = targetRealmId,
			startedAt = startedAt,
			status = PendingRecoveryProfileState.Status.AwaitingDestination,
		})
		if not applyResult.accepted then
			return nil, applyResult.reason
		end
		return applyResult.profileData
	end)
	if not updateResult.ok then
		return false, updateResult.reason or "pending_recovery_persist_failed"
	end

	local saveResult = ProfilePersistenceGateway.SavePlayerProfile(player)
	if not saveResult.ok then
		return false, saveResult.reason or "pending_recovery_save_failed"
	end

	return true, nil
end

local function clearPersistedPendingRecovery(userId: number)
	local player = makePlayerStub(userId)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local clearResult = PendingRecoveryProfileState.ClearRecovery(currentData)
		if not clearResult.accepted then
			return nil, clearResult.reason
		end
		return clearResult.profileData
	end)
	if updateResult.ok then
		pcall(ProfilePersistenceGateway.SavePlayerProfile, player)
	end
end

local function persistDiscoveredRealm(userId: number, realmId: string, discoveredAt: number)
	local player = makePlayerStub(userId)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local recordResult = DiscoveredRealmsProfileState.RecordDiscovery(currentData, {
			realmId = realmId,
			firstDiscoveredAt = discoveredAt,
		})
		if not recordResult.accepted then
			return nil, recordResult.reason
		end
		return recordResult.profileData
	end)
	if updateResult.ok then
		pcall(ProfilePersistenceGateway.SavePlayerProfile, player)
	end
end

local function tryRestorePendingHandoffFromProfile(userId: number): boolean
	if pendingHandoffByUserId[userId] ~= nil then
		return true
	end

	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(makePlayerStub(userId))
	if not profileResult.ok or type(profileResult.data) ~= "table" then
		return false
	end

	local recovery = PendingRecoveryProfileState.GetRecovery(profileResult.data)
	if recovery == nil then
		return false
	end

	pendingHandoffByUserId[userId] = {
		handoffToken = recovery.handoffToken,
		targetRealmId = recovery.targetRealmId,
	}
	return true
end

local function clearPendingHandoff(userId: number)
	local pending = pendingHandoffByUserId[userId]
	if pending ~= nil and isNonEmptyString(pending.targetRealmId) then
		persistDiscoveredRealm(userId, pending.targetRealmId :: string, os.time())
	end

	pendingHandoffByUserId[userId] = nil
	releaseReadyCallbacksByUserId[userId] = nil
	clearPersistedPendingRecovery(userId)
end

local function getRealmTransferHandoffQueryApi(): any?
	local queryApi = globalEnv._RealmTransferHandoffService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(RealmTransferHandoffService) == "table" then
		return RealmTransferHandoffService
	end
	return nil
end

local function getRealmTransferAssignmentQueryApi(): any?
	local queryApi = globalEnv._RealmTransferAssignmentService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if
		type(RealmTransferAssignmentService) == "table"
		and type(RealmTransferAssignmentService.ApplyTransition) == "function"
	then
		return RealmTransferAssignmentService
	end
	return nil
end

local function resolveRealmOwnerUserId(targetRealmId: string, context: any?): number?
	local contextAny: any = context
	if type(contextAny) == "table" and isValidUserId(contextAny.realmOwnerUserId) then
		return contextAny.realmOwnerUserId
	end
	return RealmTransferState.ParseRealmOwnerUserId(targetRealmId)
end

local function resolveAssignmentReason(context: any?): string
	local contextAny: any = context
	if type(contextAny) ~= "table" then
		return RealmAssignmentProfileState.AssignmentReason.PartyAdmission
	end

	local assignmentReason = contextAny.assignmentReason
	if isNonEmptyString(assignmentReason) then
		return assignmentReason
	end

	local flow = contextAny.flow
	if flow == "capture" then
		return RealmAssignmentProfileState.AssignmentReason.Capture
	end
	if flow == "rescue" then
		return RealmAssignmentProfileState.AssignmentReason.Rescue
	end
	if flow == "trade" then
		return RealmAssignmentProfileState.AssignmentReason.Trade
	end
	if flow == "escape_return" or flow == "realm_to_hub" then
		return RealmAssignmentProfileState.AssignmentReason.EscapeReturn
	end

	return RealmAssignmentProfileState.AssignmentReason.PartyAdmission
end

local function abortControlledTransferHandoff(userId: number, handoffToken: string, targetRealmId: string?)
	if not isNonEmptyString(targetRealmId) or not isNonEmptyString(handoffToken) then
		return
	end

	local handoffApi = getRealmTransferHandoffQueryApi()
	if handoffApi == nil or type(handoffApi.InvalidateHandoffOnAbort) ~= "function" then
		if handoffApi ~= nil and type(handoffApi.ConsumeHandoffOnArrival) == "function" then
			pcall(handoffApi.ConsumeHandoffOnArrival, {
				userId = userId,
				handoffToken = handoffToken,
				targetRealmId = targetRealmId,
				now = os.time(),
			})
		end
		return
	end

	pcall(handoffApi.InvalidateHandoffOnAbort, {
		handoffToken = handoffToken,
		targetRealmId = targetRealmId,
		now = os.time(),
	})
end

local function resolveConfirmOperation(assignmentReason: string?): string
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.EscapeReturn then
		return RealmTransferState.Operations.ConfirmHubReturn
	end
	return RealmTransferState.Operations.ConfirmArrival
end

local function getPendingRecoveryForUserId(userId: number): any?
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(makePlayerStub(userId))
	if not profileResult.ok or type(profileResult.data) ~= "table" then
		return nil
	end
	return PendingRecoveryProfileState.GetRecovery(profileResult.data)
end

local function pendingRecoveryMatchesHandoff(recovery: any?, handoffToken: string, targetRealmId: string): boolean
	if recovery == nil then
		return false
	end
	if recovery.status ~= PendingRecoveryProfileState.Status.AwaitingDestination then
		return false
	end
	return recovery.handoffToken == handoffToken and recovery.targetRealmId == targetRealmId
end

local function getGiantLevelServiceQueryApi(): any?
	local queryApi = globalEnv._GiantLevelService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._GiantLevelService_QueryAPI) == "table" then
		return (_G :: any)._GiantLevelService_QueryAPI
	end
	return nil
end

local function getRealmTradeConversionServiceQueryApi(): any?
	local queryApi = globalEnv._RealmTradeConversionService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._RealmTradeConversionService_QueryAPI) == "table" then
		return (_G :: any)._RealmTradeConversionService_QueryAPI
	end
	return nil
end

local function recordTradeRewardsFromHandoff(handoffEntry: any?)
	if type(handoffEntry) ~= "table" then
		return
	end
	if handoffEntry.assignmentReason ~= RealmAssignmentProfileState.AssignmentReason.Trade then
		return
	end

	local awardedAt = os.time()
	local giantLevelApi = getGiantLevelServiceQueryApi()
	if giantLevelApi ~= nil then
		pcall(GiantLevelTradeXpProducer.RecordFromHandoffEntry, handoffEntry, awardedAt, {
			giantLevelApi = giantLevelApi,
		})
	end

	local conversionApi = getRealmTradeConversionServiceQueryApi()
	if conversionApi ~= nil then
		pcall(RealmTradeConversionProducer.RecordFromHandoffEntry, handoffEntry, awardedAt, {
			conversionApi = conversionApi,
		})
	end
end

local function resolveBeginOperation(assignmentReason: string): string?
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.Capture then
		return RealmTransferState.Operations.BeginCapture
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.Rescue then
		return RealmTransferState.Operations.BeginRescue
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.Trade then
		return RealmTransferState.Operations.BeginTrade
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.EscapeReturn then
		return RealmTransferState.Operations.BeginEscapeReturn
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.PartyAdmission then
		return RealmTransferState.Operations.BeginPartyAdmission
	end
	return nil
end

local function applyAssignmentTransition(
	userId: number,
	operation: string,
	targetRealmId: string,
	context: any?
): (boolean, string?)
	local assignmentApi = getRealmTransferAssignmentQueryApi()
	if assignmentApi == nil or type(assignmentApi.ApplyTransition) ~= "function" then
		return true, nil
	end

	local realmOwnerUserId = resolveRealmOwnerUserId(targetRealmId, context)
	if realmOwnerUserId == nil then
		return false, "realm_target_invalid"
	end

	local transitionResult = assignmentApi.ApplyTransition(userId, {
		operation = operation,
		now = os.time(),
		realmOwnerUserId = realmOwnerUserId,
		realmId = targetRealmId,
	})
	if type(transitionResult) ~= "table" or transitionResult.accepted ~= true then
		local reason = if type(transitionResult) == "table" and type(transitionResult.reason) == "string"
			then transitionResult.reason
			else "assignment_transition_failed"
		return false, reason
	end

	return true, nil
end

local function beginControlledTransferHandoff(
	userId: number,
	targetRealmId: string,
	context: any?
): (boolean, string?, string?)
	local handoffApi = getRealmTransferHandoffQueryApi()
	if handoffApi == nil or type(handoffApi.BeginHandoff) ~= "function" then
		return false, "handoff_service_unavailable", nil
	end

	local contextAny: any = context
	local operationId = if type(contextAny) == "table" and isNonEmptyString(contextAny.operationId)
		then contextAny.operationId
		else nil
	local assignmentReason = resolveAssignmentReason(context)
	local realmOwnerUserId = resolveRealmOwnerUserId(targetRealmId, context)

	local beginResult = handoffApi.BeginHandoff({
		userId = userId,
		targetRealmId = targetRealmId,
		operationId = operationId,
		assignmentReason = assignmentReason,
		realmOwnerUserId = realmOwnerUserId,
		now = os.time(),
	})
	if type(beginResult) ~= "table" or beginResult.accepted ~= true then
		local reason = if type(beginResult) == "table" and type(beginResult.reason) == "string"
			then beginResult.reason
			else "handoff_begin_failed"
		return false, reason, nil
	end

	local handoffToken = beginResult.handoffToken
	if not isNonEmptyString(handoffToken) then
		return false, "handoff_token_missing", nil
	end

	local beginOperation = resolveBeginOperation(assignmentReason)
	if beginOperation == nil then
		return false, "assignment_reason_invalid", nil
	end

	if realmOwnerUserId ~= nil then
		local transitionOk, transitionReason = applyAssignmentTransition(userId, beginOperation, targetRealmId, context)
		if not transitionOk then
			abortControlledTransferHandoff(userId, handoffToken, targetRealmId)
			return false, transitionReason or "assignment_transition_failed", nil
		end
	end

	return true, nil, handoffToken
end

local function consumeControlledTransferHandoff(
	userId: number,
	handoffToken: string,
	targetRealmId: string?
): (boolean, string?, any?)
	if not isNonEmptyString(targetRealmId) then
		return false, "handoff_target_realm_invalid", nil
	end

	local resolvedTargetRealmId = targetRealmId :: string
	local recovery = getPendingRecoveryForUserId(userId)
	local handoffApi = getRealmTransferHandoffQueryApi()
	if handoffApi ~= nil and type(handoffApi.ResolveExpiredSession) == "function" then
		local resolutionResult = handoffApi.ResolveExpiredSession({
			handoffToken = handoffToken,
			targetRealmId = resolvedTargetRealmId,
			now = os.time(),
		})
		if type(resolutionResult) == "table" then
			if resolutionResult.resolution == "safe_fallback" then
				return false, resolutionResult.reason or "handoff_token_not_found", nil
			end
			if
				resolutionResult.resolution == "pending_recovery_authority"
				and pendingRecoveryMatchesHandoff(recovery, handoffToken, resolvedTargetRealmId)
			then
				local assignmentApi = getRealmTransferAssignmentQueryApi()
				if assignmentApi == nil or type(assignmentApi.ApplyTransition) ~= "function" then
					return true, nil, resolutionResult.handoffEntry
				end

				local assignmentReason = if type(resolutionResult.handoffEntry) == "table"
					then resolutionResult.handoffEntry.assignmentReason
					else nil
				local realmOwnerUserId = RealmTransferState.ParseRealmOwnerUserId(resolvedTargetRealmId)
				if realmOwnerUserId == nil and type(resolutionResult.handoffEntry) == "table" then
					local entryAny: any = resolutionResult.handoffEntry
					if isValidUserId(entryAny.realmOwnerUserId) then
						realmOwnerUserId = entryAny.realmOwnerUserId
					end
				end
				if realmOwnerUserId ~= nil then
					local transitionResult = assignmentApi.ApplyTransition(userId, {
						operation = resolveConfirmOperation(assignmentReason),
						now = os.time(),
						realmOwnerUserId = realmOwnerUserId,
						realmId = resolvedTargetRealmId,
					})
					if type(transitionResult) ~= "table" or transitionResult.accepted ~= true then
						local reason = if type(transitionResult) == "table"
								and type(transitionResult.reason) == "string"
							then transitionResult.reason
							else "assignment_confirm_failed"
						return false, reason, nil
					end
				end
				return true, nil, resolutionResult.handoffEntry
			end
		end
	end

	if handoffApi == nil or type(handoffApi.ConsumeHandoffOnArrival) ~= "function" then
		return true, nil, nil
	end

	local consumeResult = handoffApi.ConsumeHandoffOnArrival({
		userId = userId,
		handoffToken = handoffToken,
		targetRealmId = resolvedTargetRealmId,
		now = os.time(),
	})
	if type(consumeResult) ~= "table" or consumeResult.accepted ~= true then
		local reason = if type(consumeResult) == "table" and type(consumeResult.reason) == "string"
			then consumeResult.reason
			else "handoff_consume_failed"
		if reason == "session_record_missing" then
			if pendingRecoveryMatchesHandoff(recovery, handoffToken, resolvedTargetRealmId) then
				local assignmentApi = getRealmTransferAssignmentQueryApi()
				if assignmentApi == nil or type(assignmentApi.ApplyTransition) ~= "function" then
					return true, nil, nil
				end

				local realmOwnerUserId = RealmTransferState.ParseRealmOwnerUserId(resolvedTargetRealmId)
				if realmOwnerUserId ~= nil then
					local transitionResult = assignmentApi.ApplyTransition(userId, {
						operation = RealmTransferState.Operations.ConfirmArrival,
						now = os.time(),
						realmOwnerUserId = realmOwnerUserId,
						realmId = resolvedTargetRealmId,
					})
					if type(transitionResult) ~= "table" or transitionResult.accepted ~= true then
						local transitionReason = if type(transitionResult) == "table"
								and type(transitionResult.reason) == "string"
							then transitionResult.reason
							else "assignment_confirm_failed"
						return false, transitionReason, nil
					end
				end
				return true, nil, nil
			end
			return true, nil, nil
		end
		if
			reason == "handoff_token_expired"
			and pendingRecoveryMatchesHandoff(recovery, handoffToken, resolvedTargetRealmId)
		then
			local assignmentApi = getRealmTransferAssignmentQueryApi()
			if assignmentApi == nil or type(assignmentApi.ApplyTransition) ~= "function" then
				return true, nil, consumeResult.handoffEntry
			end

			local assignmentReason = if type(consumeResult.handoffEntry) == "table"
				then consumeResult.handoffEntry.assignmentReason
				else nil
			local realmOwnerUserId = RealmTransferState.ParseRealmOwnerUserId(resolvedTargetRealmId)
			if realmOwnerUserId == nil and type(consumeResult.handoffEntry) == "table" then
				local entryAny: any = consumeResult.handoffEntry
				if isValidUserId(entryAny.realmOwnerUserId) then
					realmOwnerUserId = entryAny.realmOwnerUserId
				end
			end
			if realmOwnerUserId ~= nil then
				local transitionResult = assignmentApi.ApplyTransition(userId, {
					operation = resolveConfirmOperation(assignmentReason),
					now = os.time(),
					realmOwnerUserId = realmOwnerUserId,
					realmId = resolvedTargetRealmId,
				})
				if type(transitionResult) ~= "table" or transitionResult.accepted ~= true then
					local transitionReason = if type(transitionResult) == "table"
							and type(transitionResult.reason) == "string"
						then transitionResult.reason
						else "assignment_confirm_failed"
					return false, transitionReason, nil
				end
			end
			return true, nil, consumeResult.handoffEntry
		end
		return false, reason, consumeResult.handoffEntry
	end

	local assignmentApi = getRealmTransferAssignmentQueryApi()
	if assignmentApi == nil or type(assignmentApi.ApplyTransition) ~= "function" then
		return true, nil, consumeResult.handoffEntry
	end

	local realmOwnerUserId = RealmTransferState.ParseRealmOwnerUserId(resolvedTargetRealmId)
	if realmOwnerUserId == nil and type(consumeResult.handoffEntry) == "table" then
		local entryAny: any = consumeResult.handoffEntry
		if isValidUserId(entryAny.realmOwnerUserId) then
			realmOwnerUserId = entryAny.realmOwnerUserId
		end
	end
	if realmOwnerUserId ~= nil then
		local assignmentReason = if type(consumeResult.handoffEntry) == "table"
			then consumeResult.handoffEntry.assignmentReason
			else nil
		local transitionResult = assignmentApi.ApplyTransition(userId, {
			operation = resolveConfirmOperation(assignmentReason),
			now = os.time(),
			realmOwnerUserId = realmOwnerUserId,
			realmId = resolvedTargetRealmId,
		})
		if type(transitionResult) ~= "table" or transitionResult.accepted ~= true then
			local reason = if type(transitionResult) == "table" and type(transitionResult.reason) == "string"
				then transitionResult.reason
				else "assignment_confirm_failed"
			return false, reason, consumeResult.handoffEntry
		end
	end

	return true, nil, consumeResult.handoffEntry
end

local function getPartyMatchmakingAdmissionQueryApi(): any?
	local queryApi = globalEnv._PartyMatchmakingAdmissionService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	if type((queryApi :: any).RequestPartyMatchAdmission) ~= "function" then
		return nil
	end

	return queryApi
end

local function getProfileTeleportAdmissionQueryApi(): any?
	local queryApi = globalEnv._ProfileTeleportAdmissionService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	if type((queryApi :: any).RequestTeleportHandoffAdmission) ~= "function" then
		return nil
	end

	return queryApi
end

local function isRetryableEnqueueReason(reason: string?): boolean
	return reason == "admission_queue_unavailable" or reason == "admission_enqueue_failed"
end

local function finalizeAdmissionResult(result: any): any
	if type(result) ~= "table" then
		return {
			accepted = false,
			reason = "admission_enqueue_failed",
		}
	end

	if result.accepted ~= true then
		return {
			accepted = false,
			reason = if type(result.reason) == "string" then result.reason else "admission_enqueue_failed",
		}
	end

	return {
		accepted = true,
		reason = if type(result.reason) == "string" then result.reason else "accepted",
	}
end

local function requestAdmissionViaProfileTeleportService(
	userId: number,
	handoffToken: string,
	targetRealmId: string
): any
	local admissionApi = getProfileTeleportAdmissionQueryApi()
	if type(admissionApi) ~= "table" then
		return {
			accepted = false,
			reason = "admission_queue_unavailable",
		}
	end

	local ok, result = pcall(function()
		return (admissionApi :: any).RequestTeleportHandoffAdmission({
			userId = userId,
			handoffToken = handoffToken,
			targetRealmId = targetRealmId,
		})
	end)

	if not ok then
		return {
			accepted = false,
			reason = "admission_enqueue_failed",
		}
	end

	return finalizeAdmissionResult(result)
end

local function requestAdmissionViaPartyMatchmakingService(
	userId: number,
	handoffToken: string,
	targetRealmId: string
): any
	local admissionApi = getPartyMatchmakingAdmissionQueryApi()
	if type(admissionApi) ~= "table" then
		return {
			accepted = false,
			reason = "admission_queue_unavailable",
		}
	end

	local ok, result = pcall(function()
		return (admissionApi :: any).RequestPartyMatchAdmission({
			operationId = handoffToken,
			partyId = string.format("handoff_party:%d:%s", userId, handoffToken),
			targetRealmId = targetRealmId,
			partyMemberUserIds = { userId },
		})
	end)

	if not ok then
		return {
			accepted = false,
			reason = "admission_enqueue_failed",
		}
	end

	return finalizeAdmissionResult(result)
end

local function requestAdmissionHandoff(userId: number, handoffToken: string, targetRealmId: string): any
	admissionIngressDiagnostics.totalAttempts += 1
	admissionIngressDiagnostics.primaryAttempts += 1
	admissionIngressDiagnostics.lastPath = "primary_profile_teleport"

	local primaryResult = requestAdmissionViaProfileTeleportService(userId, handoffToken, targetRealmId)
	if primaryResult.accepted == true then
		admissionIngressDiagnostics.primarySucceeded += 1
		admissionIngressDiagnostics.lastReason = "accepted"
		admissionIngressDiagnostics.lastPrimaryReason = "accepted"
		return primaryResult
	end

	admissionIngressDiagnostics.primaryFailed += 1
	local primaryReason = if type(primaryResult.reason) == "string" and primaryResult.reason ~= ""
		then primaryResult.reason
		else "admission_enqueue_failed"
	admissionIngressDiagnostics.lastReason = primaryReason
	admissionIngressDiagnostics.lastPrimaryReason = primaryReason

	if primaryReason ~= "admission_queue_unavailable" then
		return primaryResult
	end

	admissionIngressDiagnostics.fallbackAttempts += 1
	admissionIngressDiagnostics.lastPath = "fallback_party_matchmaking"

	local fallbackResult = requestAdmissionViaPartyMatchmakingService(userId, handoffToken, targetRealmId)
	if fallbackResult.accepted == true then
		admissionIngressDiagnostics.fallbackSucceeded += 1
		admissionIngressDiagnostics.lastReason = "accepted"
		admissionIngressDiagnostics.lastFallbackReason = "accepted"
		return fallbackResult
	end

	admissionIngressDiagnostics.fallbackFailed += 1
	local fallbackReason = if type(fallbackResult.reason) == "string" and fallbackResult.reason ~= ""
		then fallbackResult.reason
		else "admission_enqueue_failed"
	admissionIngressDiagnostics.lastReason = fallbackReason
	admissionIngressDiagnostics.lastFallbackReason = fallbackReason
	return fallbackResult
end

local function getLifecycleQueryApi(): any?
	local queryApi = globalEnv._ProfilePersistenceLifecycle_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function isOwnershipReady(userId: number): boolean
	local queryApi = getLifecycleQueryApi()
	if queryApi == nil or type(queryApi.IsPlayerOwnershipReady) ~= "function" then
		return false
	end

	local ok, ready = pcall(function()
		return queryApi.IsPlayerOwnershipReady(userId)
	end)
	if not ok then
		return false
	end

	return ready == true
end

local function notifyReleaseReadyCallbacks(userId: number, result: HandoffResult)
	local callbacks = releaseReadyCallbacksByUserId[userId]
	if callbacks == nil or #callbacks == 0 then
		return
	end

	for _, callback in ipairs(callbacks) do
		pcall(callback, result)
	end
end

local function defaultTeleportContextFromPlayer(player: any): any?
	if type(player) ~= "table" and typeof(player) ~= "Instance" then
		return nil
	end
	if type(player.GetJoinData) ~= "function" then
		return nil
	end

	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return nil
	end

	local teleportData = joinData.TeleportData
	if type(teleportData) ~= "table" then
		return nil
	end

	return teleportData
end

local function resolveTeleportContext(player: any): any?
	if destinationTeleportContextResolver ~= nil then
		local ok, teleportContext = pcall(destinationTeleportContextResolver, player)
		if ok and type(teleportContext) == "table" then
			return teleportContext
		end
	end

	return defaultTeleportContextFromPlayer(player)
end

local function resolveHandoffTokenFromTeleportContext(userId: number, teleportContext: any): string?
	if type(teleportContext) ~= "table" then
		return nil
	end

	local tokensByUserId = teleportContext.handoffTokensByUserId
	if type(tokensByUserId) ~= "table" then
		return nil
	end

	local token = tokensByUserId[userId]
	if isNonEmptyString(token) then
		return token
	end

	return nil
end

local function resolveTargetRealmIdFromTeleportContext(teleportContext: any): string?
	if type(teleportContext) ~= "table" then
		return nil
	end

	if isNonEmptyString(teleportContext.targetRealmId) then
		return teleportContext.targetRealmId
	end

	return nil
end

local function getCapacityQueryApi(): any?
	local queryApi = globalEnv._ActiveRealmCapacity_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	if type((queryApi :: any).CommitTinyfolkArrival) ~= "function" then
		return nil
	end

	return queryApi
end

local function tryCommitCapacityArrival(targetRealmId: string?)
	if not isNonEmptyString(targetRealmId) then
		destinationOrchestrationDiagnostics.capacitySkipped += 1
		return
	end

	local capacityApi = getCapacityQueryApi()
	if capacityApi == nil then
		destinationOrchestrationDiagnostics.capacitySkipped += 1
		return
	end

	local ok, result = pcall(function()
		return (capacityApi :: any).CommitTinyfolkArrival(targetRealmId, 1, os.time())
	end)
	if not ok or type(result) ~= "table" or result.accepted ~= true then
		destinationOrchestrationDiagnostics.capacitySkipped += 1
		return
	end

	destinationOrchestrationDiagnostics.capacityCommitted += 1
end

local function clearDestinationAwaitingOwnership(userId: number)
	destinationAwaitingOwnershipByUserId[userId] = nil
end

local function attemptDestinationConfirmation(
	userId: number,
	handoffToken: string?,
	targetRealmId: string?
): HandoffResult
	local confirmResult = ProfileTeleportHandoffService.ConfirmDestinationOwnership(userId, handoffToken)
	if confirmResult.ok == true then
		destinationOrchestrationDiagnostics.confirmed += 1
		destinationOrchestrationDiagnostics.lastReason = "confirmed"
		clearDestinationAwaitingOwnership(userId)
		tryCommitCapacityArrival(targetRealmId)
		return confirmResult
	end

	if confirmResult.reason == "ownership_not_ready" and confirmResult.retryable == true then
		destinationOrchestrationDiagnostics.awaitingOwnership += 1
		destinationOrchestrationDiagnostics.lastReason = "ownership_not_ready"
		destinationAwaitingOwnershipByUserId[userId] = true
		return confirmResult
	end

	destinationOrchestrationDiagnostics.confirmFailed += 1
	destinationOrchestrationDiagnostics.lastReason = if type(confirmResult.reason) == "string"
		then confirmResult.reason
		else "confirm_failed"
	clearDestinationAwaitingOwnership(userId)
	return confirmResult
end

local function orchestrateDestinationArrivalForPlayer(player: any): HandoffResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeResult(false, "OrchestrateDestinationArrival", "invalid_player_user_id", false, nil, "safe_fallback")
	end

	destinationOrchestrationDiagnostics.totalAttempts += 1

	local teleportContext = resolveTeleportContext(player)
	local teleportHandoffToken = resolveHandoffTokenFromTeleportContext(userId, teleportContext)
	local teleportTargetRealmId = resolveTargetRealmIdFromTeleportContext(teleportContext)

	ProfileTeleportHandoffService.RestorePendingHandoffFromProfile(player)

	local pending = pendingHandoffByUserId[userId]
	local pendingToken: string? = nil
	local pendingTargetRealmId: string? = nil
	if pending ~= nil then
		pendingToken = pending.handoffToken
		pendingTargetRealmId = pending.targetRealmId
	end

	if pendingToken == nil and teleportHandoffToken == nil then
		destinationOrchestrationDiagnostics.noTransferSkipped += 1
		destinationOrchestrationDiagnostics.lastReason = "no_transfer_context"
		return makeResult(true, "OrchestrateDestinationArrival", "no_transfer_context", false, nil, nil)
	end

	local handoffToken = if teleportHandoffToken ~= nil then teleportHandoffToken else pendingToken
	local targetRealmId = if teleportTargetRealmId ~= nil then teleportTargetRealmId else pendingTargetRealmId

	return attemptDestinationConfirmation(userId, handoffToken, targetRealmId)
end

local function registerDestinationOwnershipCallback(userId: number, player: any)
	local queryApi = getLifecycleQueryApi()
	if queryApi == nil or type(queryApi.RegisterOwnershipReadyCallback) ~= "function" then
		return
	end

	queryApi.RegisterOwnershipReadyCallback(userId, function(ready: boolean, _failureReason: string?)
		if ready ~= true then
			return
		end
		if destinationAwaitingOwnershipByUserId[userId] ~= true then
			return
		end
		if getPlayerUserId(player) ~= userId then
			return
		end

		orchestrateDestinationArrivalForPlayer(player)
	end)
end

function ProfileTeleportHandoffService.ResetForTests()
	pendingHandoffByUserId = {}
	releaseReadyCallbacksByUserId = {}
	destinationOrchestrationStarted = false
	destinationAwaitingOwnershipByUserId = {}
	destinationTeleportContextResolver = nil
	admissionIngressDiagnostics = {
		totalAttempts = 0,
		primaryAttempts = 0,
		primarySucceeded = 0,
		primaryFailed = 0,
		fallbackAttempts = 0,
		fallbackSucceeded = 0,
		fallbackFailed = 0,
		lastPath = "none",
		lastReason = "none",
		lastPrimaryReason = "none",
		lastFallbackReason = "none",
	}
	destinationOrchestrationDiagnostics = {
		totalAttempts = 0,
		confirmed = 0,
		awaitingOwnership = 0,
		noTransferSkipped = 0,
		confirmFailed = 0,
		capacityCommitted = 0,
		capacitySkipped = 0,
		lastReason = "not_started",
	}
end

function ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics(): AdmissionIngressDiagnostics
	return cloneAdmissionIngressDiagnostics()
end

function ProfileTeleportHandoffService.RegisterReleaseReadyCallback(userId: any, callback: any): boolean
	if not isValidUserId(userId) then
		return false
	end
	if type(callback) ~= "function" then
		return false
	end

	local callbacks = releaseReadyCallbacksByUserId[userId]
	if callbacks == nil then
		callbacks = {}
		releaseReadyCallbacksByUserId[userId] = callbacks
	end
	table.insert(callbacks, callback)

	local pending = pendingHandoffByUserId[userId]
	if pending ~= nil then
		pcall(callback, makeResult(true, "BeginCrossServerHandoff", nil, nil, pending.handoffToken, nil))
	end
	return true
end

function ProfileTeleportHandoffService.BeginCrossServerHandoff(player: any, context: any?): HandoffResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeResult(false, "BeginCrossServerHandoff", "invalid_player_user_id", false, nil, "safe_fallback")
	end

	local contextAny: any = context
	local targetRealmId = if type(contextAny) == "table" then contextAny.targetRealmId else nil
	if not isNonEmptyString(targetRealmId) then
		return makeResult(false, "BeginCrossServerHandoff", "target_realm_id_invalid", false, nil, "safe_fallback")
	end

	local handoffBegun, handoffReason, handoffToken = beginControlledTransferHandoff(userId, targetRealmId, contextAny)
	if not handoffBegun or not isNonEmptyString(handoffToken) then
		return makeResult(
			false,
			"BeginCrossServerHandoff",
			handoffReason or "handoff_begin_failed",
			handoffReason == "transfer_lock_active",
			nil,
			"safe_fallback"
		)
	end

	local enqueueResult = requestAdmissionHandoff(userId, handoffToken, targetRealmId)
	if enqueueResult.accepted ~= true then
		abortControlledTransferHandoff(userId, handoffToken, targetRealmId)
		return makeResult(
			false,
			"BeginCrossServerHandoff",
			enqueueResult.reason,
			isRetryableEnqueueReason(enqueueResult.reason),
			nil,
			"safe_fallback"
		)
	end

	local startedAt = os.time()
	local persisted, persistReason = persistPendingRecovery(player, handoffToken, targetRealmId, startedAt)
	if not persisted then
		return makeResult(
			false,
			"BeginCrossServerHandoff",
			persistReason or "pending_recovery_persist_failed",
			false,
			nil,
			"safe_fallback"
		)
	end

	local releaseResult = ProfilePersistenceGateway.ReleasePlayerProfile(player)
	if not releaseResult.ok then
		return makeResult(
			false,
			"BeginCrossServerHandoff",
			"release_before_transfer_failed",
			releaseResult.retryable == true,
			nil,
			"safe_fallback"
		)
	end

	pendingHandoffByUserId[userId] = {
		handoffToken = handoffToken,
		targetRealmId = targetRealmId,
	}

	local result = makeResult(true, "BeginCrossServerHandoff", nil, nil, handoffToken, nil)
	notifyReleaseReadyCallbacks(userId, result)
	return result
end

function ProfileTeleportHandoffService.RestorePendingHandoffFromProfile(player: any): boolean
	local userId = getPlayerUserId(player)
	if userId == nil then
		return false
	end

	return tryRestorePendingHandoffFromProfile(userId)
end

function ProfileTeleportHandoffService.ConfirmDestinationOwnership(userId: any, handoffToken: any?): HandoffResult
	if not isValidUserId(userId) then
		return makeResult(false, "ConfirmDestinationOwnership", "invalid_user_id", false, nil, "safe_fallback")
	end

	tryRestorePendingHandoffFromProfile(userId)

	local pending = pendingHandoffByUserId[userId]
	local pendingToken: string? = nil
	if pending ~= nil then
		pendingToken = pending.handoffToken
	end

	if pendingToken ~= nil and handoffToken ~= nil and pendingToken ~= handoffToken then
		return makeResult(false, "ConfirmDestinationOwnership", "handoff_token_mismatch", false, nil, "safe_fallback")
	end

	if pendingToken == nil and type(handoffToken) ~= "string" then
		return makeResult(false, "ConfirmDestinationOwnership", "handoff_not_pending", false, nil, "safe_fallback")
	end

	if not isOwnershipReady(userId) then
		return makeResult(
			false,
			"ConfirmDestinationOwnership",
			"ownership_not_ready",
			true,
			if pendingToken ~= nil then pendingToken else handoffToken,
			nil
		)
	end

	local resolvedTargetRealmId = if pending ~= nil and isNonEmptyString(pending.targetRealmId)
		then pending.targetRealmId
		else nil
	local resolvedHandoffToken = if pendingToken ~= nil then pendingToken else handoffToken
	local consumedHandoffEntry: any? = nil
	if isNonEmptyString(resolvedHandoffToken) and isNonEmptyString(resolvedTargetRealmId) then
		local consumed, consumeReason, handoffEntry =
			consumeControlledTransferHandoff(userId, resolvedHandoffToken :: string, resolvedTargetRealmId)
		consumedHandoffEntry = handoffEntry
		if not consumed then
			local retryable = consumeReason == "handoff_token_expired"
			return makeResult(
				false,
				"ConfirmDestinationOwnership",
				consumeReason or "handoff_consume_failed",
				retryable,
				resolvedHandoffToken,
				"safe_fallback"
			)
		end
	end

	recordTradeRewardsFromHandoff(consumedHandoffEntry)

	clearPendingHandoff(userId)
	return makeResult(
		true,
		"ConfirmDestinationOwnership",
		nil,
		nil,
		if pendingToken ~= nil then pendingToken else handoffToken,
		nil
	)
end

function ProfileTeleportHandoffService.CanSpawnGameplayForUserId(userId: any): boolean
	if not isValidUserId(userId) then
		return false
	end

	tryRestorePendingHandoffFromProfile(userId)

	local pending = pendingHandoffByUserId[userId]
	if pending == nil then
		return true
	end

	if isOwnershipReady(userId) then
		clearPendingHandoff(userId)
		return true
	end

	return false
end

function ProfileTeleportHandoffService.OrchestrateDestinationArrival(player: any): HandoffResult
	return orchestrateDestinationArrivalForPlayer(player)
end

function ProfileTeleportHandoffService.GetDestinationOrchestrationDiagnostics(): DestinationOrchestrationDiagnostics
	return cloneDestinationOrchestrationDiagnostics()
end

function ProfileTeleportHandoffService.StartDestinationOrchestration(config: any?): { ok: boolean, reason: string? }
	if destinationOrchestrationStarted then
		return {
			ok = true,
			reason = "already_started",
		}
	end

	local configAny: any = config
	if type(configAny) == "table" and type(configAny.teleportContextResolver) == "function" then
		destinationTeleportContextResolver = configAny.teleportContextResolver
	end

	local playersService = if type(configAny) == "table" then configAny.players else nil
	if playersService == nil and game ~= nil and type(game.GetService) == "function" then
		local ok, resolvedPlayers = pcall(function()
			return game:GetService("Players")
		end)
		if ok then
			playersService = resolvedPlayers
		end
	end

	if
		type(playersService) ~= "table"
		or type(playersService.PlayerAdded) ~= "table"
		or type(playersService.PlayerAdded.Connect) ~= "function"
		or type(playersService.PlayerRemoving) ~= "table"
		or type(playersService.PlayerRemoving.Connect) ~= "function"
		or type(playersService.GetPlayers) ~= "function"
	then
		return {
			ok = false,
			reason = "players_service_missing",
		}
	end

	local function onPlayerAdded(player: any)
		local userId = getPlayerUserId(player)
		if userId == nil then
			return
		end

		local result = orchestrateDestinationArrivalForPlayer(player)
		if result.ok ~= true and result.reason == "ownership_not_ready" then
			registerDestinationOwnershipCallback(userId, player)
		end
	end

	playersService.PlayerAdded:Connect(onPlayerAdded)
	playersService.PlayerRemoving:Connect(function(player: any)
		local userId = getPlayerUserId(player)
		if userId == nil then
			return
		end

		clearDestinationAwaitingOwnership(userId)

		local pending = pendingHandoffByUserId[userId]
		if pending ~= nil and isNonEmptyString(pending.handoffToken) and isNonEmptyString(pending.targetRealmId) then
			abortControlledTransferHandoff(userId, pending.handoffToken, pending.targetRealmId)
			local assignmentApi = getRealmTransferAssignmentQueryApi()
			if assignmentApi ~= nil and type(assignmentApi.ApplyTransition) == "function" then
				pcall(assignmentApi.ApplyTransition, userId, {
					operation = RealmTransferState.Operations.AbortToHub,
					now = os.time(),
				})
			end
			pendingHandoffByUserId[userId] = nil
			releaseReadyCallbacksByUserId[userId] = nil
		end
	end)

	for _, player in playersService:GetPlayers() do
		onPlayerAdded(player)
	end

	destinationOrchestrationStarted = true
	destinationOrchestrationDiagnostics.lastReason = "started"
	return {
		ok = true,
		reason = nil,
	}
end

globalEnv._ProfileTeleportHandoffService_QueryAPI = {
	BeginCrossServerHandoff = function(player: any, context: any?): HandoffResult
		return ProfileTeleportHandoffService.BeginCrossServerHandoff(player, context)
	end,
	ConfirmDestinationOwnership = function(userId: any, handoffToken: any?): HandoffResult
		return ProfileTeleportHandoffService.ConfirmDestinationOwnership(userId, handoffToken)
	end,
	CanSpawnGameplayForUserId = function(userId: any): boolean
		return ProfileTeleportHandoffService.CanSpawnGameplayForUserId(userId)
	end,
	RestorePendingHandoffFromProfile = function(player: any): boolean
		return ProfileTeleportHandoffService.RestorePendingHandoffFromProfile(player)
	end,
	RegisterReleaseReadyCallback = function(userId: any, callback: any): boolean
		return ProfileTeleportHandoffService.RegisterReleaseReadyCallback(userId, callback)
	end,
	GetAdmissionIngressDiagnostics = function(): AdmissionIngressDiagnostics
		return ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics()
	end,
	OrchestrateDestinationArrival = function(player: any): HandoffResult
		return ProfileTeleportHandoffService.OrchestrateDestinationArrival(player)
	end,
	GetDestinationOrchestrationDiagnostics = function(): DestinationOrchestrationDiagnostics
		return ProfileTeleportHandoffService.GetDestinationOrchestrationDiagnostics()
	end,
	StartDestinationOrchestration = function(config: any?): { ok: boolean, reason: string? }
		return ProfileTeleportHandoffService.StartDestinationOrchestration(config)
	end,
	ResetForTests = function()
		ProfileTeleportHandoffService.ResetForTests()
	end,
}

return ProfileTeleportHandoffService
