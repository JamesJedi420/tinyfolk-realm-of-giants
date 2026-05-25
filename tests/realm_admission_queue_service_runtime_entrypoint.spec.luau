--!nocheck

local RealmAdmissionQueueService = require("../src/ServerScriptService/Services/RealmAdmissionQueueService")
local RealmAdmissionQueueState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAdmissionQueueState")
local MemoryStoreStructurePolicy = require("../src/ServerScriptService/Services/MemoryStoreStructurePolicy")

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

local function makeEntry(overrides: any?): any
	local entry = {
		operationId = "op-100",
		partyId = "party-42",
		targetRealmId = "realm-9402",
		entryType = "standard",
		priority = nil,
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

local function makeCodec()
	return {
		Encode = function(entry: any): string
			return table.concat({
				entry.operationId,
				entry.partyId,
				entry.targetRealmId,
				entry.entryType,
				tostring(entry.priority),
				tostring(entry.createdAt),
				tostring(entry.expiration),
				tostring(entry.partySize),
				tostring(entry.retryCount),
			}, "|")
		end,
		Decode = function(encoded: string): any
			local parts = string.split(encoded, "|")
			return {
				operationId = parts[1],
				partyId = parts[2],
				targetRealmId = parts[3],
				entryType = parts[4],
				priority = tonumber(parts[5]),
				createdAt = tonumber(parts[6]),
				expiration = tonumber(parts[7]),
				partySize = tonumber(parts[8]),
				retryCount = tonumber(parts[9]),
			}
		end,
	}
end

local function makeQueueAdapter()
	local queueByName: { [string]: { any } } = {}
	local removedIds: { [string]: boolean } = {}
	local adapter: any = {}

	adapter.QueueAddAsync = function(queueName: string, encoded: string, _ttlSeconds: number, priority: number)
		if queueByName[queueName] == nil then
			queueByName[queueName] = {}
		end
		local queue = queueByName[queueName]
		local nextId = "receipt-" .. tostring(#queue + 1)
		table.insert(queue, {
			id = nextId,
			value = encoded,
			priority = priority,
		})
		table.sort(queue, function(a, b)
			if a.priority == b.priority then
				return a.id < b.id
			end
			return a.priority > b.priority
		end)
	end

	adapter.QueueReadAsync = function(
		queueName: string,
		count: number,
		_allOrNothing: boolean,
		_waitTimeout: number
	): { any }
		local queue = queueByName[queueName] or {}
		local result = {}
		for _, item in ipairs(queue) do
			if #result >= count then
				break
			end
			if removedIds[item.id] ~= true then
				table.insert(result, {
					id = item.id,
					value = item.value,
				})
			end
		end
		return result
	end

	adapter.QueueRemoveAsync = function(_queueName: string, receiptId: string)
		removedIds[receiptId] = true
	end

	return adapter, removedIds
end

RealmAdmissionQueueService.ResetForTests()
assertTrue(type(_G._RealmAdmissionQueue_QueryAPI) == "table", "service stores global query api")
assertTrue(type(RealmAdmissionQueueService.Start) == "function", "service exposes Start")
assertTrue(type(RealmAdmissionQueueService.EnqueueAdmission) == "function", "service exposes EnqueueAdmission")
assertTrue(type(RealmAdmissionQueueService.ProcessBatch) == "function", "service exposes ProcessBatch")

local startWithoutAdapter = RealmAdmissionQueueService.Start({
	codec = makeCodec(),
	queueState = RealmAdmissionQueueState,
	structurePolicy = MemoryStoreStructurePolicy,
})
assertTrue(startWithoutAdapter.ok, "start without adapter still initializes bounded service")

local unavailableEnqueue = RealmAdmissionQueueService.EnqueueAdmission(makeEntry())
assertEqual(unavailableEnqueue.accepted, false, "enqueue rejects when adapter unavailable")
assertEqual(unavailableEnqueue.reason, "adapter_unavailable", "enqueue unavailable reason")

local unavailableProcess = RealmAdmissionQueueService.ProcessBatch(5)
assertTrue(unavailableProcess.accepted, "process returns outcome even when read fails")
assertEqual(unavailableProcess.outcome.failed, 1, "process captures adapter-unavailable read failure")

local adapter, removedIds = makeQueueAdapter()
local reserveCalls = 0
local releaseCalls = 0
local dispatchCalls = 0

local configured = RealmAdmissionQueueService.ConfigureForTests({
	adapter = adapter,
	codec = makeCodec(),
	queueState = RealmAdmissionQueueState,
	structurePolicy = MemoryStoreStructurePolicy,
	capacityApi = {
		ReserveTinyfolkSlots = function(_realmId: string, _partySize: number, _nowAt: number)
			reserveCalls += 1
			return {
				accepted = true,
				reason = "accepted",
			}
		end,
		ReleaseReservedSlots = function(_realmId: string, _partySize: number, _nowAt: number)
			releaseCalls += 1
			return {
				accepted = true,
			}
		end,
	},
	teleportDispatcher = {
		Dispatch = function(entry: any)
			dispatchCalls += 1
			if entry.operationId == "op-fatal" then
				return {
					ok = false,
					retryable = false,
					reason = "dispatch_rejected",
				}
			end
			return {
				ok = true,
				retryable = false,
			}
		end,
	},
	operationLock = {
		TryAcquire = function(_operationId: string): boolean
			return true
		end,
		Release = function(_operationId: string)
			return
		end,
	},
	now = function(): number
		return 150
	end,
})
assertTrue(configured.ok, "configure for tests accepted")

assertTrue(
	RealmAdmissionQueueService.EnqueueAdmission(makeEntry({ operationId = "op-expired", expiration = 120 })).accepted,
	"enqueue expired seed accepted"
)
assertTrue(
	RealmAdmissionQueueService.EnqueueAdmission(makeEntry({ operationId = "op-success", expiration = 220 })).accepted,
	"enqueue success seed accepted"
)
assertTrue(
	RealmAdmissionQueueService.EnqueueAdmission(makeEntry({ operationId = "op-fatal", expiration = 220 })).accepted,
	"enqueue fatal seed accepted"
)

local processed = RealmAdmissionQueueService.ProcessBatch(10)
assertTrue(processed.accepted, "process batch accepted")
assertEqual(processed.outcome.processed, 3, "processed count")
assertEqual(processed.outcome.expired, 1, "expired count")
assertEqual(processed.outcome.succeeded, 1, "success count")
assertEqual(processed.outcome.failed, 1, "failed count")
assertEqual(processed.outcome.retryDeferred, 0, "retry deferred count")
assertEqual(reserveCalls, 2, "reserve called for non-expired entries")
assertEqual(releaseCalls, 1, "release called for non-retryable dispatch rejection")
assertEqual(dispatchCalls, 2, "dispatch called for non-expired entries")

local readAfterProcess = RealmAdmissionQueueService.ReadBatch(10)
assertTrue(readAfterProcess.accepted, "read after process accepted")
assertEqual(#readAfterProcess.items, 0, "queue emptied by expired/success/fatal handling")
assertTrue(removedIds["receipt-1"] == true, "expired entry removed")
assertTrue(removedIds["receipt-2"] == true, "success entry removed")
assertTrue(removedIds["receipt-3"] == true, "fatal entry removed")

local invalidProcess = RealmAdmissionQueueService.ProcessBatch(0)
assertEqual(invalidProcess.accepted, false, "invalid process max rejected")
assertEqual(invalidProcess.reason, "max_items_invalid", "invalid process max reason")

RealmAdmissionQueueService.ResetForTests()

do
	local loopAdapter, loopRemovedIds = makeQueueAdapter()
	local loopDispatchCalls = 0
	local scheduledCallbacks = {}
	local scheduledDelays = {}
	local scheduledTokens = {}
	local cancelledToken = nil

	local configuredLoop = RealmAdmissionQueueService.ConfigureForTests({
		adapter = loopAdapter,
		codec = makeCodec(),
		queueState = RealmAdmissionQueueState,
		structurePolicy = MemoryStoreStructurePolicy,
		capacityApi = {
			ReserveTinyfolkSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
			ReleaseReservedSlots = function(_realmId: string, _partySize: number, _nowAt: number)
				return {
					accepted = true,
				}
			end,
		},
		teleportDispatcher = {
			Dispatch = function(_entry: any)
				loopDispatchCalls += 1
				return {
					ok = true,
					retryable = false,
				}
			end,
		},
		operationLock = {
			TryAcquire = function(_operationId: string): boolean
				return true
			end,
			Release = function(_operationId: string)
				return
			end,
		},
		now = function(): number
			return 150
		end,
		enableProcessingLoop = true,
		processIntervalSeconds = 2,
		processBatchSize = 3,
		processScheduler = {
			schedule = function(delaySeconds: number, callback: () -> ())
				table.insert(scheduledDelays, delaySeconds)
				table.insert(scheduledCallbacks, callback)
				local token = "token-" .. tostring(#scheduledCallbacks)
				table.insert(scheduledTokens, token)
				return token
			end,
			cancel = function(token: any)
				cancelledToken = token
			end,
		},
	})

	assertTrue(configuredLoop.ok, "loop configure accepted")
	assertEqual(scheduledDelays[1], 2, "loop interval is scheduled")
	assertTrue(type(scheduledCallbacks[1]) == "function", "loop callback captured")

	assertTrue(
		RealmAdmissionQueueService.EnqueueAdmission(makeEntry({ operationId = "op-loop", expiration = 220 })).accepted,
		"loop enqueue accepted"
	)

	scheduledCallbacks[1]()

	assertEqual(loopDispatchCalls, 1, "scheduled callback processes queued item")
	assertTrue(loopRemovedIds["receipt-1"] == true, "scheduled callback removes processed receipt")
	assertEqual(scheduledDelays[2], 2, "loop reschedules after callback")

	RealmAdmissionQueueService.ResetForTests()
	assertEqual(cancelledToken, scheduledTokens[2], "reset cancels pending scheduled token")
end

print("realm_admission_queue_service_runtime_entrypoint: all checks passed")
