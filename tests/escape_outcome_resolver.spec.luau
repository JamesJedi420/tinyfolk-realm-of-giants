--!strict

local EscapeOutcomeResolver = require("../src/ServerScriptService/Services/EscapeOutcomeResolver")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function makePlayer(userId: number): any
	return {
		UserId = userId,
	}
end

do
	local scoreCalls = 0
	local lootCalls = 0
	local profileCalls = 0
	local defenseCalls = 0
	local returnCalls = 0
	local reputationLogEvents = {}
	local profileData: any = {
		schemaVersion = 1,
		userId = 101,
	}

	local resolver = EscapeOutcomeResolver.Create({
		now = function()
			return 10
		end,
		scoreApi = {
			RequestScoreEvent = function(userId: number, eventId: string, at: number, metadata: any): any
				scoreCalls += 1
				assertEqual(userId, 101, "score user")
				assertEqual(eventId, "escape_success", "score event")
				assertEqual(at, 10, "score time")
				assertEqual(metadata.operationId, "op-escape-1", "score operation metadata")
				return { accepted = true, reason = "accepted" }
			end,
		},
		carriedLootApi = {
			ConsumeForEscape = function(userId: number, operationId: string): any
				lootCalls += 1
				assertEqual(userId, 101, "loot user")
				assertEqual(operationId, "op-escape-1", "loot operation")
				return {
					accepted = true,
					reason = "accepted",
					loot = {
						items = { "glimmer" },
						wood = 2,
						stone = 1,
						value = 3,
					},
				}
			end,
		},
		profileGateway = {
			UpdateLoadedPlayerProfileData = function(_player: any, updater: any): any
				profileCalls += 1
				profileData = updater(profileData)
				return { ok = true, reason = nil, data = profileData }
			end,
		},
		defenseHistoryApi = {
			RecordEscapeDefenseOutcome = function(record: any): any
				defenseCalls += 1
				assertEqual(record.operationId, "op-escape-1", "defense operation")
				assertEqual(record.escapedUserId, 101, "defense user")
				assertEqual(record.lootValue, 3, "defense loot value")
				return { accepted = true, reason = "accepted" }
			end,
		},
		returnToHub = function(player: any): boolean
			returnCalls += 1
			assertEqual(player.UserId, 101, "return user")
			return true
		end,
		eventLogApi = {
			RecordEvent = function(category: string, message: string, severity: string, _at: number, metadata: any)
				table.insert(reputationLogEvents, {
					category = category,
					message = message,
					severity = severity,
					metadata = metadata,
				})
				return { accepted = true, reason = "accepted" }
			end,
		},
	})

	local player = makePlayer(101)
	local first = resolver.Resolve({
		operationId = "op-escape-1",
		userId = 101,
		player = player,
		sourceKind = "final_exit",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
		realmOwnerUserId = 9001,
		realmId = "giant_realm_9001",
		difficulty = 2,
		now = 10,
	})

	assertTrue(first.accepted, "first accepted")
	assertFalse(first.duplicate, "first not duplicate")
	assertTrue(first.lootTransferred, "loot transferred")
	assertTrue(first.profileUpdated, "profile updated")
	assertTrue(first.defenseUpdated, "defense updated")
	assertTrue(first.returnedToHub, "returned to hub")
	assertTrue(first.safeLocationUpdated, "safe location updated")
	assertEqual(scoreCalls, 1, "score called once")
	assertEqual(lootCalls, 1, "loot called once")
	assertEqual(profileCalls, 2, "profile called for escape history and safe location")
	assertEqual(defenseCalls, 1, "defense called once")
	assertEqual(returnCalls, 1, "return called once")
	assertEqual(#profileData.escapeHistory, 1, "profile history appended")
	assertEqual(profileData.escapeHistory[1].operationId, "op-escape-1", "profile history operation")
	assertEqual(profileData.safeLocation.returnReason, "escape_success", "profile safe location reason")
	assertEqual(profileData.safeLocation.sourceId, "EscapeRoute_A", "profile safe location source")
	assertTrue(first.reputationAccepted, "reputation update accepted")
	assertEqual(#reputationLogEvents, 1, "reputation log emitted")
	assertEqual(reputationLogEvents[1].category, "reputation_update", "reputation log category")
	assertEqual(reputationLogEvents[1].metadata.outcomeKind, "escape_success", "reputation log outcome kind")

	local duplicate = resolver.Resolve({
		operationId = "op-escape-1",
		userId = 101,
		player = player,
		sourceKind = "final_exit",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
		now = 10,
	})
	assertTrue(duplicate.accepted, "duplicate accepted for cleanup/no-op")
	assertTrue(duplicate.duplicate, "duplicate marked")
	assertEqual(duplicate.reason, "duplicate_completed", "duplicate reason")
	assertEqual(scoreCalls, 1, "duplicate skips score")
	assertEqual(lootCalls, 1, "duplicate skips loot")
	assertEqual(profileCalls, 2, "duplicate skips profile")
	assertEqual(defenseCalls, 1, "duplicate skips defense")
	assertEqual(returnCalls, 1, "duplicate skips return")
end

do
	local resolver = EscapeOutcomeResolver.Create({
		idempotencyStore = {
			TryBegin = function(_operationId: any): any
				return { accepted = false, reason = "already_processing", status = "processing" }
			end,
			MarkCompleted = function(_operationId: any): any
				return { accepted = true, reason = "accepted" }
			end,
			ReleaseProcessing = function(_operationId: any): any
				return { accepted = true, reason = "accepted" }
			end,
		},
	})
	local result = resolver.Resolve({
		operationId = "op-processing",
		userId = 202,
		sourceKind = "route_escape",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
	})
	assertFalse(result.accepted, "processing duplicate rejected")
	assertEqual(result.reason, "already_processing", "processing duplicate reason")
	assertTrue(result.duplicate, "processing duplicate flag")
end

do
	local scoreCalls = 0
	local profileCalls = 0
	local reputationLogEvents = {}
	local resolver = EscapeOutcomeResolver.Create({
		scoreApi = {
			RequestScoreEvent = function(_userId: number, _eventId: string, _at: number, _metadata: any): any
				scoreCalls += 1
				return { accepted = true, reason = "accepted" }
			end,
		},
		profileGateway = {
			UpdateLoadedPlayerProfileData = function(_player: any, _updater: any): any
				profileCalls += 1
				return { ok = false, reason = "player_profile_not_loaded" }
			end,
		},
		defenseHistoryApi = {
			RecordEscapeDefenseOutcome = function(_record: any): any
				return { accepted = true, reason = "accepted" }
			end,
		},
		eventLogApi = {
			RecordEvent = function(category: string, _message: string, _severity: string, _at: number, metadata: any)
				table.insert(reputationLogEvents, { category = category, metadata = metadata })
				return { accepted = true, reason = "accepted" }
			end,
		},
	})

	local result = resolver.Resolve({
		operationId = "op-profile-failure",
		userId = 303,
		player = makePlayer(303),
		sourceKind = "route_escape",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
	})
	assertTrue(result.accepted, "profile failure nonfatal")
	assertFalse(result.profileUpdated, "profile not updated")
	assertEqual(result.profileReason, "player_profile_not_loaded", "profile reason")
	assertTrue(result.lootTransferred, "missing loot api defaults accepted")
	assertEqual(result.loot.value, 0, "missing loot api zero value")
	assertEqual(scoreCalls, 1, "score still emitted")
	assertEqual(profileCalls, 1, "profile attempted")
	assertEqual(#reputationLogEvents, 1, "reputation log emitted on nonfatal profile failure")
	assertEqual(reputationLogEvents[1].metadata.reputationAccepted, false, "reputation failure logged")

	local duplicate = resolver.Resolve({
		operationId = "op-profile-failure",
		userId = 303,
		player = makePlayer(303),
		sourceKind = "route_escape",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
	})
	assertTrue(duplicate.accepted, "profile failure duplicate accepted")
	assertTrue(duplicate.duplicate, "profile failure duplicate marked")
	assertEqual(scoreCalls, 1, "profile failure duplicate skips score")
	assertEqual(profileCalls, 1, "profile failure duplicate skips profile")
end

do
	local scoreCalls = 0
	local lootCalls = 0
	local profileCalls = 0
	local defenseCalls = 0
	local returnCalls = 0
	local releaseCalls = 0
	local recordStatus: string? = nil
	local markCompletedShouldFail = true

	local resolver = EscapeOutcomeResolver.Create({
		idempotencyStore = {
			TryBegin = function(_operationId: any): any
				if recordStatus == "processing" then
					return { accepted = false, reason = "already_processing", status = "processing" }
				end
				if recordStatus == "completed" then
					return { accepted = true, reason = "accepted", status = "completed" }
				end
				recordStatus = "processing"
				return { accepted = true, reason = "accepted", status = "begun" }
			end,
			MarkCompleted = function(_operationId: any): any
				if markCompletedShouldFail then
					return { accepted = false, reason = "adapter_update_failed" }
				end
				recordStatus = "completed"
				return { accepted = true, reason = "accepted", status = "completed" }
			end,
			ReleaseProcessing = function(_operationId: any): any
				releaseCalls += 1
				recordStatus = nil
				return { accepted = true, reason = "accepted", status = "released" }
			end,
		},
		scoreApi = {
			RequestScoreEvent = function(_userId: number, _eventId: string, _at: number, _metadata: any): any
				scoreCalls += 1
				return { accepted = true, reason = "accepted" }
			end,
		},
		carriedLootApi = {
			ConsumeForEscape = function(_userId: number, _operationId: string): any
				lootCalls += 1
				return { accepted = true, reason = "accepted", loot = { value = 1 } }
			end,
		},
		profileGateway = {
			UpdateLoadedPlayerProfileData = function(_player: any, updater: any): any
				profileCalls += 1
				updater({ schemaVersion = 1, userId = 404 })
				return { ok = true, reason = nil }
			end,
		},
		defenseHistoryApi = {
			RecordEscapeDefenseOutcome = function(_record: any): any
				defenseCalls += 1
				return { accepted = true, reason = "accepted" }
			end,
		},
		returnToHub = function(_player: any): boolean
			returnCalls += 1
			return true
		end,
	})

	local first = resolver.Resolve({
		operationId = "op-completion-fails",
		userId = 404,
		player = makePlayer(404),
		sourceKind = "route_escape",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
	})
	assertFalse(first.accepted, "completion failure rejected")
	assertEqual(first.reason, "idempotency_mark_completed_failed", "completion failure reason")
	assertTrue(first.cleanupDebt, "completion failure leaves cleanup debt")
	assertEqual(releaseCalls, 0, "completion failure does not release processing")
	assertEqual(recordStatus, "processing", "completion failure leaves operation processing")

	markCompletedShouldFail = false
	local retry = resolver.Resolve({
		operationId = "op-completion-fails",
		userId = 404,
		player = makePlayer(404),
		sourceKind = "route_escape",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
	})
	assertFalse(retry.accepted, "completion failure retry blocked")
	assertEqual(retry.reason, "already_processing", "completion failure retry reason")
	assertEqual(scoreCalls, 1, "completion failure retry skips score")
	assertEqual(lootCalls, 1, "completion failure retry skips loot")
	assertEqual(profileCalls, 2, "completion failure retry skips profile")
	assertEqual(defenseCalls, 1, "completion failure retry skips defense")
	assertEqual(returnCalls, 1, "completion failure retry skips return")
end

print("escape_outcome_resolver: all checks passed")
