--!strict

local RealmAdmissionQueueProcessor = require("../src/ServerScriptService/Services/RealmAdmissionQueueProcessor")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function _assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function makeEntry(overrides: any?): any
	local entry = {
		operationId = "op-1",
		partyId = "party-1",
		targetRealmId = "realm-1",
		entryType = "standard",
		priority = 100,
		createdAt = 100,
		expiration = 200,
		partySize = 2,
		retryCount = 0,
	}
	if overrides ~= nil then
		for key, value in pairs(overrides) do
			entry[key] = value
		end
	end
	return entry
end

local function makeQueueStore(items: { any })
	local calls: { any } = {}
	local queueStore = {
		ReadBatch = function(maxItems: number)
			table.insert(calls, { method = "ReadBatch", maxItems = maxItems })
			local result = {}
			for index, item in ipairs(items) do
				if index > maxItems then
					break
				end
				table.insert(result, item)
			end
			return {
				accepted = true,
				reason = "accepted",
				items = result,
			}
		end,
		Remove = function(receiptId: string)
			table.insert(calls, { method = "Remove", receiptId = receiptId })
			return {
				accepted = true,
				reason = "accepted",
			}
		end,
	}
	return queueStore, calls
end

local function makeQueueStoreWithRemoveFailure(items: { any }, failureIds: { [string]: boolean })
	local calls: { any } = {}
	local queueStore = {
		ReadBatch = function(maxItems: number)
			table.insert(calls, { method = "ReadBatch", maxItems = maxItems })
			local result = {}
			for index, item in ipairs(items) do
				if index > maxItems then
					break
				end
				table.insert(result, item)
			end
			return {
				accepted = true,
				reason = "accepted",
				items = result,
			}
		end,
		Remove = function(receiptId: string)
			table.insert(calls, { method = "Remove", receiptId = receiptId })
			if failureIds[receiptId] == true then
				return {
					accepted = false,
					reason = "adapter_remove_failed",
				}
			end
			return {
				accepted = true,
				reason = "accepted",
			}
		end,
	}
	return queueStore, calls
end

local queueState = {
	IsExpired = function(entry: any, nowAt: number): boolean
		return nowAt >= entry.expiration
	end,
}

do
	local queueStore, queueCalls = makeQueueStore({
		{ receiptId = "expired-1", entry = makeEntry({ expiration = 150 }) },
		{ receiptId = "ok-1", entry = makeEntry({ operationId = "op-ok", expiration = 220 }) },
	})
	local capacityCalls: { any } = {}
	local dispatchCalls: { any } = {}
	local lockCalls: { any } = {}
	local unregisterCalls: { any } = {}

	local processor = RealmAdmissionQueueProcessor.Create({
		queueStore = queueStore,
		queueState = queueState,
		capacityApi = {
			ReserveTinyfolkSlots = function(realmId: string, partySize: number, nowAt: number)
				table.insert(capacityCalls, {
					method = "ReserveTinyfolkSlots",
					realmId = realmId,
					partySize = partySize,
					nowAt = nowAt,
				})
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
			ReleaseReservedSlots = function(realmId: string, partySize: number, nowAt: number)
				table.insert(capacityCalls, {
					method = "ReleaseReservedSlots",
					realmId = realmId,
					partySize = partySize,
					nowAt = nowAt,
				})
				return {
					accepted = true,
				}
			end,
		},
		teleportDispatcher = {
			Dispatch = function(entry: any)
				table.insert(dispatchCalls, {
					operationId = entry.operationId,
				})
				return {
					ok = true,
					retryable = false,
				}
			end,
		},
		operationLock = {
			TryAcquire = function(operationId: string): boolean
				table.insert(lockCalls, { method = "TryAcquire", operationId = operationId })
				return true
			end,
			Release = function(operationId: string)
				table.insert(lockCalls, { method = "Release", operationId = operationId })
			end,
		},
		partyResolver = {
			UnregisterParty = function(partyId: string)
				table.insert(unregisterCalls, partyId)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
		now = function(): number
			return 160
		end,
	})

	local outcome = processor.ProcessBatch(5)
	assertEqual(outcome.processed, 2, "processed count")
	assertEqual(outcome.expired, 1, "expired count")
	assertEqual(outcome.succeeded, 1, "success count")
	assertEqual(outcome.retryDeferred, 0, "retry deferred count")
	assertEqual(outcome.failed, 0, "failed count")

	assertEqual(queueCalls[1].method, "ReadBatch", "read batch called")
	assertEqual(queueCalls[2].receiptId, "expired-1", "expired removed first")
	assertEqual(queueCalls[3].receiptId, "ok-1", "success removed")
	assertEqual(capacityCalls[1].method, "ReserveTinyfolkSlots", "reserve before dispatch")
	assertEqual(dispatchCalls[1].operationId, "op-ok", "dispatch called for valid entry")
	assertEqual(lockCalls[1].method, "TryAcquire", "lock acquired")
	assertEqual(lockCalls[2].method, "Release", "lock released")
	assertEqual(unregisterCalls[1], "party-1", "expired entry unregisters party")
	assertEqual(unregisterCalls[2], "party-1", "success entry unregisters party")
end

do
	local queueStore, queueCalls = makeQueueStore({
		{ receiptId = "retry-1", entry = makeEntry({ operationId = "op-retry" }) },
		{ receiptId = "fatal-1", entry = makeEntry({ operationId = "op-fatal" }) },
		{ receiptId = "busy-1", entry = makeEntry({ operationId = "op-busy" }) },
	})

	local capacityCalls: { any } = {}
	local dispatchCalls: { any } = {}
	local unregisterCalls: { any } = {}

	local lockBusyIds = {
		op_busy = true,
	}

	local processor = RealmAdmissionQueueProcessor.Create({
		queueStore = queueStore,
		queueState = queueState,
		capacityApi = {
			ReserveTinyfolkSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				table.insert(capacityCalls, { method = "ReserveTinyfolkSlots" })
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
			ReleaseReservedSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				table.insert(capacityCalls, { method = "ReleaseReservedSlots" })
				return {
					accepted = true,
				}
			end,
		},
		teleportDispatcher = {
			Dispatch = function(entry: any)
				table.insert(dispatchCalls, { operationId = entry.operationId })
				if entry.operationId == "op-retry" then
					return {
						ok = false,
						retryable = true,
						reason = "teleport_timeout",
					}
				end
				return {
					ok = false,
					retryable = false,
					reason = "teleport_rejected",
				}
			end,
		},
		operationLock = {
			TryAcquire = function(operationId: string): boolean
				if lockBusyIds[string.gsub(operationId, "-", "_")] then
					return false
				end
				return true
			end,
			Release = function(_operationId: string) end,
		},
		partyResolver = {
			UnregisterParty = function(partyId: string)
				table.insert(unregisterCalls, partyId)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(5)
	assertEqual(outcome.processed, 3, "processed count second")
	assertEqual(outcome.succeeded, 0, "success count second")
	assertEqual(outcome.expired, 0, "expired count second")
	assertEqual(outcome.retryDeferred, 2, "retry deferred second")
	assertEqual(outcome.failed, 1, "failed count second")

	assertEqual(#dispatchCalls, 2, "dispatch not called for lock-busy item")
	assertEqual(#capacityCalls, 4, "capacity reserve+release for dispatch failures")
	assertEqual(queueCalls[2].receiptId, "fatal-1", "fatal item removed")
	assertEqual(#unregisterCalls, 1, "only terminal non-retryable failure unregisters")
end

do
	local queueStore, queueCalls = makeQueueStoreWithRemoveFailure({
		{ receiptId = "remove-fails", entry = makeEntry({ operationId = "op-remove-fails" }) },
	}, {
		["remove-fails"] = true,
	})

	local capacityCalls: { any } = {}
	local dispatchCalls: { any } = {}
	local unregisterCalls: { any } = {}

	local processor = RealmAdmissionQueueProcessor.Create({
		queueStore = queueStore,
		queueState = queueState,
		capacityApi = {
			ReserveTinyfolkSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				table.insert(capacityCalls, { method = "ReserveTinyfolkSlots" })
				return { accepted = true, reason = "accepted" }
			end,
			ReleaseReservedSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				table.insert(capacityCalls, { method = "ReleaseReservedSlots" })
				return { accepted = true }
			end,
		},
		teleportDispatcher = {
			Dispatch = function(entry: any)
				table.insert(dispatchCalls, { operationId = entry.operationId })
				return {
					ok = true,
					retryable = false,
				}
			end,
		},
		partyResolver = {
			UnregisterParty = function(partyId: string)
				table.insert(unregisterCalls, partyId)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(1)
	assertEqual(outcome.processed, 1, "remove failure processed")
	assertEqual(outcome.succeeded, 0, "remove failure blocks success")
	assertEqual(outcome.retryDeferred, 1, "remove failure becomes retry deferred")
	assertEqual(outcome.failed, 0, "remove failure does not hard-fail")
	assertEqual(#dispatchCalls, 1, "remove failure path still dispatched once")
	assertEqual(#capacityCalls, 2, "remove failure path compensates capacity")
	assertEqual(queueCalls[2].method, "Remove", "remove attempted on success path")
	assertEqual(#unregisterCalls, 0, "remove-failure retry path does not unregister")
end

do
	local queueStore, queueCalls = makeQueueStore({
		{ receiptId = "concurrent-1", entry = makeEntry({ operationId = "op-concurrent" }) },
		{ receiptId = "concurrent-2", entry = makeEntry({ operationId = "op-concurrent" }) },
	})

	local dispatchCalls: { any } = {}
	local lockCalls: { any } = {}
	local unregisterCalls: { any } = {}

	local processor = RealmAdmissionQueueProcessor.Create({
		queueStore = queueStore,
		queueState = queueState,
		capacityApi = {
			ReserveTinyfolkSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				return { accepted = true, reason = "accepted" }
			end,
			ReleaseReservedSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				return { accepted = true }
			end,
		},
		teleportDispatcher = {
			Dispatch = function(entry: any)
				table.insert(dispatchCalls, { operationId = entry.operationId })
				return {
					ok = true,
					retryable = false,
				}
			end,
		},
		operationLock = {
			TryAcquire = function(operationId: string): boolean
				table.insert(lockCalls, { method = "TryAcquire", operationId = operationId })
				for _, call in ipairs(lockCalls) do
					if call.method == "LockHeld" and call.operationId == operationId then
						return false
					end
				end
				table.insert(lockCalls, { method = "LockHeld", operationId = operationId })
				return true
			end,
			Release = function(operationId: string)
				table.insert(lockCalls, { method = "Release", operationId = operationId })
			end,
		},
		partyResolver = {
			UnregisterParty = function(partyId: string)
				table.insert(unregisterCalls, partyId)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
		now = function(): number
			return 110
		end,
	})

	local outcome = processor.ProcessBatch(5)
	assertEqual(outcome.processed, 2, "concurrency processed count")
	assertEqual(outcome.succeeded, 1, "concurrency only one dispatch succeeds")
	assertEqual(outcome.retryDeferred, 1, "concurrency duplicate deferred by lock")
	assertEqual(outcome.failed, 0, "concurrency no hard failures")
	assertEqual(#dispatchCalls, 1, "concurrency lock prevents duplicate dispatch")
	assertEqual(queueCalls[2].receiptId, "concurrent-1", "only first concurrent receipt removed")
	assertEqual(#unregisterCalls, 1, "concurrency unregister only on terminal success")
end

print("realm_admission_queue_processor: all checks passed")
