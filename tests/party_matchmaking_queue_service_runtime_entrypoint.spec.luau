--!nocheck

local PartyMatchmakingQueueState = require("../src/ReplicatedStorage/Shared/GiantRealm/PartyMatchmakingQueueState")
local PartyMatchmakingQueueService = require("../src/ServerScriptService/Services/PartyMatchmakingQueueService")
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

local function makeEntryInput(overrides: any?): any
	local entry = {
		operationId = "party_matchmaking_tinyfolk_party_101_1000",
		partyId = "tinyfolk_party:101:1000",
		leaderUserId = 101,
		partySize = 2,
		partyMemberUserIds = { 202, 101 },
		desiredActivity = "raid",
		skillBand = 1,
		toolTier = 0,
		createdAt = 100,
		expiration = 400,
		status = "pending",
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
				tostring(entry.leaderUserId),
				tostring(entry.partySize),
				table.concat(entry.partyMemberUserIds, ","),
				entry.desiredActivity,
				tostring(entry.skillBand),
				tostring(entry.toolTier),
				tostring(entry.createdAt),
				tostring(entry.expiration),
				entry.status,
				tostring(entry.targetRealmId or ""),
			}, "|")
		end,
		Decode = function(encoded: string): any
			local parts = string.split(encoded, "|")
			local memberIds = {}
			for _, token in ipairs(string.split(parts[5], ",")) do
				if token ~= "" then
					table.insert(memberIds, tonumber(token))
				end
			end
			return {
				operationId = parts[1],
				partyId = parts[2],
				leaderUserId = tonumber(parts[3]),
				partySize = tonumber(parts[4]),
				partyMemberUserIds = memberIds,
				desiredActivity = parts[6],
				skillBand = tonumber(parts[7]),
				toolTier = tonumber(parts[8]),
				createdAt = tonumber(parts[9]),
				expiration = tonumber(parts[10]),
				status = parts[11],
				targetRealmId = if parts[12] == "" then nil else parts[12],
			}
		end,
	}
end

local queueName = MemoryStoreStructurePolicy.GetPolicy("partyMatchmakingQueue").name
local queueItems = {}
local idempotencyRecords = {}

local adapter = {
	QueueAddAsync = function(_queueName: string, value: string, _ttl: number, _priority: number)
		table.insert(queueItems, {
			id = "receipt-" .. tostring(#queueItems + 1),
			value = value,
		})
		return true
	end,
	QueueReadAsync = function(_queueName: string, maxItems: number)
		local batch = {}
		for index = 1, math.min(maxItems, #queueItems) do
			table.insert(batch, queueItems[index])
		end
		return batch
	end,
	QueueRemoveAsync = function(_queueName: string, receiptId: string)
		for index, item in ipairs(queueItems) do
			if item.id == receiptId then
				table.remove(queueItems, index)
				return true
			end
		end
		return false
	end,
	HashMapUpdateAsync = function(_mapName: string, key: string, transform: (any) -> any, _ttl: number)
		local current = idempotencyRecords[key]
		local nextValue = transform(current)
		if nextValue == nil then
			idempotencyRecords[key] = nil
		else
			idempotencyRecords[key] = nextValue
		end
		return nextValue
	end,
}

local admissionCalls = {}
local admissionApi = {
	RequestPartyMatchAdmission = function(payload: any)
		table.insert(admissionCalls, payload)
		return {
			accepted = true,
			reason = "accepted",
			payload = payload,
		}
	end,
}

local partyApi = {
	ResolveMatchmakingQueueContext = function(userId: number)
		if userId ~= 101 then
			return { accepted = false, reason = "party_leader_required" }
		end
		return {
			accepted = true,
			reason = "accepted",
			partyId = "tinyfolk_party:101:1000",
			partyMemberUserIds = { 101, 202 },
		}
	end,
}

PartyMatchmakingQueueService.ResetForTests()
PartyMatchmakingQueueService.ConfigureForTests({
	adapter = adapter,
	codec = makeCodec(),
	structurePolicy = MemoryStoreStructurePolicy,
	now = function()
		return 100
	end,
	admissionApi = admissionApi,
	tinyfolkPartyApi = partyApi,
	listLiveRealmAvailability = function()
		return {
			{
				realmId = "realm-raid",
				ownerUserId = 9001,
				privateServerId = "ps-raid",
				accessMode = "raid_enabled",
				playerCount = 1,
				capacity = 8,
				dangerRating = 0.8,
				lifecycle = "active",
				isAvailable = true,
				updatedAt = 100,
			},
		}
	end,
	enableProcessingLoop = false,
})

local api = _G._PartyMatchmakingQueue_QueryAPI
assertTrue(type(api) == "table", "query api published")

local enqueueAccepted = api.EnqueueMatchmaking({
	partyId = "tinyfolk_party:101:1000",
	leaderUserId = 101,
	partySize = 2,
	partyMemberUserIds = { 101, 202 },
	desiredActivity = "raid",
	skillBand = 1,
	toolTier = 0,
	createdAt = 100,
})
assertEqual(enqueueAccepted.accepted, true, "enqueue accepted")
assertEqual(enqueueAccepted.snapshot.status, "pending", "enqueue pending status")
assertEqual(#queueItems, 1, "queue item stored")

local duplicateEnqueue = api.EnqueueMatchmaking({
	partyId = "tinyfolk_party:101:1000",
	leaderUserId = 101,
	partySize = 2,
	partyMemberUserIds = { 101, 202 },
	desiredActivity = "scouting",
})
assertEqual(duplicateEnqueue.accepted, false, "duplicate enqueue rejected")
assertEqual(duplicateEnqueue.reason, "party_already_queued", "duplicate enqueue reason")

local processResult = api.ProcessBatch(5)
assertEqual(processResult.accepted, true, "process batch accepted")
assertEqual(processResult.outcome.matched, 1, "one party matched")
assertEqual(#admissionCalls, 1, "admission called once")
assertEqual(admissionCalls[1].targetRealmId, "realm-raid", "matched raid realm")

local snapshotResult = api.GetQueueSnapshot({
	operationId = enqueueAccepted.snapshot.operationId,
})
assertEqual(snapshotResult.accepted, true, "snapshot found")
assertEqual(snapshotResult.snapshot.status, "matched", "snapshot matched status")
assertEqual(snapshotResult.snapshot.targetRealmId, "realm-raid", "snapshot target realm")

PartyMatchmakingQueueService.ResetForTests()
queueItems = {}
idempotencyRecords = {}
admissionCalls = {}

PartyMatchmakingQueueService.ConfigureForTests({
	adapter = adapter,
	codec = makeCodec(),
	structurePolicy = MemoryStoreStructurePolicy,
	now = function()
		return 500
	end,
	admissionApi = admissionApi,
	tinyfolkPartyApi = partyApi,
	listLiveRealmAvailability = function()
		return {}
	end,
	enableProcessingLoop = false,
})

local expiredEnqueue = api.EnqueueMatchmaking({
	partyId = "tinyfolk_party:101:1000",
	leaderUserId = 101,
	partySize = 2,
	partyMemberUserIds = { 101, 202 },
	desiredActivity = "raid",
	createdAt = 100,
	timeoutSeconds = 300,
})
assertEqual(expiredEnqueue.accepted, true, "expired-path enqueue accepted")

local expiredProcess = api.ProcessBatch(5)
assertEqual(expiredProcess.outcome.expired, 1, "expired queue item")
assertEqual(#admissionCalls, 0, "expired path does not call admission")

PartyMatchmakingQueueService.ResetForTests()

print("party_matchmaking_queue_service_runtime_entrypoint: all checks passed")
