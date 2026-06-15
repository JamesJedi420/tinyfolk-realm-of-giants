--!strict

local LiveRealmRegistryService: any = {}

local STRUCTURE_ID = "liveRealmRegistry"
local DEFAULT_LIST_LIMIT = 50
local HEARTBEAT_INTERVAL_SECONDS = 45

local runtimeStore: any = nil
local runtimeRegistryState: any = nil
local runtimeStructurePolicy: any = nil
local runtimeQueueNotificationFanout: any = nil
local runtimeConfig: any = nil
local runtimeHeartbeatOwnerUserId: number? = nil
local runtimeHeartbeatToken: any = nil
local runtimePolicyTtlSeconds = 120

local diagnostics = {
	publishAttempts = 0,
	publishSucceeded = 0,
	publishFailed = 0,
	refreshAttempts = 0,
	refreshSucceeded = 0,
	refreshFailed = 0,
	pruneAttempts = 0,
	pruneSucceeded = 0,
	pruneFailed = 0,
	notificationAttempts = 0,
	notificationSucceeded = 0,
	notificationFailed = 0,
	lastReason = "not_started",
	lastRealmId = nil :: string?,
}

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneTable(child)
	end
	return copy
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local function getGlobalTable(name: string): any?
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function resolveNow(): number
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.now) == "function" then
		local nowValue = configAny.now()
		if type(nowValue) == "number" and nowValue == nowValue then
			return nowValue
		end
	end
	return os.clock()
end

local function resolvePolicyTtl(): number
	if type(runtimeStructurePolicy) ~= "table" then
		return runtimePolicyTtlSeconds
	end
	local ttl = runtimeStructurePolicy.ResolveExpiration(STRUCTURE_ID)
	if ttl.ok == true and type(ttl.ttlSeconds) == "number" then
		return ttl.ttlSeconds
	end
	return runtimePolicyTtlSeconds
end

local function resolveRuntimeJobId(): string
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.jobId) == "string" then
		return configAny.jobId
	end
	if game ~= nil then
		local ok, jobId = pcall(function()
			return (game :: any).JobId
		end)
		if ok and type(jobId) == "string" then
			return jobId
		end
	end
	return ""
end

local function resolveRuntimePrivateServerId(): string
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.privateServerId) == "string" then
		return configAny.privateServerId
	end
	if game ~= nil then
		local ok, privateServerId = pcall(function()
			return (game :: any).PrivateServerId
		end)
		if ok and type(privateServerId) == "string" then
			return privateServerId
		end
	end
	return ""
end

local function resolveAllocationBackedPrivateServerId(ownerUserId: number): string
	local runtimeId = resolveRuntimePrivateServerId()
	if runtimeRegistryState ~= nil then
		local stableFallback = runtimeRegistryState.ResolveStablePrivateServerId(ownerUserId, nil)
		if runtimeId ~= "" and runtimeId ~= stableFallback then
			return runtimeId
		end
	else
		if runtimeId ~= "" then
			return runtimeId
		end
	end

	local allocationApi = getGlobalTable("_RealmReservedServerAllocationService_QueryAPI")
	if type(allocationApi) == "table" and type((allocationApi :: any).ResolveAccessCodeForRealm) == "function" then
		local realmId = if runtimeRegistryState ~= nil
			then runtimeRegistryState.FormatRealmId(ownerUserId)
			else string.format("giant_realm_%d", ownerUserId)
		local ok, result = pcall(function()
			return (allocationApi :: any).ResolveAccessCodeForRealm(realmId)
		end)
		if ok and type(result) == "table" and result.accepted == true and type(result.accessCode) == "string" then
			return result.accessCode
		end
	end

	return runtimeId
end

local function resolvePlayerCount(): number
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.getPlayerCount) == "function" then
		local count = configAny.getPlayerCount()
		if type(count) == "number" and count >= 0 and count % 1 == 0 then
			return count
		end
	end
	return 0
end

local function resolveCapacity(realmId: string): number
	local capacityApi = getGlobalTable("_ActiveRealmCapacity_QueryAPI")
	if type(capacityApi) == "table" and type(capacityApi.GetCapacitySnapshot) == "function" then
		local ok, result = pcall(capacityApi.GetCapacitySnapshot, realmId)
		if ok and type(result) == "table" and result.accepted == true and type(result.snapshot) == "table" then
			local maxTinyfolk = result.snapshot.maxTinyfolk
			if type(maxTinyfolk) == "number" and maxTinyfolk > 0 then
				return maxTinyfolk
			end
		end
	end
	if type(runtimeRegistryState) == "table" and type(runtimeRegistryState.DEFAULT_CAPACITY) == "number" then
		return runtimeRegistryState.DEFAULT_CAPACITY
	end
	return 8
end

local function recordDiagnostic(kind: string, accepted: boolean, reason: string, realmId: string?)
	if kind == "publish" then
		diagnostics.publishAttempts += 1
		if accepted then
			diagnostics.publishSucceeded += 1
		else
			diagnostics.publishFailed += 1
		end
	elseif kind == "refresh" then
		diagnostics.refreshAttempts += 1
		if accepted then
			diagnostics.refreshSucceeded += 1
		else
			diagnostics.refreshFailed += 1
		end
	elseif kind == "prune" then
		diagnostics.pruneAttempts += 1
		if accepted then
			diagnostics.pruneSucceeded += 1
		else
			diagnostics.pruneFailed += 1
		end
	elseif kind == "notification" then
		diagnostics.notificationAttempts += 1
		if accepted then
			diagnostics.notificationSucceeded += 1
		else
			diagnostics.notificationFailed += 1
		end
	end
	diagnostics.lastReason = reason
	diagnostics.lastRealmId = realmId
end

local function publishRealmStatusNotification(realmId: string, lifecycle: string, operationSuffix: string)
	local fanout = runtimeQueueNotificationFanout
	if fanout == nil then
		fanout = getGlobalTable("_QueueNotificationFanout_QueryAPI")
	end
	if type(fanout) ~= "table" or type(fanout.PublishRealmStatus) ~= "function" then
		recordDiagnostic("notification", false, "fanout_unavailable", realmId)
		return
	end

	local now = resolveNow()
	local operationId = string.format("realm_status_%s_%s_%d", realmId, operationSuffix, math.floor(now * 1000))
	local ok, result = pcall(function()
		return fanout.PublishRealmStatus("realm_status_changed", {
			realmId = realmId,
			lifecycle = lifecycle,
			operationId = operationId,
		})
	end)
	if not ok or type(result) ~= "table" or result.accepted ~= true then
		local reason = if type(result) == "table" and type(result.reason) == "string"
			then result.reason
			else "notification_publish_failed"
		recordDiagnostic("notification", false, reason, realmId)
		return
	end
	recordDiagnostic("notification", true, "accepted", realmId)
end

local function stopHeartbeat()
	runtimeHeartbeatOwnerUserId = nil
	runtimeHeartbeatToken = nil
end

local function refreshTrackedRealm(ownerUserId: number): any
	if runtimeStore == nil or runtimeRegistryState == nil then
		recordDiagnostic("refresh", false, "store_unavailable", nil)
		return {
			accepted = false,
			reason = "store_unavailable",
			snapshot = nil,
		}
	end

	local now = resolveNow()
	local realmId = runtimeRegistryState.FormatRealmId(ownerUserId)
	local patch = {
		privateServerId = runtimeRegistryState.ResolveStablePrivateServerId(
			ownerUserId,
			resolveAllocationBackedPrivateServerId(ownerUserId)
		),
		jobId = resolveRuntimeJobId(),
		accessMode = runtimeRegistryState.ResolveAccessMode(resolveAllocationBackedPrivateServerId(ownerUserId)),
		playerCount = resolvePlayerCount(),
		capacity = resolveCapacity(realmId),
		lifecycle = runtimeRegistryState.Lifecycle.Active,
	}
	local result = runtimeStore.RefreshRegistryEntry(realmId, patch, now)
	recordDiagnostic(
		"refresh",
		result.accepted == true,
		if type(result.reason) == "string" then result.reason else "refresh_failed",
		realmId
	)
	return result
end

local function scheduleHeartbeat(ownerUserId: number)
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and configAny.enableHeartbeat == false then
		return
	end

	runtimeHeartbeatOwnerUserId = ownerUserId
	local token = {}
	runtimeHeartbeatToken = token

	local scheduler = if type(configAny) == "table" then configAny.scheduler else nil
	if type(scheduler) == "table" and type(scheduler.schedule) == "function" then
		local function tick()
			if runtimeHeartbeatToken ~= token or runtimeHeartbeatOwnerUserId ~= ownerUserId then
				return
			end
			refreshTrackedRealm(ownerUserId)
			if runtimeHeartbeatToken == token and runtimeHeartbeatOwnerUserId == ownerUserId then
				pcall(function()
					scheduler.schedule(HEARTBEAT_INTERVAL_SECONDS, tick)
				end)
			end
		end
		pcall(function()
			scheduler.schedule(HEARTBEAT_INTERVAL_SECONDS, tick)
		end)
		return
	end

	task.spawn(function()
		while runtimeHeartbeatToken == token and runtimeHeartbeatOwnerUserId == ownerUserId do
			task.wait(HEARTBEAT_INTERVAL_SECONDS)
			if runtimeHeartbeatToken ~= token or runtimeHeartbeatOwnerUserId ~= ownerUserId then
				break
			end
			refreshTrackedRealm(ownerUserId)
		end
	end)
end

function LiveRealmRegistryService.GetDiagnostics(): any
	return cloneTable(diagnostics)
end

function LiveRealmRegistryService.PublishActiveRealm(input: any): any
	if runtimeStore == nil or runtimeRegistryState == nil then
		recordDiagnostic("publish", false, "store_unavailable", nil)
		return {
			accepted = false,
			reason = "store_unavailable",
			snapshot = nil,
		}
	end
	if type(input) ~= "table" or not isPositiveInteger(input.ownerUserId) then
		recordDiagnostic("publish", false, "owner_user_id_invalid", nil)
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
			snapshot = nil,
		}
	end

	local ownerUserId = math.floor(input.ownerUserId)
	local now = resolveNow()
	local realmId = runtimeRegistryState.FormatRealmId(ownerUserId)
	local publishInput, buildReason = runtimeRegistryState.BuildPublishInput({
		ownerUserId = ownerUserId,
		now = now,
		privateServerId = resolveAllocationBackedPrivateServerId(ownerUserId),
		jobId = resolveRuntimeJobId(),
		playerCount = resolvePlayerCount(),
		capacity = resolveCapacity(realmId),
		dangerRating = input.dangerRating,
		lifecycle = runtimeRegistryState.Lifecycle.Starting,
	})
	if publishInput == nil then
		recordDiagnostic("publish", false, buildReason or "publish_input_invalid", realmId)
		return {
			accepted = false,
			reason = buildReason or "publish_input_invalid",
			snapshot = nil,
		}
	end

	local startingResult = runtimeStore.PublishRegistryEntry(publishInput)
	if startingResult.accepted ~= true then
		recordDiagnostic(
			"publish",
			false,
			if type(startingResult.reason) == "string" then startingResult.reason else "publish_failed",
			realmId
		)
		return startingResult
	end

	publishRealmStatusNotification(realmId, runtimeRegistryState.Lifecycle.Starting, "starting")

	local activeResult = runtimeStore.RefreshRegistryEntry(realmId, {
		lifecycle = runtimeRegistryState.Lifecycle.Active,
		playerCount = resolvePlayerCount(),
		capacity = resolveCapacity(realmId),
		jobId = resolveRuntimeJobId(),
	}, now)
	if activeResult.accepted ~= true then
		recordDiagnostic(
			"publish",
			false,
			if type(activeResult.reason) == "string" then activeResult.reason else "activate_failed",
			realmId
		)
		return activeResult
	end

	recordDiagnostic("publish", true, "accepted", realmId)
	publishRealmStatusNotification(realmId, runtimeRegistryState.Lifecycle.Active, "active")
	scheduleHeartbeat(ownerUserId)
	return activeResult
end

function LiveRealmRegistryService.RefreshActiveRealm(input: any): any
	if type(input) ~= "table" or not isPositiveInteger(input.ownerUserId) then
		recordDiagnostic("refresh", false, "owner_user_id_invalid", nil)
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
			snapshot = nil,
		}
	end
	return refreshTrackedRealm(math.floor(input.ownerUserId))
end

function LiveRealmRegistryService.PruneActiveRealm(input: any): any
	if runtimeStore == nil or runtimeRegistryState == nil then
		recordDiagnostic("prune", false, "store_unavailable", nil)
		return {
			accepted = false,
			reason = "store_unavailable",
			snapshot = nil,
		}
	end
	if type(input) ~= "table" or not isPositiveInteger(input.ownerUserId) then
		recordDiagnostic("prune", false, "owner_user_id_invalid", nil)
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
			snapshot = nil,
		}
	end

	stopHeartbeat()
	local ownerUserId = math.floor(input.ownerUserId)
	local realmId = runtimeRegistryState.FormatRealmId(ownerUserId)
	local now = resolveNow()
	local pruneResult = runtimeStore.PruneRegistryEntry(realmId, now)
	if pruneResult.accepted == true then
		runtimeStore.RemoveRegistryEntry(realmId)
	end
	recordDiagnostic(
		"prune",
		pruneResult.accepted == true,
		if type(pruneResult.reason) == "string" then pruneResult.reason else "prune_failed",
		realmId
	)
	publishRealmStatusNotification(realmId, runtimeRegistryState.Lifecycle.Expired, "expired")
	return pruneResult
end

function LiveRealmRegistryService.GetRegistrySnapshot(realmId: any): any
	if runtimeStore == nil then
		return {
			accepted = false,
			reason = "store_unavailable",
			snapshot = nil,
		}
	end
	return runtimeStore.GetRegistrySnapshot(realmId)
end

function LiveRealmRegistryService.ListLiveRegistryEntries(limit: any, exclusiveStartKey: any?): any
	if runtimeStore == nil then
		return {
			accepted = false,
			reason = "store_unavailable",
			entries = {},
		}
	end
	local resolvedLimit = if isPositiveInteger(limit) then limit else DEFAULT_LIST_LIMIT
	return runtimeStore.ListRegistryEntries(resolvedLimit, exclusiveStartKey)
end

function LiveRealmRegistryService.ListLiveRealmAvailability(limit: any, at: any?): { any }
	if runtimeRegistryState == nil then
		return {}
	end
	local resolvedLimit = if isPositiveInteger(limit) then limit else DEFAULT_LIST_LIMIT
	local now = if type(at) == "number" and at == at then at else resolveNow()
	local ttlSeconds = resolvePolicyTtl()
	local listResult = LiveRealmRegistryService.ListLiveRegistryEntries(resolvedLimit, nil)
	local entries = if type(listResult) == "table" and type(listResult.entries) == "table"
		then listResult.entries
		else {}

	local availability = {}
	for _, entry in ipairs(entries) do
		local snapshot = runtimeRegistryState.BuildAvailabilitySnapshot(entry, now, ttlSeconds)
		if snapshot ~= nil then
			table.insert(availability, snapshot)
		end
	end
	table.sort(availability, function(left: any, right: any): boolean
		if left.dangerRating ~= right.dangerRating then
			return left.dangerRating > right.dangerRating
		end
		return left.realmId < right.realmId
	end)
	return availability
end

function LiveRealmRegistryService.ConfigureForTests(config: any): { ok: boolean, reason: string? }
	return LiveRealmRegistryService.Start(config)
end

function LiveRealmRegistryService.ResetForTests()
	stopHeartbeat()
	runtimeStore = nil
	runtimeRegistryState = nil
	runtimeStructurePolicy = nil
	runtimeQueueNotificationFanout = nil
	runtimeConfig = nil
	runtimePolicyTtlSeconds = 120
	diagnostics.lastReason = "reset"
	diagnostics.lastRealmId = nil
end

function LiveRealmRegistryService.Start(config: any?): { ok: boolean, reason: string? }
	stopHeartbeat()
	runtimeConfig = if type(config) == "table" then config else {}

	local configAny: any = runtimeConfig
	runtimeRegistryState = configAny.registryState
	runtimeStructurePolicy = configAny.structurePolicy
	runtimeQueueNotificationFanout = configAny.queueNotificationFanout

	if runtimeRegistryState == nil then
		return {
			ok = false,
			reason = "registry_state_unavailable",
		}
	end
	if runtimeStructurePolicy == nil then
		return {
			ok = false,
			reason = "structure_policy_unavailable",
		}
	end

	local storeModule = configAny.storeModule
	if type(storeModule) ~= "table" or type(storeModule.Create) ~= "function" then
		return {
			ok = false,
			reason = "store_module_unavailable",
		}
	end

	runtimePolicyTtlSeconds = resolvePolicyTtl()
	runtimeStore = storeModule.Create({
		adapter = configAny.adapter,
		registryState = runtimeRegistryState,
		structurePolicy = runtimeStructurePolicy,
	})

	if type(configAny.queueNotificationFanout) ~= "table" then
		runtimeQueueNotificationFanout = getGlobalTable("_QueueNotificationFanout_QueryAPI")
	end

	diagnostics.lastReason = "started"
	return {
		ok = true,
		reason = "accepted",
	}
end

return LiveRealmRegistryService
