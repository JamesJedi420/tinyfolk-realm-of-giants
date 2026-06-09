--!strict

local ContainmentRewardResolver = require("../src/ServerScriptService/Services/ContainmentRewardResolver")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function makeStore(config: any?): any
	local configAny: any = if type(config) == "table" then config else {}
	local records: { [string]: string? } = {}
	local calls = {
		tryBegin = 0,
		markCompleted = 0,
		releaseProcessing = 0,
	}
	return {
		calls = calls,
		records = records,
		TryBegin = function(operationId: string): any
			calls.tryBegin += 1
			local status = records[operationId]
			if status == "completed" then
				return { accepted = true, reason = "accepted", status = "completed" }
			end
			if status == "processing" then
				return { accepted = false, reason = "already_processing", status = "processing" }
			end
			records[operationId] = "processing"
			return { accepted = true, reason = "accepted", status = "begun" }
		end,
		MarkCompleted = function(operationId: string): any
			calls.markCompleted += 1
			if configAny.failMarkCompleted == true then
				return { accepted = false, reason = "adapter_update_failed" }
			end
			records[operationId] = "completed"
			return { accepted = true, reason = "accepted", status = "completed" }
		end,
		ReleaseProcessing = function(operationId: string): any
			calls.releaseProcessing += 1
			if records[operationId] == "processing" then
				records[operationId] = nil
			end
			return { accepted = true, reason = "accepted", status = "released" }
		end,
	}
end

local function makeScoreApi(events: { any }): any
	return {
		RequestScoreEvent = function(userId: number, eventId: string, at: number, metadata: any): any
			table.insert(events, {
				userId = userId,
				eventId = eventId,
				at = at,
				metadata = metadata,
			})
			return { accepted = true, reason = "accepted", awardedPoints = 50 }
		end,
	}
end

local function resolveInput(overrides: any?): any
	local input = {
		operationId = "containment-released-101-202-1000",
		custodianUserId = 101,
		targetUserId = 202,
		captureStartedAt = 1,
		captureExpiresAt = 9,
		endedAt = 5,
		endReason = "released",
		custodyWindowSeconds = 8,
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			input[key] = value
		end
	end
	return input
end

local scoreEvents = {}
local reputationEvents = {}
local trophyEvents = {}
local store = makeStore()
local resolver = ContainmentRewardResolver.Create({
	idempotencyStore = store,
	scoreApi = makeScoreApi(scoreEvents),
	trophyApi = {
		RecordContainmentEnd = function(metadata: any): any
			table.insert(trophyEvents, metadata)
			return { accepted = true, reason = "accepted" }
		end,
	},
	eventLogApi = {
		RecordEvent = function(category: string, _message: string, _severity: string, _at: number, metadata: any)
			table.insert(reputationEvents, {
				category = category,
				metadata = metadata,
			})
			return { accepted = true, reason = "accepted" }
		end,
	},
	profileGateway = {
		UpdateLoadedPlayerProfileData = function(_player: any, updater: any): any
			local data = updater({ schemaVersion = 1, userId = 101 })
			return { ok = type(data) == "table", reason = nil, data = data }
		end,
	},
	now = function()
		return 100
	end,
})

local first = resolver.Resolve(resolveInput())
assertTrue(first.accepted, "first terminal resolve accepted")
assertEqual(first.operationId, "containment-released-101-202-1000", "explicit operation id preserved")
assertTrue(first.rewardGranted, "first terminal resolve grants score")
assertEqual(first.heldSeconds, 4, "held seconds calculated")
assertEqual(first.contributionRatio, 0.5, "contribution ratio from custody window")
assertEqual(first.pairRewardCount, 1, "first pair reward count")
assertEqual(#scoreEvents, 1, "first terminal resolve emits one score")
assertEqual(scoreEvents[1].eventId, "containment_reward", "score event id")
assertEqual(scoreEvents[1].metadata.endReason, "released", "score metadata end reason")
assertEqual(store.calls.markCompleted, 1, "first terminal resolve completes idempotency")
assertTrue(first.reputationAccepted, "first terminal resolve reputation accepted")
assertEqual(#reputationEvents, 1, "first terminal resolve emits reputation log")
assertEqual(reputationEvents[1].category, "reputation_update", "reputation log category")
assertEqual(reputationEvents[1].metadata.outcomeKind, "containment_custody_end", "reputation log outcome kind")
assertEqual(#trophyEvents, 1, "first terminal resolve records trophy")
assertEqual(trophyEvents[1].endReason, "released", "trophy metadata end reason")
assertTrue(first.trophyAccepted, "first terminal resolve trophy accepted")

local duplicate = resolver.Resolve(resolveInput())
assertTrue(duplicate.accepted, "duplicate completed accepted as no-op")
assertTrue(duplicate.duplicate, "duplicate completed marked duplicate")
assertEqual(duplicate.rewardGranted, false, "duplicate completed does not grant reward")
assertEqual(#scoreEvents, 1, "duplicate completed does not emit score")
assertEqual(#trophyEvents, 1, "duplicate completed does not record trophy again")

local processingStore = makeStore()
processingStore.records["containment-released-101-202-1000"] = "processing"
local processingResolver = ContainmentRewardResolver.Create({
	idempotencyStore = processingStore,
	scoreApi = makeScoreApi({}),
})
local processing = processingResolver.Resolve(resolveInput())
assertEqual(processing.accepted, false, "already processing duplicate rejected")
assertEqual(processing.reason, "already_processing", "already processing reason")

local failedEvents = {}
local failedStore = makeStore({ failMarkCompleted = true })
local failedResolver = ContainmentRewardResolver.Create({
	idempotencyStore = failedStore,
	scoreApi = makeScoreApi(failedEvents),
})
local failed = failedResolver.Resolve(resolveInput({ operationId = "containment-released-101-202-2000" }))
assertEqual(failed.accepted, false, "mark completed failure rejected")
assertEqual(failed.reason, "idempotency_mark_completed_failed", "mark completed failure reason")
assertTrue(failed.cleanupDebt, "mark completed failure reports cleanup debt")
assertEqual(#failedEvents, 1, "mark completed failure still ran side effect once")
assertEqual(failedStore.calls.releaseProcessing, 0, "mark completed failure does not release processing")
local failedRetry = failedResolver.Resolve(resolveInput({ operationId = "containment-released-101-202-2000" }))
assertEqual(failedRetry.accepted, false, "retry after mark completed failure rejected")
assertEqual(failedRetry.reason, "already_processing", "retry after mark completed failure remains blocked")
assertEqual(#failedEvents, 1, "retry after mark completed failure does not duplicate score")

local diminishingEvents = {}
local diminishingResolver = ContainmentRewardResolver.Create({
	idempotencyStore = makeStore(),
	scoreApi = makeScoreApi(diminishingEvents),
	pairRetentionSeconds = 300,
})
local dimFirst = diminishingResolver.Resolve(resolveInput({
	operationId = "containment-released-101-202-3000",
	captureStartedAt = 10,
	endedAt = 18,
}))
local dimSecond = diminishingResolver.Resolve(resolveInput({
	operationId = "containment-released-101-202-4000",
	captureStartedAt = 20,
	endedAt = 28,
}))
local dimThird = diminishingResolver.Resolve(resolveInput({
	operationId = "containment-released-101-202-5000",
	captureStartedAt = 30,
	endedAt = 38,
}))
local dimFourth = diminishingResolver.Resolve(resolveInput({
	operationId = "containment-released-101-202-6000",
	captureStartedAt = 40,
	endedAt = 48,
}))
assertEqual(dimFirst.contributionRatio, 1, "first pair reward multiplier")
assertEqual(dimSecond.contributionRatio, 0.5, "second pair reward multiplier")
assertEqual(dimThird.contributionRatio, 0.25, "third pair reward multiplier")
assertEqual(dimFourth.reason, "pair_reward_cap_reached", "fourth pair reward capped")
assertEqual(dimFourth.rewardGranted, false, "fourth pair reward no score")
assertEqual(#diminishingEvents, 3, "pair reward cap emits only three scores")

local missingScoreResolver = ContainmentRewardResolver.Create({
	idempotencyStore = makeStore(),
	scoreApi = {},
})
local missingScore = missingScoreResolver.Resolve(resolveInput({ operationId = "containment-released-101-202-7000" }))
assertTrue(missingScore.accepted, "missing score api is non-fatal")
assertEqual(missingScore.scoreReason, "score_api_unavailable", "missing score api reason")
assertEqual(missingScore.rewardGranted, false, "missing score api reports no reward")

local invalid = resolver.Resolve({
	custodianUserId = 101,
	targetUserId = 202,
	captureStartedAt = 1,
	endedAt = 2,
	endReason = "owned",
	custodyWindowSeconds = 8,
})
assertEqual(invalid.accepted, false, "invalid end reason rejected")
assertEqual(invalid.reason, "end_reason_invalid", "invalid end reason")

print("containment_reward_resolver: all checks passed")
