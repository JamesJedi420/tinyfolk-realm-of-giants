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
			local memberSegment = ""
			if type(entry.partyMemberUserIds) == "table" then
				memberSegment = table.concat(entry.partyMemberUserIds, ",")
			end
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
				memberSegment,
			}, "|")
		end,
		Decode = function(encoded: string): any
			local parts = string.split(encoded, "|")
			local memberIds = nil
			if type(parts[10]) == "string" and parts[10] ~= "" then
				memberIds = {}
				for _, token in ipairs(string.split(parts[10], ",")) do
					table.insert(memberIds, tonumber(token))
				end
			end
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
				partyMemberUserIds = memberIds,
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
local admissionFanoutEvents = {}

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
	queueNotificationFanout = {
		PublishAdmission = function(eventName: string, payload: any)
			table.insert(admissionFanoutEvents, {
				eventName = eventName,
				payload = payload,
			})
			return {
				accepted = true,
				reason = "accepted",
			}
		end,
	},
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
assertEqual(#admissionFanoutEvents, 4, "fanout emits enqueue and batch events")
assertEqual(admissionFanoutEvents[1].eventName, "admission_enqueue", "fanout event for first enqueue")
assertEqual(admissionFanoutEvents[2].eventName, "admission_enqueue", "fanout event for second enqueue")
assertEqual(admissionFanoutEvents[3].eventName, "admission_enqueue", "fanout event for third enqueue")
assertEqual(admissionFanoutEvents[4].eventName, "admission_batch_processed", "fanout event for batch process")
assertEqual(admissionFanoutEvents[4].payload.processed, 3, "fanout batch payload processed")
assertEqual(admissionFanoutEvents[4].payload.succeeded, 1, "fanout batch payload succeeded")
assertEqual(admissionFanoutEvents[4].payload.failed, 1, "fanout batch payload failed")

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
	local e2eAdapter, e2eRemovedIds = makeQueueAdapter()
	local resolverMembersByPartyId: { [string]: { number } } = {}
	local registerCalls = 0
	local unregisterCalls = 0
	local e2eDispatchCalls = 0

	local configuredE2E = RealmAdmissionQueueService.ConfigureForTests({
		adapter = e2eAdapter,
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
		partyResolver = {
			RegisterPartyMembers = function(input: any)
				registerCalls += 1
				if
					type(input) ~= "table"
					or type(input.partyId) ~= "string"
					or type(input.memberUserIds) ~= "table"
				then
					return {
						accepted = false,
						reason = "input_invalid",
					}
				end
				local normalized = {}
				for _, userId in ipairs(input.memberUserIds) do
					table.insert(normalized, userId)
				end
				table.sort(normalized)
				resolverMembersByPartyId[input.partyId] = normalized
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
			ResolvePartyMemberUserIds = function(partyId: string): { number }
				local members = resolverMembersByPartyId[partyId]
				if type(members) ~= "table" then
					return {}
				end
				local cloned = {}
				for _, userId in ipairs(members) do
					table.insert(cloned, userId)
				end
				return cloned
			end,
			UnregisterParty = function(partyId: string)
				unregisterCalls += 1
				resolverMembersByPartyId[partyId] = nil
				return {
					accepted = true,
					reason = "accepted",
				}
			end,
		},
		teleportDispatcher = {
			Dispatch = function(entry: any)
				e2eDispatchCalls += 1
				local members = resolverMembersByPartyId[entry.partyId]
				if type(members) ~= "table" or #members <= 0 then
					return {
						ok = false,
						retryable = true,
						reason = "party_members_unavailable",
					}
				end
				return {
					ok = true,
					retryable = false,
					reason = "accepted",
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
	assertTrue(configuredE2E.ok, "e2e configure accepted")

	local enqueueE2E = RealmAdmissionQueueService.EnqueueAdmission(makeEntry({
		operationId = "op-e2e-party",
		partyId = "party-e2e",
		expiration = 220,
		partySize = 2,
		partyMemberUserIds = { 7102, 7101 },
	}))
	assertTrue(enqueueE2E.accepted, "e2e enqueue accepted")
	assertEqual(registerCalls, 1, "e2e register called on enqueue acceptance")

	local processedE2E = RealmAdmissionQueueService.ProcessBatch(10)
	assertTrue(processedE2E.accepted, "e2e process accepted")
	assertEqual(processedE2E.outcome.succeeded, 1, "e2e process succeeds with resolver members")
	assertEqual(processedE2E.outcome.retryDeferred, 0, "e2e process has no retry deferral")
	assertEqual(e2eDispatchCalls, 1, "e2e dispatch called once")
	assertEqual(unregisterCalls, 1, "e2e unregister called on terminal success")
	assertTrue(resolverMembersByPartyId["party-e2e"] == nil, "e2e unregister clears resolver state")
	assertTrue(e2eRemovedIds["receipt-1"] == true, "e2e success removes queue entry")

	RealmAdmissionQueueService.ResetForTests()
end

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
