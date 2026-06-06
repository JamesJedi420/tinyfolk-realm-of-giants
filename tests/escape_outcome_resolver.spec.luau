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
	assertEqual(scoreCalls, 1, "score called once")
	assertEqual(lootCalls, 1, "loot called once")
	assertEqual(profileCalls, 1, "profile called once")
	assertEqual(defenseCalls, 1, "defense called once")
	assertEqual(returnCalls, 1, "return called once")
	assertEqual(#profileData.escapeHistory, 1, "profile history appended")
	assertEqual(profileData.escapeHistory[1].operationId, "op-escape-1", "profile history operation")

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
	assertEqual(profileCalls, 1, "duplicate skips profile")
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

print("escape_outcome_resolver: all checks passed")
