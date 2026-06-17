--!nocheck

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local globalEnv: any = getfenv()
local MemoryStoreObservabilityService = require("../src/ServerScriptService/Services/MemoryStoreObservabilityService")

globalEnv._RealmAdmissionQueue_QueryAPI = {
	GetProcessingDiagnostics = function(): any
		return {
			totalProcessed = 12,
			totalRetryDeferred = 4,
		}
	end,
}

globalEnv._RescueContractHubSurface_QueryAPI = {
	GetPendingRescueQueueEntries = function(_limit: number, _at: number): { any }
		return {
			{ queueEntryId = "entry-1" },
			{ queueEntryId = "entry-2" },
		}
	end,
}

globalEnv._LiveRealmRegistry_QueryAPI = {
	GetDiagnostics = function(): any
		return {
			refreshFailed = 3,
			pruneFailed = 1,
			lastReason = "refresh_failed",
		}
	end,
}

globalEnv._LiveRealmRegistryHubSurface_QueryAPI = {
	ListLiveRealmAvailability = function(_limit: number, _at: number): { any }
		return {
			{ realmId = "realm-a" },
			{ realmId = "realm-b" },
			{ realmId = "realm-c" },
		}
	end,
}

globalEnv._TransferLock_QueryAPI = {
	GetDiagnostics = function(): any
		return {
			failedAcquireCount = 2,
			lastReason = "transfer_lock_active",
			activeLockCount = 1,
		}
	end,
}

globalEnv._RescueContractService_QueryAPI = {
	GetAdmissionIngressDiagnostics = function(): any
		return {
			lastReason = "accepted",
			primaryAttempts = 5,
		}
	end,
}

globalEnv._ProfileTeleportHandoffService_QueryAPI = {
	GetAdmissionIngressDiagnostics = function(): any
		return {
			lastReason = "admission_queue_unavailable",
			fallbackAttempts = 2,
		}
	end,
}

local acceptedResult = MemoryStoreObservabilityService.GetSnapshot()
assertTrue(acceptedResult.accepted, "aggregate snapshot accepted")
assertEqual(acceptedResult.snapshot.queueDepth.rescuePendingCount, 2, "rescue queue depth")
assertEqual(acceptedResult.snapshot.queueDepth.admissionLastProcessedCount, 12, "admission processed counter")
assertEqual(acceptedResult.snapshot.realm.activeRealmCount, 3, "active realm count")
assertEqual(acceptedResult.snapshot.realm.staleRegistryIndicators.refreshFailed, 3, "refresh failed indicator")
assertEqual(acceptedResult.snapshot.transferLock.failedAcquireCount, 2, "transfer lock failed acquire count")
assertEqual(acceptedResult.snapshot.ingress.admission.retryDeferred, 4, "admission retry deferred counter")
assertEqual(acceptedResult.snapshot.reasons.rescueIngress, "accepted", "rescue ingress reason")
assertEqual(
	acceptedResult.snapshot.ingress.profileTeleport.lastReason,
	"admission_queue_unavailable",
	"profile teleport ingress reason parity"
)

globalEnv._TransferLock_QueryAPI = nil
local partialResult = MemoryStoreObservabilityService.GetSnapshot()
assertEqual(partialResult.accepted, false, "missing dependency returns partial snapshot")
assertEqual(partialResult.reason, "partial_observability_unavailable", "partial reason")
assertEqual(
	partialResult.snapshot.reasons.transferLock,
	"transfer_lock_api_unavailable",
	"transfer lock unavailable reason"
)

print("memory_store_observability_service: all checks passed")
