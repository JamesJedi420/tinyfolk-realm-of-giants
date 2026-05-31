--!nocheck

local globalEnv: any = _G

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

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function resetGlobals()
	globalEnv._NeutralWildlifeService_QueryAPI = nil
end

resetGlobals()
require("../src/ServerScriptService/Services/NeutralWildlifeService.server")

local serviceApi = globalEnv._NeutralWildlifeService_QueryAPI
assertTrue(type(serviceApi) == "table", "service query api published")
assertTrue(type(serviceApi.Start) == "function", "start function published")
assertTrue(type(serviceApi.Tick) == "function", "tick function published")
assertTrue(type(serviceApi.GetWildlifeSnapshot) == "function", "snapshot function published")
assertTrue(type(serviceApi.GetWildlifeDiagnostics) == "function", "diagnostics function published")
assertTrue(type(serviceApi.RequestWildlifeDisturbance) == "function", "disturbance function published")
assertTrue(type(serviceApi.RequestWildlifeInteraction) == "function", "interaction function published")

local now = 100
local recordedEvents = {}
local scoreRequests = {}

local function makeHabitatNode(name: string, attributes: any): any
	return {
		Name = name,
		Position = attributes.Position,
		GetAttribute = function(_self: any, attributeName: string): any
			return attributes[attributeName]
		end,
		IsA = function(_self: any, className: string): boolean
			return className == "BasePart"
		end,
	}
end

serviceApi.ConfigureForTests({
	now = function()
		return now
	end,
	realmTemplateIds = { "RealmAlpha" },
	habitatNodeResolver = function(): any
		return {
			makeHabitatNode("node_a", {
				WildlifeHabitatGroupId = "waterline",
				RealmTemplateId = "RealmAlpha",
				WildlifeZoneId = "shoreline",
				Position = { X = 10, Y = 0, Z = 10 },
			}),
			makeHabitatNode("node_b", {
				WildlifeHabitatGroupId = "waterline",
				RealmTemplateId = "RealmAlpha",
				WildlifeZoneId = "shoreline",
				Position = { X = 14, Y = 0, Z = 14 },
			}),
		}
	end,
	HabitatGroups = {
		{
			habitatGroupId = "forest_edge",
			realmTemplateIds = { "RealmAlpha" },
			targetActive = 2,
			speciesIds = { "deer", "boar" },
			clueTag = "disturbed_forest_edge",
		},
		{
			habitatGroupId = "waterline",
			realmTemplateIds = { "RealmAlpha" },
			targetActive = 2,
			speciesIds = { "otter", "duck" },
			clueTag = "disturbed_waterline",
		},
	},
	TargetActiveWildlifeTotal = 2,
	MaxActiveWildlifeTotal = 3,
	WildlifeLifetimeSeconds = 30,
	RespawnIntervalSeconds = 10,
	DisturbanceMaxDistance = 10,
	WildlifeAnchorBucketSize = 8,
	MaxFeedGrantsPerWindow = 1,
	FeedGrantWindowSeconds = 120,
	FeedScoreEventId = "wildlife_feed",
	roleResolver = function(userId: number): string
		if userId == 7001 then
			return "Tinyfolk"
		end
		return "Giant"
	end,
	roleServiceApi = {
		CanPlayerPerformInteraction = function(_userId: number, _interactionName: string): boolean
			return true
		end,
	},
	scoreServiceApi = {
		RequestScoreEvent = function(userId: number, eventId: string, at: number, metadata: any): any
			table.insert(scoreRequests, {
				userId = userId,
				eventId = eventId,
				at = at,
				metadata = metadata,
			})
			return { accepted = true, reason = "accepted" }
		end,
	},
	eventLogApi = {
		RecordEvent = function(category: any, message: any, severity: any, timestamp: any, metadata: any): any
			table.insert(recordedEvents, {
				category = category,
				message = message,
				severity = severity,
				timestamp = timestamp,
				metadata = metadata,
			})
			return { accepted = true, reason = "accepted" }
		end,
	},
})

local initial = serviceApi.GetWildlifeSnapshot()
assertTrue(initial.accepted, "initial snapshot accepted")
assertEqual(initial.activeCount, 2, "initial population seeded")
assertEqual(#initial.records, 2, "initial records length")
assertEqual(initial.records[1].realmTemplateId, "RealmAlpha", "initial realm id")
assertEqual(initial.records[1].habitatGroupId, "waterline", "initial habitat resolved from nodes")
assertEqual(initial.records[2].habitatGroupId, "waterline", "second habitat resolved from nodes")

local invalidRequest = serviceApi.RequestWildlifeDisturbance(nil)
assertFalse(invalidRequest.accepted, "invalid disturbance request rejected")
assertEqual(invalidRequest.reason, "request_invalid", "invalid disturbance reason")

local missingWildlife = serviceApi.RequestWildlifeDisturbance({
	wildlifeId = "missing",
	userId = 1,
})
assertFalse(missingWildlife.accepted, "missing wildlife rejected")
assertEqual(missingWildlife.reason, "wildlife_not_found", "missing wildlife reason")

local disturbed = serviceApi.RequestWildlifeDisturbance({
	wildlifeId = initial.records[1].wildlifeId,
	userId = 9001,
	position = { X = 12, Y = 0, Z = 12 },
})
assertTrue(disturbed.accepted, "disturbance accepted")
assertEqual(disturbed.reason, "disturbed", "disturbance reason")
assertEqual(disturbed.snapshot.status, "disturbed", "disturbance status")

local farDisturbance = serviceApi.RequestWildlifeDisturbance({
	wildlifeId = initial.records[2].wildlifeId,
	userId = 9002,
	position = { X = 200, Y = 0, Z = 200 },
})
assertFalse(farDisturbance.accepted, "out of range disturbance rejected")
assertEqual(farDisturbance.reason, "disturbance_out_of_range", "out of range disturbance reason")

local missingPositionDisturbance = serviceApi.RequestWildlifeDisturbance({
	wildlifeId = initial.records[2].wildlifeId,
	userId = 9003,
})
assertFalse(missingPositionDisturbance.accepted, "missing position disturbance rejected")
assertEqual(missingPositionDisturbance.reason, "disturbance_position_required", "missing position disturbance reason")

assertEqual(#recordedEvents, 1, "disturbance emits one clue event")
assertEqual(recordedEvents[1].category, "wildlife", "clue category")
assertEqual(recordedEvents[1].metadata.clueTag, "wildlife_disturbed", "clue tag")
assertEqual(recordedEvents[1].metadata.anchorZoneId, "shoreline", "clue metadata zone id")
assertTrue(type(recordedEvents[1].metadata.anchorBucketId) == "string", "clue metadata anchor bucket id")
assertTrue(recordedEvents[1].metadata.userId == nil, "clue metadata omits actor id")
assertTrue(recordedEvents[1].metadata.position == nil, "clue metadata omits exact position")
assertTrue(recordedEvents[1].metadata.anchorX == nil, "clue metadata omits exact anchor x")
assertTrue(recordedEvents[1].metadata.anchorZ == nil, "clue metadata omits exact anchor z")

local invalidInteraction = serviceApi.RequestWildlifeInteraction(nil)
assertFalse(invalidInteraction.accepted, "invalid interaction request rejected")
assertEqual(invalidInteraction.reason, "request_invalid", "invalid interaction reason")

local forbiddenInteraction = serviceApi.RequestWildlifeInteraction({
	wildlifeId = initial.records[1].wildlifeId,
	actorUserId = 7001,
	outcome = "feed_denied",
})
assertFalse(forbiddenInteraction.accepted, "non giant interaction rejected")
assertEqual(forbiddenInteraction.reason, "actor_role_forbidden", "non giant interaction reason")

local invalidOutcomeInteraction = serviceApi.RequestWildlifeInteraction({
	wildlifeId = initial.records[1].wildlifeId,
	actorUserId = 9001,
	outcome = "unknown_outcome",
})
assertFalse(invalidOutcomeInteraction.accepted, "invalid outcome rejected")
assertEqual(invalidOutcomeInteraction.reason, "interaction_outcome_invalid", "invalid outcome reason")

local feedAccepted = serviceApi.RequestWildlifeInteraction({
	wildlifeId = initial.records[1].wildlifeId,
	actorUserId = 9001,
	outcome = "feed_accepted",
})
assertTrue(feedAccepted.accepted, "feed accepted interaction")
assertEqual(feedAccepted.reason, "feed_accepted", "feed accepted reason")
assertEqual(feedAccepted.snapshot.status, "despawned", "feed accepted despawns wildlife")

local feedCapReached = serviceApi.RequestWildlifeInteraction({
	wildlifeId = initial.records[2].wildlifeId,
	actorUserId = 9001,
	outcome = "feed_accepted",
})
assertFalse(feedCapReached.accepted, "feed cap reached rejected")
assertEqual(feedCapReached.reason, "feed_cap_reached", "feed cap reached reason")

local feedDenied = serviceApi.RequestWildlifeInteraction({
	wildlifeId = initial.records[2].wildlifeId,
	actorUserId = 9002,
	outcome = "feed_denied",
})
assertTrue(feedDenied.accepted, "feed denied interaction accepted")
assertEqual(feedDenied.reason, "feed_denied", "feed denied reason")
assertTrue(feedDenied.snapshot.active, "feed denied keeps wildlife active")

local dispersed = serviceApi.RequestWildlifeInteraction({
	wildlifeId = initial.records[2].wildlifeId,
	actorUserId = 9002,
	outcome = "wildlife_dispersed",
})
assertTrue(dispersed.accepted, "wildlife dispersed interaction accepted")
assertEqual(dispersed.reason, "wildlife_dispersed", "wildlife dispersed reason")
assertEqual(dispersed.snapshot.status, "despawned", "wildlife dispersed despawns wildlife")

local ineligibleInteraction = serviceApi.RequestWildlifeInteraction({
	wildlifeId = initial.records[2].wildlifeId,
	actorUserId = 9002,
	outcome = "feed_denied",
})
assertFalse(ineligibleInteraction.accepted, "ineligible interaction rejected")
assertEqual(ineligibleInteraction.reason, "wildlife_ineligible", "ineligible interaction reason")

assertEqual(#scoreRequests, 1, "feed accepted triggers one score request")
assertEqual(scoreRequests[1].userId, 9001, "score request user id")
assertEqual(scoreRequests[1].eventId, "wildlife_feed", "score request event id")
assertEqual(scoreRequests[1].metadata.anchorZoneId, "shoreline", "score metadata coarse zone")
assertTrue(scoreRequests[1].metadata.anchorX == nil, "score metadata omits exact anchor x")
assertTrue(scoreRequests[1].metadata.anchorZ == nil, "score metadata omits exact anchor z")

local hasFeedClue = false
local hasFeedDeniedClue = false
local hasDispersedClue = false
for _, event in ipairs(recordedEvents) do
	if event.metadata.clueTag == "wildlife_feed" then
		hasFeedClue = true
	end
	if event.metadata.clueTag == "wildlife_feed_denied" then
		hasFeedDeniedClue = true
	end
	if event.metadata.clueTag == "wildlife_dispersed" then
		hasDispersedClue = true
	end
	assertTrue(event.metadata.userId == nil, "all clue metadata omits actor id")
	assertTrue(event.metadata.position == nil, "all clue metadata omits exact position")
end
assertTrue(hasFeedClue, "feed clue emitted")
assertTrue(hasFeedDeniedClue, "feed denied clue emitted")
assertTrue(hasDispersedClue, "dispersed clue emitted")

local tickAt101 = serviceApi.Tick({ at = 101 })
assertTrue(tickAt101.accepted, "tick accepted")
local afterShortTick = serviceApi.GetWildlifeSnapshot()
assertEqual(afterShortTick.activeCount, 0, "short tick keeps empty active count before respawn window")

now = 140
local tickAt140 = serviceApi.Tick({ at = 140 })
assertTrue(tickAt140.accepted, "long tick accepted")
local afterExpiryTick = serviceApi.GetWildlifeSnapshot()
assertTrue(afterExpiryTick.activeCount >= 1, "expiry tick maintains population")

local diagnostics = serviceApi.GetWildlifeDiagnostics()
assertTrue(diagnostics.spawnAttempts >= 2, "diagnostics spawn attempts")
assertTrue(diagnostics.spawnSucceeded >= 2, "diagnostics spawn succeeded")
assertTrue(diagnostics.disturbanceAttempts >= 5, "diagnostics disturbance attempts")
assertTrue(diagnostics.disturbanceSucceeded >= 1, "diagnostics disturbance succeeded")
assertTrue(diagnostics.disturbanceRangeChecks >= 3, "diagnostics disturbance range checks")
assertTrue(diagnostics.disturbanceRangeRejected >= 1, "diagnostics disturbance range rejected")
assertTrue(diagnostics.disturbanceMissingPositionRejected >= 1, "diagnostics disturbance missing position rejected")
assertTrue(diagnostics.interactionAttempts >= 8, "diagnostics interaction attempts")
assertTrue(diagnostics.interactionSucceeded >= 3, "diagnostics interaction succeeded")
assertTrue(diagnostics.interactionFailed >= 5, "diagnostics interaction failed")
assertTrue(diagnostics.interactionFeedAccepted >= 1, "diagnostics interaction feed accepted")
assertTrue(diagnostics.interactionFeedDenied >= 1, "diagnostics interaction feed denied")
assertTrue(diagnostics.interactionDispersed >= 1, "diagnostics interaction dispersed")
assertTrue(diagnostics.feedGrantAttempts >= 2, "diagnostics feed grant attempts")
assertTrue(diagnostics.feedGrantSucceeded >= 1, "diagnostics feed grant succeeded")
assertTrue(diagnostics.feedGrantCapped >= 1, "diagnostics feed grant capped")
assertTrue(diagnostics.expiryCount >= 0, "diagnostics expiry count tracked")
assertTrue(diagnostics.despawnCount >= 2, "diagnostics despawn count")
assertTrue(diagnostics.clueEventsAttempted >= 1, "diagnostics clue attempts")
assertTrue(diagnostics.clueEventsSucceeded >= 1, "diagnostics clue succeeded")
assertEqual(diagnostics.habitatSource, "workspace_nodes", "diagnostics habitat source")
assertTrue(diagnostics.habitatNodeCount >= 2, "diagnostics habitat node count")
assertTrue(diagnostics.habitatGroupCount >= 1, "diagnostics habitat group count")
assertTrue(diagnostics.anchorResolvedCount >= 1, "diagnostics anchor resolved count")
assertEqual(diagnostics.anchorFallbackCount, 0, "diagnostics anchor fallback count")
assertEqual(diagnostics.lastAnchorZoneId, "shoreline", "diagnostics last anchor zone id")
assertTrue(type(diagnostics.lastAnchorBucketId) == "string", "diagnostics last anchor bucket id")
assertEqual(diagnostics.lastInteractionOutcome, "wildlife_dispersed", "diagnostics last interaction outcome")

serviceApi.ResetForTests()
local resetSnapshot = serviceApi.GetWildlifeSnapshot()
assertEqual(resetSnapshot.activeCount, 0, "reset clears records")

resetGlobals()

print("neutral_wildlife_service_runtime_entrypoint: all checks passed")
