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
	assertEqual(outcome.retryDeferred, 0, "remove failure does not use retry deferred counter")
	assertEqual(outcome.cleanupDeferred, 1, "remove failure becomes cleanup deferred")
	assertEqual(outcome.failed, 0, "remove failure does not hard-fail")
	assertEqual(#dispatchCalls, 1, "remove failure path still dispatched once")
	assertEqual(#capacityCalls, 1, "remove failure path keeps completed capacity state")
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

do
	local queueStore, queueCalls = makeQueueStore({
		{ receiptId = "completed-1", entry = makeEntry({ operationId = "op-completed" }) },
	})
	local dispatchCalls: { any } = {}
	local unregisterCalls: { any } = {}

	local processor = RealmAdmissionQueueProcessor.Create({
		queueStore = queueStore,
		queueState = queueState,
		capacityApi = {
			ReserveTinyfolkSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				error("capacity should not be reserved for completed duplicate")
			end,
		},
		teleportDispatcher = {
			Dispatch = function(entry: any)
				table.insert(dispatchCalls, entry.operationId)
				return { ok = true, retryable = false }
			end,
		},
		idempotencyStore = {
			TryBegin = function(_operationId: string)
				return {
					accepted = true,
					reason = "accepted",
					status = "completed",
				}
			end,
		},
		partyResolver = {
			UnregisterParty = function(partyId: string)
				table.insert(unregisterCalls, partyId)
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(1)
	assertEqual(outcome.processed, 1, "completed duplicate processed")
	assertEqual(outcome.duplicatesSkipped, 1, "completed duplicate skipped")
	assertEqual(outcome.cleanupDeferred, 0, "completed duplicate cleanup not deferred")
	assertEqual(outcome.succeeded, 0, "completed duplicate not counted as success")
	assertEqual(#dispatchCalls, 0, "completed duplicate does not dispatch")
	assertEqual(queueCalls[2].receiptId, "completed-1", "completed duplicate receipt removed")
	assertEqual(unregisterCalls[1], "party-1", "completed duplicate unregisters party")
end

do
	local queueStore, _queueCalls = makeQueueStoreWithRemoveFailure({
		{ receiptId = "completed-remove-fails", entry = makeEntry({ operationId = "op-completed-remove-fails" }) },
	}, {
		["completed-remove-fails"] = true,
	})

	local processor = RealmAdmissionQueueProcessor.Create({
		queueStore = queueStore,
		queueState = queueState,
		idempotencyStore = {
			TryBegin = function(_operationId: string)
				return {
					accepted = true,
					reason = "accepted",
					status = "completed",
				}
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(1)
	assertEqual(outcome.processed, 1, "completed cleanup failure processed")
	assertEqual(outcome.duplicatesSkipped, 0, "cleanup failure not counted skipped")
	assertEqual(outcome.cleanupDeferred, 1, "cleanup failure deferred")
	assertEqual(outcome.retryDeferred, 0, "cleanup failure has dedicated counter")
end

do
	local queueStore, queueCalls = makeQueueStore({
		{ receiptId = "idempotent-1", entry = makeEntry({ operationId = "op-idempotent" }) },
		{ receiptId = "idempotent-2", entry = makeEntry({ operationId = "op-idempotent" }) },
	})
	local operationStatusById: { [string]: string? } = {}
	local dispatchCalls: { any } = {}

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
				table.insert(dispatchCalls, entry.operationId)
				return { ok = true, retryable = false }
			end,
		},
		idempotencyStore = {
			TryBegin = function(operationId: string)
				if operationStatusById[operationId] == "completed" then
					return { accepted = true, reason = "accepted", status = "completed" }
				end
				if operationStatusById[operationId] == "processing" then
					return { accepted = false, reason = "already_processing", status = "processing" }
				end
				operationStatusById[operationId] = "processing"
				return { accepted = true, reason = "accepted", status = "begun" }
			end,
			MarkCompleted = function(operationId: string)
				operationStatusById[operationId] = "completed"
				return { accepted = true, reason = "accepted", status = "completed" }
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(2)
	assertEqual(outcome.processed, 2, "idempotent duplicate processed")
	assertEqual(outcome.succeeded, 1, "idempotent first succeeds")
	assertEqual(outcome.duplicatesSkipped, 1, "idempotent second skipped")
	assertEqual(#dispatchCalls, 1, "idempotent duplicate dispatches once")
	assertEqual(queueCalls[2].receiptId, "idempotent-1", "idempotent first removed")
	assertEqual(queueCalls[3].receiptId, "idempotent-2", "idempotent duplicate removed")
end

do
	local queueStore, _queueCalls = makeQueueStoreWithRemoveFailure({
		{ receiptId = "success-remove-fails", entry = makeEntry({ operationId = "op-success-remove-fails" }) },
	}, {
		["success-remove-fails"] = true,
	})
	local operationStatusById: { [string]: string? } = {}
	local dispatchCalls = 0

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
			Dispatch = function(_entry: any)
				dispatchCalls += 1
				return { ok = true, retryable = false }
			end,
		},
		idempotencyStore = {
			TryBegin = function(operationId: string)
				if operationStatusById[operationId] == "completed" then
					return { accepted = true, reason = "accepted", status = "completed" }
				end
				operationStatusById[operationId] = "processing"
				return { accepted = true, reason = "accepted", status = "begun" }
			end,
			MarkCompleted = function(operationId: string)
				operationStatusById[operationId] = "completed"
				return { accepted = true, reason = "accepted", status = "completed" }
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local firstOutcome = processor.ProcessBatch(1)
	assertEqual(firstOutcome.succeeded, 0, "remove-failed success not counted")
	assertEqual(firstOutcome.cleanupDeferred, 1, "remove-failed success cleanup deferred")
	assertEqual(dispatchCalls, 1, "remove-failed success dispatched once")

	local secondOutcome = processor.ProcessBatch(1)
	assertEqual(secondOutcome.duplicatesSkipped, 0, "remove failure remains cleanup deferred")
	assertEqual(secondOutcome.cleanupDeferred, 1, "completed duplicate remove failure deferred")
	assertEqual(dispatchCalls, 1, "completed duplicate after remove failure does not redispatch")
end

do
	local queueStore, _queueCalls = makeQueueStore({
		{ receiptId = "completion-write-fails", entry = makeEntry({ operationId = "op-completion-write-fails" }) },
	})
	local operationStatusById: { [string]: string? } = {}
	local dispatchCalls = 0
	local capacityReleaseCalls = 0
	local processingReleaseCalls = 0

	local processor = RealmAdmissionQueueProcessor.Create({
		queueStore = queueStore,
		queueState = queueState,
		capacityApi = {
			ReserveTinyfolkSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				return { accepted = true, reason = "accepted" }
			end,
			ReleaseReservedSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				capacityReleaseCalls += 1
				return { accepted = true }
			end,
		},
		teleportDispatcher = {
			Dispatch = function(_entry: any)
				dispatchCalls += 1
				return { ok = true, retryable = false }
			end,
		},
		idempotencyStore = {
			TryBegin = function(operationId: string)
				if operationStatusById[operationId] == "processing" then
					return { accepted = false, reason = "already_processing", status = "processing" }
				end
				operationStatusById[operationId] = "processing"
				return { accepted = true, reason = "accepted", status = "begun" }
			end,
			MarkCompleted = function(_operationId: string)
				return { accepted = false, reason = "adapter_update_failed" }
			end,
			ReleaseProcessing = function(operationId: string)
				processingReleaseCalls += 1
				operationStatusById[operationId] = nil
				return { accepted = true, reason = "accepted", status = "released" }
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local firstOutcome = processor.ProcessBatch(1)
	assertEqual(firstOutcome.cleanupDeferred, 1, "completion failure after dispatch becomes cleanup debt")
	assertEqual(firstOutcome.retryDeferred, 0, "completion failure after dispatch is not reopened for retry")
	assertEqual(dispatchCalls, 1, "completion failure after dispatch dispatched once")
	assertEqual(capacityReleaseCalls, 0, "completion failure after dispatch keeps reserved capacity")
	assertEqual(processingReleaseCalls, 0, "completion failure after dispatch keeps processing record")

	local secondOutcome = processor.ProcessBatch(1)
	assertEqual(secondOutcome.retryDeferred, 1, "completion failure duplicate remains blocked by processing record")
	assertEqual(dispatchCalls, 1, "completion failure duplicate does not redispatch")
	assertEqual(capacityReleaseCalls, 0, "completion failure duplicate does not release capacity")
	assertEqual(processingReleaseCalls, 0, "completion failure duplicate does not release processing")
end

do
	local queueStore, _queueCalls = makeQueueStore({
		{ receiptId = "retry-release", entry = makeEntry({ operationId = "op-retry-release" }) },
	})
	local released = false
	local completed = false

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
			Dispatch = function(_entry: any)
				return { ok = false, retryable = true, reason = "retry_later" }
			end,
		},
		idempotencyStore = {
			TryBegin = function(_operationId: string)
				return { accepted = true, reason = "accepted", status = "begun" }
			end,
			MarkCompleted = function(_operationId: string)
				completed = true
				return { accepted = true, reason = "accepted", status = "completed" }
			end,
			ReleaseProcessing = function(_operationId: string)
				released = true
				return { accepted = true, reason = "accepted", status = "released" }
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(1)
	assertEqual(outcome.retryDeferred, 1, "retryable dispatch deferred")
	assertEqual(released, true, "retryable dispatch releases processing")
	assertEqual(completed, false, "retryable dispatch does not complete operation")
end

do
	local queueStore, queueCalls = makeQueueStore({
		{ receiptId = "fatal-complete", entry = makeEntry({ operationId = "op-fatal-complete" }) },
		{ receiptId = "fatal-complete-again", entry = makeEntry({ operationId = "op-fatal-complete" }) },
	})
	local operationStatusById: { [string]: string? } = {}
	local dispatchCalls = 0

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
			Dispatch = function(_entry: any)
				dispatchCalls += 1
				return { ok = false, retryable = false, reason = "fatal" }
			end,
		},
		idempotencyStore = {
			TryBegin = function(operationId: string)
				if operationStatusById[operationId] == "completed" then
					return { accepted = true, reason = "accepted", status = "completed" }
				end
				operationStatusById[operationId] = "processing"
				return { accepted = true, reason = "accepted", status = "begun" }
			end,
			MarkCompleted = function(operationId: string)
				operationStatusById[operationId] = "completed"
				return { accepted = true, reason = "accepted", status = "completed" }
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(2)
	assertEqual(outcome.failed, 1, "fatal first failed")
	assertEqual(outcome.duplicatesSkipped, 1, "fatal duplicate skipped")
	assertEqual(dispatchCalls, 1, "fatal duplicate not repeated")
	assertEqual(queueCalls[2].receiptId, "fatal-complete", "fatal first removed")
	assertEqual(queueCalls[3].receiptId, "fatal-complete-again", "fatal duplicate removed")
end

do
	local queueStore, _queueCalls = makeQueueStore({
		{
			receiptId = "party-transfer",
			entry = makeEntry({
				operationId = "op-party-transfer",
				partyId = "tinyfolk_party:5001:100",
			}),
		},
	})
	local transferOutcomeCalls: { any } = {}
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
			Dispatch = function(_entry: any)
				return {
					ok = true,
					retryable = false,
					transferredUserIds = { 5001 },
				}
			end,
		},
		partyResolver = {
			ResolvePartyMemberUserIds = function(_partyId: string, _entry: any)
				return { 5001, 5002 }
			end,
			UnregisterParty = function(partyId: string)
				table.insert(unregisterCalls, partyId)
			end,
		},
		tinyfolkPartyApi = {
			HandleTransferOutcome = function(input: any)
				table.insert(transferOutcomeCalls, input)
				return {
					accepted = true,
					reason = "accepted",
					dissolved = false,
				}
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(1)
	assertEqual(outcome.succeeded, 1, "party transfer success processed")
	assertEqual(transferOutcomeCalls[1].partyId, "tinyfolk_party:5001:100", "transfer outcome party id")
	assertEqual(transferOutcomeCalls[1].transferredUserIds[1], 5001, "transfer outcome transferred user")
	assertEqual(#unregisterCalls, 0, "partial transfer keeps resolver registration")
end

do
	local queueStore, _queueCalls = makeQueueStore({
		{
			receiptId = "party-transfer-full",
			entry = makeEntry({
				operationId = "op-party-transfer-full",
				partyId = "tinyfolk_party:5001:101",
			}),
		},
	})
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
			Dispatch = function(_entry: any)
				return {
					ok = true,
					retryable = false,
					transferredUserIds = { 5001, 5002 },
				}
			end,
		},
		partyResolver = {
			UnregisterParty = function(partyId: string)
				table.insert(unregisterCalls, partyId)
			end,
		},
		tinyfolkPartyApi = {
			HandleTransferOutcome = function(_input: any)
				return {
					accepted = true,
					reason = "accepted",
					dissolved = true,
				}
			end,
		},
		now = function(): number
			return 120
		end,
	})

	local outcome = processor.ProcessBatch(1)
	assertEqual(outcome.succeeded, 1, "full party transfer success processed")
	assertEqual(unregisterCalls[1], "tinyfolk_party:5001:101", "full transfer unregisters party")
end

print("realm_admission_queue_processor: all checks passed")
