--!nocheck
--!nolint BuiltinGlobalWrite

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local sampleEntry = {
	queueEntryId = "queue_cross_1",
	operationId = "rescue_accept_queue_cross_1",
	capturedUserId = 2102,
	realmId = "giant_realm_9001",
	sessionId = "session_a",
	rewardHint = "rescue_contract",
	dangerRating = 0.5,
	expiration = 220,
	rescuerUserId = 2101,
	targetRealmOwnerUserId = 9001,
	entryRouteId = "RescueEntryRoute_9001",
	entryRouteKind = "RescueEntry",
	createdAt = 200,
	status = "pending",
}

local queueItems: { any } = {}
local removedReceipts: { string } = {}
local ingested: { any } = {}
local encodedPayload = ""

_G._MemoryStoreAdapter_QueryAPI = {
	QueueAddAsync = function(_queueName: string, _encoded: string, _ttl: number, _priority: number): boolean
		return true
	end,
	QueueReadAsync = function(_queueName: string, maxItems: number, _allServers: boolean, _timeout: number): { any }
		local items = {}
		for index = 1, math.min(maxItems, #queueItems) do
			table.insert(items, queueItems[index])
		end
		return items
	end,
	QueueRemoveAsync = function(_queueName: string, receiptId: string): boolean
		table.insert(removedReceipts, receiptId)
		for index, item in ipairs(queueItems) do
			if item.id == receiptId then
				table.remove(queueItems, index)
				break
			end
		end
		return true
	end,
}

_G._RescueContractService_QueryAPI = {
	IngestQueueEntry = function(entry: any, receiptId: string, _at: number): any
		table.insert(ingested, {
			entry = entry,
			receiptId = receiptId,
		})
		return {
			accepted = true,
			reason = "accepted",
		}
	end,
}

require("../src/ServerScriptService/Services/RescueContractQueueService")

local api = _G._RescueContractQueue_QueryAPI
assertTrue(type(api) == "table", "rescue contract queue api present")
api.ResetForTests()
api.ConfigureForTests({
	adapter = _G._MemoryStoreAdapter_QueryAPI,
	codec = {
		Encode = function(value: any): string
			encodedPayload = value.queueEntryId
			return encodedPayload
		end,
		Decode = function(_encoded: string): any
			return sampleEntry
		end,
	},
})

local enqueueResult = api.EnqueueQueueEntry(sampleEntry)
assertTrue(enqueueResult.accepted, "enqueue accepted")

table.insert(queueItems, {
	id = "receipt_1",
	value = encodedPayload,
})

local reconcileResult = api.ReconcileFromStore({
	at = 210,
	limit = 10,
})
assertTrue(reconcileResult.accepted, "reconcile accepted")
assertEqual(reconcileResult.ingestedCount, 1, "reconcile ingested count")
assertEqual(#ingested, 1, "ingest call count")
assertEqual(ingested[1].receiptId, "receipt_1", "ingest receipt id")

local removeResult = api.RemoveStoreReceipt("receipt_1")
assertTrue(removeResult.accepted, "remove accepted")
assertEqual(#removedReceipts, 1, "remove receipt count")

print("rescue_contract_queue_service_runtime_entrypoint: all checks passed")
