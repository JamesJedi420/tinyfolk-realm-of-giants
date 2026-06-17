--!strict

local MemoryStoreObservabilityService: any = {}
local globalEnv: any = getfenv()

local DEFAULT_RESCUE_LIMIT = 200

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

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local cloned = {}
	for key, child in pairs(value) do
		cloned[key] = cloneTable(child)
	end
	return cloned
end

local function nowSeconds(): number
	return os.clock()
end

local function readAdmissionDiagnostics(): (any, string)
	local api = getGlobalTable("_RealmAdmissionQueue_QueryAPI")
	if type(api) ~= "table" or type((api :: any).GetProcessingDiagnostics) ~= "function" then
		return nil, "admission_queue_api_unavailable"
	end

	local ok, diagnostics = pcall(function()
		return (api :: any).GetProcessingDiagnostics()
	end)
	if not ok or type(diagnostics) ~= "table" then
		return nil, "admission_queue_diagnostics_unavailable"
	end

	return diagnostics, "accepted"
end

local function readRescuePendingCount(): (number, string)
	local api = getGlobalTable("_RescueContractHubSurface_QueryAPI")
	if type(api) ~= "table" or type((api :: any).GetPendingRescueQueueEntries) ~= "function" then
		return 0, "rescue_queue_api_unavailable"
	end

	local ok, entries = pcall(function()
		return (api :: any).GetPendingRescueQueueEntries(DEFAULT_RESCUE_LIMIT, nowSeconds())
	end)
	if not ok or type(entries) ~= "table" then
		return 0, "rescue_queue_unavailable"
	end

	return #entries, "accepted"
end

local function readLiveRealmDiagnostics(): (any, string)
	local api = getGlobalTable("_LiveRealmRegistry_QueryAPI")
	if type(api) ~= "table" or type((api :: any).GetDiagnostics) ~= "function" then
		return nil, "live_registry_api_unavailable"
	end

	local ok, diagnostics = pcall(function()
		return (api :: any).GetDiagnostics()
	end)
	if not ok or type(diagnostics) ~= "table" then
		return nil, "live_registry_diagnostics_unavailable"
	end

	return diagnostics, "accepted"
end

local function readLiveRealmCount(): (number, string)
	local api = getGlobalTable("_LiveRealmRegistryHubSurface_QueryAPI")
	if type(api) ~= "table" or type((api :: any).ListLiveRealmAvailability) ~= "function" then
		return 0, "live_realm_hub_api_unavailable"
	end

	local ok, availability = pcall(function()
		return (api :: any).ListLiveRealmAvailability(DEFAULT_RESCUE_LIMIT, nowSeconds())
	end)
	if not ok or type(availability) ~= "table" then
		return 0, "live_realm_availability_unavailable"
	end

	return #availability, "accepted"
end

local function readTransferLockDiagnostics(): (any, string)
	local api = getGlobalTable("_TransferLock_QueryAPI")
	if type(api) ~= "table" or type((api :: any).GetDiagnostics) ~= "function" then
		return nil, "transfer_lock_api_unavailable"
	end

	local ok, diagnostics = pcall(function()
		return (api :: any).GetDiagnostics()
	end)
	if not ok or type(diagnostics) ~= "table" then
		return nil, "transfer_lock_diagnostics_unavailable"
	end

	return diagnostics, "accepted"
end

local function readIngressDiagnostics(
	globalName: string,
	accessorName: string,
	unavailableReason: string,
	failedReason: string
)
	local api = getGlobalTable(globalName)
	if type(api) ~= "table" or type((api :: any)[accessorName]) ~= "function" then
		return nil, unavailableReason
	end

	local ok, diagnostics = pcall(function()
		return (api :: any)[accessorName]()
	end)
	if not ok or type(diagnostics) ~= "table" then
		return nil, failedReason
	end

	return diagnostics, "accepted"
end

function MemoryStoreObservabilityService.GetSnapshot(_input: any?): any
	local admissionDiagnostics, admissionReason = readAdmissionDiagnostics()
	local rescuePendingCount, rescueReason = readRescuePendingCount()
	local liveRegistryDiagnostics, liveRegistryReason = readLiveRealmDiagnostics()
	local activeRealmCount, activeRealmReason = readLiveRealmCount()
	local transferLockDiagnostics, transferLockReason = readTransferLockDiagnostics()
	local rescueIngressDiagnostics, rescueIngressReason = readIngressDiagnostics(
		"_RescueContractService_QueryAPI",
		"GetAdmissionIngressDiagnostics",
		"rescue_ingress_api_unavailable",
		"rescue_ingress_diagnostics_unavailable"
	)
	local profileTeleportIngressDiagnostics, profileTeleportIngressReason = readIngressDiagnostics(
		"_ProfileTeleportHandoffService_QueryAPI",
		"GetAdmissionIngressDiagnostics",
		"profile_teleport_ingress_api_unavailable",
		"profile_teleport_ingress_diagnostics_unavailable"
	)

	local reasons = {
		admission = admissionReason,
		rescueQueue = rescueReason,
		liveRegistry = liveRegistryReason,
		activeRealm = activeRealmReason,
		transferLock = transferLockReason,
		rescueIngress = rescueIngressReason,
		profileTeleportIngress = profileTeleportIngressReason,
	}

	local accepted = true
	for _, reason in pairs(reasons) do
		if reason ~= "accepted" then
			accepted = false
			break
		end
	end

	local admissionAny: any = admissionDiagnostics
	local liveAny: any = liveRegistryDiagnostics
	local transferAny: any = transferLockDiagnostics

	return {
		accepted = accepted,
		reason = if accepted then "accepted" else "partial_observability_unavailable",
		snapshot = {
			queueDepth = {
				rescuePendingCount = rescuePendingCount,
				admissionLastProcessedCount = if type(admissionAny) == "table"
						and type(admissionAny.totalProcessed) == "number"
					then admissionAny.totalProcessed
					else 0,
			},
			realm = {
				activeRealmCount = activeRealmCount,
				staleRegistryIndicators = {
					refreshFailed = if type(liveAny) == "table" and type(liveAny.refreshFailed) == "number"
						then liveAny.refreshFailed
						else 0,
					pruneFailed = if type(liveAny) == "table" and type(liveAny.pruneFailed) == "number"
						then liveAny.pruneFailed
						else 0,
					lastReason = if type(liveAny) == "table" and type(liveAny.lastReason) == "string"
						then liveAny.lastReason
						else "unavailable",
				},
			},
			transferLock = {
				failedAcquireCount = if type(transferAny) == "table"
						and type(transferAny.failedAcquireCount) == "number"
					then transferAny.failedAcquireCount
					else 0,
				lastReason = if type(transferAny) == "table" and type(transferAny.lastReason) == "string"
					then transferAny.lastReason
					else "unavailable",
				activeLockCount = if type(transferAny) == "table"
						and type(transferAny.activeLockCount) == "number"
					then transferAny.activeLockCount
					else 0,
			},
			ingress = {
				rescue = cloneTable(rescueIngressDiagnostics) or {},
				profileTeleport = cloneTable(profileTeleportIngressDiagnostics) or {},
				admission = {
					retryDeferred = if type(admissionAny) == "table"
							and type(admissionAny.totalRetryDeferred) == "number"
						then admissionAny.totalRetryDeferred
						else 0,
				},
			},
			reasons = reasons,
		},
	}
end

globalEnv._MemoryStoreObservability_QueryAPI = {
	GetSnapshot = function(input: any?): any
		return MemoryStoreObservabilityService.GetSnapshot(input)
	end,
}

if type(_G) == "table" then
	rawset(_G, "_MemoryStoreObservability_QueryAPI", globalEnv._MemoryStoreObservability_QueryAPI)
end

return MemoryStoreObservabilityService
